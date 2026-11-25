-- Polmas Keamanan: aplikasi penerima SOS & laporan dari lima aplikasi Polmas Digital (Warga, Kantor, UMKM, Sekolah,
-- Komunitas). Aplikasi sumber = app SiagaSOS biasa yang ditandai `apps.polmas_source`; laporannya dibaca lintas tenant
-- per kecamatan. Pengguna Polmas Keamanan login dengan nomor telepon + password (akun dibuat admin, tanpa daftar mandiri).

-- ---------------------------------------------------------------- aplikasi sumber
ALTER TABLE apps ADD COLUMN polmas_source text CHECK (polmas_source IN ('warga','kantor','umkm','sekolah','komunitas'));
COMMENT ON COLUMN apps.polmas_source IS
  'Jenis aplikasi sumber Polmas Digital. NULL = laporan app ini TIDAK dibagikan ke Polmas Keamanan. Hanya laporan mode live yang dibagikan.';

-- ---------------------------------------------------------------- wilayah per laporan
ALTER TABLE reports
  ADD COLUMN kecamatan_code text REFERENCES wilayah(kode),
  ADD COLUMN kelurahan_code text REFERENCES wilayah(kode),
  ADD COLUMN area_source text CHECK (area_source IN ('gps','manual','seed')),
  ADD COLUMN area_checked_at timestamptz,
  ADD COLUMN verified_at timestamptz;
COMMENT ON COLUMN reports.kecamatan_code IS 'Kecamatan kejadian (kode wilayah level 3). Diisi worker Polmas Keamanan dari GPS setelah laporan tersimpan, bukan di request SOS.';
COMMENT ON COLUMN reports.kelurahan_code IS 'Desa/kelurahan kejadian (kode wilayah level 4), bila geocoder bisa mencocokkan.';
COMMENT ON COLUMN reports.area_source IS 'Asal kode wilayah: gps = reverse geocode koordinat, manual = dikoreksi petugas, seed = data demo.';
COMMENT ON COLUMN reports.area_checked_at IS 'Kapan worker terakhir mencoba mengisi wilayah (berhasil atau tidak). NULL = belum dicoba.';
COMMENT ON COLUMN reports.verified_at IS 'Diisi saat Bhabinkamtibmas menandai laporan "Diverifikasi" (status laporan tetap acknowledged).';
CREATE INDEX reports_kecamatan_idx ON reports (kecamatan_code, created_at DESC) WHERE kecamatan_code IS NOT NULL;
CREATE INDEX reports_area_pending_idx ON reports (created_at) WHERE area_checked_at IS NULL AND lat IS NOT NULL;

