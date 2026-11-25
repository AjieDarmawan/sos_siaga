-- Polmas Keamanan = aplikasi penerima Nomor Darurat (docs/POLMAS_KEAMANAN.md): nomor yang diisi di menu Nomor Darurat
-- SDK (pemilik toko, satpam, ketua RT, …) bisa login, membuat password di login pertama, dan menanggapi SOS yang
-- memanggil nomornya. Peran diturunkan otomatis dari emergency_contacts setiap login.

ALTER TABLE pk_user_roles DROP CONSTRAINT pk_user_roles_role_check;
ALTER TABLE pk_user_roles ADD CONSTRAINT pk_user_roles_role_check
  CHECK (role IN ('penerima','warga','kantor','umkm','sekolah','komunitas','bhabinkamtibmas'));
COMMENT ON COLUMN pk_user_roles.role IS
  'penerima = pemilik Nomor Darurat (menanggapi SOS yang memanggil nomornya); bhabinkamtibmas = + semua laporan di kecamatannya; warga/kantor/umkm/sekolah/komunitas = melihat laporan kecamatan.';

ALTER TABLE pk_user_roles ADD COLUMN from_contact boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN pk_user_roles.from_contact IS
  'true = peran diturunkan otomatis dari emergency_contacts (disinkron ulang setiap login); false = dibuat admin (pnpm pk:user).';

-- Login pertama dari Nomor Darurat membuat akun sendiri; akun admin tetap ditandai.
ALTER TABLE pk_users ADD COLUMN created_via text NOT NULL DEFAULT 'admin' CHECK (created_via IN ('admin','contact','seed'));
COMMENT ON COLUMN pk_users.created_via IS 'admin = pnpm pk:user, contact = login pertama dengan nomor dari Nomor Darurat (membuat password sendiri), seed = data demo.';

-- Pencarian Nomor Darurat per nomor lintas app (cek login, sinkron peran).
CREATE INDEX IF NOT EXISTS emergency_contacts_phone_active_idx ON emergency_contacts (phone) WHERE active;
