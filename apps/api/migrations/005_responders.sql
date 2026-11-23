-- Satpam / penerima darurat yang login di app klien (mis. POS: tombol "Login Security" di layar login).
-- Yang boleh login = nomor yang dimasukkan pelapor di Nomor Darurat. Supaya server tahu nomor itu sebelum SOS
-- pertama, daftar Nomor Darurat perangkat disinkronkan ke tabel `emergency_contacts`. Login lewat OTP WhatsApp,
-- lalu perangkat satpam mendaftarkan token FCM; tiap SOS yang menyebut nomornya mengirim push + sirene.

-- ---------------------------------------------------------------- Nomor Darurat (salinan server)
CREATE TABLE emergency_contacts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id),
  app_id        uuid NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
  reporter_ref  text NOT NULL CHECK (length(reporter_ref) BETWEEN 1 AND 128),
  reporter_name text,
  source_id     uuid REFERENCES sources(id) ON DELETE SET NULL,
  name          text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  role          text CHECK (role IS NULL OR length(role) <= 40),
  phone         text NOT NULL CHECK (phone ~ '^62[0-9]{8,13}$'),
  active        boolean NOT NULL DEFAULT true,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (app_id, reporter_ref, phone)
);
CREATE INDEX ON emergency_contacts (app_id, phone);

COMMENT ON TABLE emergency_contacts IS 'Nomor Darurat pribadi pelapor, disinkronkan SDK (PUT /v1/sdk/contacts, ganti total per reporter_ref). Sumber daftar nomor yang boleh login sebagai responder (satpam). WA/push per SOS tetap memakai snapshot reports.emergency_contacts.';
COMMENT ON COLUMN emergency_contacts.reporter_ref IS 'reporter.ref dari SDK (id pengguna di app klien, mis. "<tenant>:<email>" kasir POS).';
COMMENT ON COLUMN emergency_contacts.role IS 'Jabatan/hubungan bebas dari app, mis. Satpam, Pemilik toko, Keluarga.';
COMMENT ON COLUMN emergency_contacts.source_id IS 'Source (outlet) pelapor saat terakhir sinkron; untuk label di app satpam.';

ALTER TABLE emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_contacts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON emergency_contacts
  USING (app_is_platform() OR account_id = app_current_account())
  WITH CHECK (app_is_platform() OR account_id = app_current_account());
COMMENT ON POLICY tenant_isolation ON emergency_contacts IS
  'Baris hanya terlihat bila account_id = app.account_id transaksi, atau sesi admin platform (app.platform=on).';

-- ---------------------------------------------------------------- OTP login responder
CREATE TABLE responder_otps (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id  uuid NOT NULL REFERENCES accounts(id),
  app_id      uuid NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
  phone       text NOT NULL,
  code_hash   text NOT NULL,
  attempts    int NOT NULL DEFAULT 0,
  expires_at  timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON responder_otps (app_id, phone, created_at DESC);
COMMENT ON TABLE responder_otps IS 'Kode OTP WhatsApp untuk login responder. Hanya hash yang disimpan; berlaku 5 menit, maks. 5 percobaan.';
COMMENT ON COLUMN responder_otps.code_hash IS 'sha256(id || kode): kode 6 digit tidak pernah disimpan polos.';

ALTER TABLE responder_otps ENABLE ROW LEVEL SECURITY;
ALTER TABLE responder_otps FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON responder_otps
  USING (app_is_platform() OR account_id = app_current_account())
  WITH CHECK (app_is_platform() OR account_id = app_current_account());
COMMENT ON POLICY tenant_isolation ON responder_otps IS
  'Baris hanya terlihat bila account_id = app.account_id transaksi, atau sesi admin platform (app.platform=on).';

-- ---------------------------------------------------------------- sesi + perangkat responder
CREATE TABLE responder_sessions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id   uuid NOT NULL REFERENCES accounts(id),
  app_id       uuid NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
  phone        text NOT NULL,
  token_hash   text NOT NULL UNIQUE,
  fcm_token    text,
  platform     text CHECK (platform IN ('android','ios','web','other')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at   timestamptz
);
CREATE INDEX ON responder_sessions (app_id, phone) WHERE revoked_at IS NULL;
COMMENT ON TABLE responder_sessions IS 'Satu baris per perangkat satpam yang login. Token sesi (rsp_...) hanya disimpan hash-nya; tidak kedaluwarsa, berakhir saat logout atau nomornya dihapus dari semua Nomor Darurat.';
COMMENT ON COLUMN responder_sessions.fcm_token IS 'Token Firebase Cloud Messaging perangkat; dikosongkan otomatis bila FCM menjawab UNREGISTERED.';

ALTER TABLE responder_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE responder_sessions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON responder_sessions
  USING (app_is_platform() OR account_id = app_current_account())
  WITH CHECK (app_is_platform() OR account_id = app_current_account());
COMMENT ON POLICY tenant_isolation ON responder_sessions IS
  'Baris hanya terlihat bila account_id = app.account_id transaksi, atau sesi admin platform (app.platform=on).';

-- Laporan yang menyebut nomor satpam (snapshot kontak darurat saat SOS) dicari dengan @>.
CREATE INDEX reports_emergency_contacts_gin ON reports USING gin (emergency_contacts jsonb_path_ops);

-- Satpam yang menanggapi lewat app dicatat sebagai actor 'responder' (bukan user portal).
ALTER TABLE report_events DROP CONSTRAINT report_events_actor_kind_check;
ALTER TABLE report_events ADD CONSTRAINT report_events_actor_kind_check
  CHECK (actor_kind IN ('user','reporter','server','system','responder'));
COMMENT ON COLUMN report_events.actor_kind IS 'reporter = pengguna akhir lewat SDK, server = backend klien lewat secret key, responder = satpam/nomor darurat yang login di app.';