-- Nomor telepon apa pun (08…, +62…, 62…) → bentuk 62xxxxxxxx; dipakai untuk mencocokkan reporter_phone dengan akun.
CREATE OR REPLACE FUNCTION pk_norm_phone(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN d IS NULL OR d = '' THEN NULL
    WHEN d LIKE '0%' THEN '62' || substr(d, 2)
    WHEN d LIKE '8%' THEN '62' || d
    ELSE d END
  FROM (SELECT regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') AS d) x
$$;
COMMENT ON FUNCTION pk_norm_phone(text) IS 'Normalisasi nomor telepon Indonesia ke 62xxxxxxxx (tanpa +, spasi, tanda hubung).';

-- ---------------------------------------------------------------- pengguna, peran, sesi
CREATE TABLE pk_users (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone             text NOT NULL UNIQUE CHECK (phone ~ '^62[0-9]{8,13}$'),
  name              text NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  password_hash     text NOT NULL,
  area              jsonb,
  area_lat          double precision,
  area_lng          double precision,
  area_confirmed_at timestamptz,
  notif_seen_at     timestamptz NOT NULL DEFAULT now(),
  is_demo           boolean NOT NULL DEFAULT false,
  failed_logins     int NOT NULL DEFAULT 0,
  locked_until      timestamptz,
  disabled_at       timestamptz,
  last_login_at     timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE pk_users IS 'Akun Polmas Keamanan. Identitas = nomor telepon. Dibuat admin (pnpm pk:user / seed), tidak ada pendaftaran mandiri.';
COMMENT ON COLUMN pk_users.area IS 'Wilayah yang dikonfirmasi pengguna saat login: {province, regency, district, village} masing-masing {code, name}. district menentukan kecamatan yang laporannya tampil.';
COMMENT ON COLUMN pk_users.notif_seen_at IS 'Notifikasi yang dibuat setelah waktu ini dihitung belum dibaca (tombol "Tandai semua dibaca").';
COMMENT ON COLUMN pk_users.is_demo IS 'Akun demo fase 1: aplikasi menampilkan pita DEMO dan boleh memakai simulasi SOS.';
COMMENT ON COLUMN pk_users.locked_until IS 'Dikunci sementara setelah 5 password salah berturut-turut (15 menit).';

CREATE TABLE pk_user_roles (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES pk_users(id) ON DELETE CASCADE,
  role           text NOT NULL CHECK (role IN ('warga','kantor','umkm','sekolah','komunitas','bhabinkamtibmas')),
  kecamatan_code text REFERENCES wilayah(kode),
  kelurahan_code text REFERENCES wilayah(kode),
  unit           text CHECK (unit IS NULL OR length(unit) <= 120),
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role, kecamatan_code)
);
CREATE INDEX ON pk_user_roles (kecamatan_code, role);
COMMENT ON TABLE pk_user_roles IS 'Satu nomor boleh punya beberapa peran & wilayah (FR-12). Semua peran melihat laporan kecamatannya; hanya bhabinkamtibmas yang menanggapi.';
COMMENT ON COLUMN pk_user_roles.kecamatan_code IS 'Wilayah tugas tetap (wajib untuk bhabinkamtibmas). NULL = ikut wilayah yang dikonfirmasi pengguna saat login.';
COMMENT ON COLUMN pk_user_roles.unit IS 'Nama instansi/organisasi, mis. "Polsek Bogor Tengah", "SDN Pabaton 1", "Toko Sinar Jaya".';

CREATE TABLE pk_sessions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES pk_users(id) ON DELETE CASCADE,
  role_id      uuid NOT NULL REFERENCES pk_user_roles(id) ON DELETE CASCADE,
  token_hash   text NOT NULL UNIQUE,
  platform     text CHECK (platform IN ('android','ios','web','other')),
  fcm_token    text,
  expires_at   timestamptz NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz
);
CREATE INDEX ON pk_sessions (user_id) WHERE revoked_at IS NULL;
COMMENT ON TABLE pk_sessions IS 'Sesi perangkat. Token pks_… hanya disimpan hash sha256-nya; berlaku 12 jam (token berumur pendek, login cepat memakai kredensial tersimpan di perangkat).';
COMMENT ON COLUMN pk_sessions.role_id IS 'Peran aktif sesi ini; bisa diganti lewat POST /v1/pk/me/role.';

-- ---------------------------------------------------------------- tanggapan Bhabinkamtibmas (data tenant)
CREATE TABLE pk_responses (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id  uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  account_id uuid NOT NULL REFERENCES accounts(id),
  user_id    uuid REFERENCES pk_users(id) ON DELETE SET NULL,
  officer    text NOT NULL,
  action     text NOT NULL CHECK (action IN ('terima','hubungi','verifikasi','tangani','selesai','tidak_valid','catatan')),
  note       text CHECK (note IS NULL OR length(note) <= 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON pk_responses (report_id, created_at);
CREATE INDEX ON pk_responses (user_id, created_at DESC);
COMMENT ON TABLE pk_responses IS 'Tanggapan petugas Polmas Keamanan (FR-17). Setiap baris juga menulis report_events lewat changeReport, jadi status kembali ke aplikasi sumber.';
COMMENT ON COLUMN pk_responses.officer IS 'Nama + unit petugas saat menanggapi (salinan, tetap ada bila akun dihapus).';
COMMENT ON COLUMN pk_responses.action IS 'terima → acknowledged, verifikasi → verified_at, tangani → in_progress, selesai → resolved, tidak_valid → false_alarm, hubungi/catatan = tanpa ubah status.';

ALTER TABLE pk_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE pk_responses FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON pk_responses
  USING (app_is_platform() OR account_id = app_current_account())
  WITH CHECK (app_is_platform() OR account_id = app_current_account());
COMMENT ON POLICY tenant_isolation ON pk_responses IS
  'Baris hanya terlihat bila account_id = app.account_id transaksi, atau sesi platform (app.platform=on, dipakai API Polmas Keamanan).';

-- Satu SOS masuk yang sudah diterima/diabaikan pengguna tidak berdering lagi di perangkatnya.
CREATE TABLE pk_call_dismissals (
  user_id    uuid NOT NULL REFERENCES pk_users(id) ON DELETE CASCADE,
  report_id  uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  action     text NOT NULL CHECK (action IN ('accepted','ignored')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, report_id)
);
COMMENT ON TABLE pk_call_dismissals IS 'Panggilan SOS yang sudah dijawab (Terima/Abaikan) per pengguna, supaya layar panggilan tidak muncul ulang.';

-- ---------------------------------------------------------------- berita & audit
CREATE TABLE pk_news (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kecamatan_code text REFERENCES wilayah(kode),
  category       text NOT NULL DEFAULT 'kabar' CHECK (category IN ('kabar','pengumuman','imbauan')),
  title          text NOT NULL CHECK (length(title) BETWEEN 3 AND 160),
  summary        text,
  body           text,
  author         text,
  is_demo        boolean NOT NULL DEFAULT false,
  published_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON pk_news (kecamatan_code, published_at DESC);
COMMENT ON TABLE pk_news IS 'Kabar & pengumuman keamanan (tab Berita, FR-11). kecamatan_code NULL = tampil di semua wilayah.';

CREATE TABLE pk_audit (
  id         bigserial PRIMARY KEY,
  user_id    uuid REFERENCES pk_users(id) ON DELETE SET NULL,
  action     text NOT NULL,
  report_id  uuid,
  detail     jsonb,
  ip         inet,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON pk_audit (report_id, created_at);
COMMENT ON TABLE pk_audit IS 'Log audit Polmas Keamanan (FR-14): login, buka detail/bukti, perubahan status. report_id tanpa FK supaya log tetap ada setelah laporan dihapus retensi.';

-- Tabel platform (bukan milik tenant): hanya bisa dibaca/ditulis dalam withPlatform().
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['pk_users','pk_user_roles','pk_sessions','pk_call_dismissals','pk_news','pk_audit'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format($p$CREATE POLICY platform_only ON %I USING (app_is_platform()) WITH CHECK (app_is_platform())$p$, t);
    EXECUTE format($p$COMMENT ON POLICY platform_only ON %I IS 'Tabel platform Polmas Keamanan: hanya terlihat dalam withPlatform() (app.platform=on).'$p$, t);
  END LOOP;
END $$;
