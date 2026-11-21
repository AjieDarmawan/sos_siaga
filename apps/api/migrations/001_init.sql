-- SiagaSOS — skema awal (M1)
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Konteks tenant di-set per transaksi oleh API: SELECT set_config('app.account_id', '<uuid>', true).
-- Admin platform memakai set_config('app.platform', 'on', true). Tanpa keduanya, tabel ber-RLS tampak kosong.
CREATE OR REPLACE FUNCTION app_current_account() RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.account_id', true), '')::uuid $$;

CREATE OR REPLACE FUNCTION app_is_platform() RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT coalesce(current_setting('app.platform', true), '') = 'on' $$;

-- ---------------------------------------------------------------- akun perusahaan
CREATE TABLE accounts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_name    text NOT NULL,
  entity_type   text NOT NULL CHECK (entity_type IN ('pt','cv','yayasan','koperasi','lainnya')),
  nib           text NOT NULL UNIQUE,
  npwp          text NOT NULL,
  address       text NOT NULL,
  phone         text,
  website       text,
  industry      text,
  est_users     int,
  usage_plan    text,
  pic_is_director boolean NOT NULL DEFAULT true,
  status        text NOT NULL DEFAULT 'pending_email'
                CHECK (status IN ('pending_email','pending_review','needs_revision',
                                  'approved','rejected','suspended')),
  status_note   text,
  risk_flags    text[] NOT NULL DEFAULT '{}',
  plan          text NOT NULL DEFAULT 'free',
  submitted_at  timestamptz,
  approved_at   timestamptz,
  rejected_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX accounts_review_queue ON accounts (submitted_at) WHERE status = 'pending_review';
COMMENT ON TABLE accounts IS 'Perusahaan klien. Hanya status approved yang boleh memakai kunci live.';
COMMENT ON COLUMN accounts.status_note IS 'Catatan admin terakhir (alasan revisi/tolak/bekukan), ditampilkan di halaman status PIC.';
COMMENT ON COLUMN accounts.risk_flags IS 'Tanda risiko otomatis saat registrasi, mis. free_email_domain.';
COMMENT ON COLUMN accounts.submitted_at IS 'Waktu terakhir diajukan ke review; dasar urutan antrean (terlama dulu) dan SLA 2 hari kerja.';
COMMENT ON COLUMN accounts.pic_is_director IS 'false = PIC bukan direksi, sehingga surat kuasa bermaterai wajib diunggah.';
COMMENT ON COLUMN accounts.rejected_at IS 'Dasar aturan daftar ulang: NIB yang sama boleh mendaftar lagi setelah 30 hari.';

CREATE TABLE account_documents (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id   uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  doc_type     text NOT NULL CHECK (doc_type IN ('nib','npwp','akta','sk_kemenkumham',
                                                 'ktp_pic','surat_kuasa','lainnya')),
  storage_key  text NOT NULL,
  original_name text,
  mime_type    text NOT NULL,
  size_bytes   int  NOT NULL,
  sha256       text NOT NULL,
  review_state text NOT NULL DEFAULT 'pending' CHECK (review_state IN ('pending','ok','rejected')),
  review_note  text,
  superseded_at timestamptz,
  uploaded_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON account_documents (account_id, doc_type) WHERE superseded_at IS NULL;
COMMENT ON COLUMN account_documents.storage_key IS 'Path di storage privat. File dienkripsi AES-256-GCM; tidak pernah punya URL publik.';
COMMENT ON COLUMN account_documents.superseded_at IS 'Diisi saat dokumen jenis yang sama diunggah ulang (revisi). Versi lama disimpan untuk audit.';
COMMENT ON COLUMN account_documents.review_state IS 'rejected = admin menandai dokumen ini perlu diunggah ulang (F-26).';

CREATE TABLE platform_admins (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         citext UNIQUE NOT NULL,
  password_hash text NOT NULL,
  totp_secret   text NOT NULL,
  full_name     text NOT NULL DEFAULT '',
  role          text NOT NULL DEFAULT 'reviewer' CHECK (role IN ('reviewer','superadmin')),
  created_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE platform_admins IS 'Tim internal SiagaSOS, terpisah dari users klien. Login wajib TOTP.';

CREATE TABLE account_reviews (
  id          bigserial PRIMARY KEY,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL REFERENCES platform_admins(id),
  decision    text NOT NULL CHECK (decision IN ('approved','needs_revision','rejected',
                                               'suspended','reinstated')),
  reason      text,
  checklist   jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON COLUMN account_reviews.checklist IS 'Hasil checklist verifikasi per dokumen, mis. {"nib_oss":true,"akta_ahu":true}.';

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  email         citext UNIQUE NOT NULL,
  password_hash text NOT NULL,
  full_name     text NOT NULL,
  phone         text,
  position      text,
  email_verified_at timestamptz,
  role          text NOT NULL DEFAULT 'owner' CHECK (role IN ('owner','admin','responder')),
  disabled_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON users (account_id);

CREATE TABLE email_tokens (
  token_hash  text PRIMARY KEY,
  user_id     uuid REFERENCES users(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  purpose     text NOT NULL CHECK (purpose IN ('verify_email','invite')),
  email       citext,
  role        text,
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE email_tokens IS 'Token sekali pakai (sha256) untuk verifikasi email dan undangan responder.';

-- ---------------------------------------------------------------- app & kunci
CREATE TABLE apps (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id         uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name               text NOT NULL,
  allowed_origins    text[] NOT NULL DEFAULT '{}',
  allowed_bundle_ids text[] NOT NULL DEFAULT '{}',
  auto_create_sources boolean NOT NULL DEFAULT true,
  sdk_config         jsonb NOT NULL DEFAULT '{}',
  webhook_url        text,
  webhook_secret     text NOT NULL DEFAULT encode(gen_random_bytes(24), 'hex'),
  disabled_at        timestamptz,
  disabled_reason    text,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON apps (account_id);
COMMENT ON COLUMN apps.allowed_origins IS 'Origin web yang boleh memakai publishable key, mis. https://app.klien.com. Kosong = live ditolak.';
COMMENT ON COLUMN apps.allowed_bundle_ids IS 'applicationId/bundle id mobile, dicocokkan dengan header X-SOS-Bundle.';
COMMENT ON COLUMN apps.sdk_config IS 'Override GET /v1/sdk/config: categories, button_text, hold_seconds, recipient_text.';
COMMENT ON COLUMN apps.disabled_at IS 'Dinonaktifkan admin platform karena penyalahgunaan (F-19); semua kunci app ditolak.';

CREATE TABLE api_keys (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_id       uuid NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
  kind         text NOT NULL CHECK (kind IN ('publishable','secret')),
  mode         text NOT NULL CHECK (mode IN ('live','test')),
  prefix       text NOT NULL,
  key_hash     text NOT NULL UNIQUE,
  plain_key    text,
  revoked_at   timestamptz,
  expires_at   timestamptz,
  last_used_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (kind = 'publishable' OR plain_key IS NULL)
);
CREATE INDEX ON api_keys (app_id);
COMMENT ON COLUMN api_keys.key_hash IS 'sha256 hex dari kunci penuh; satu-satunya yang dicari saat autentikasi.';
COMMENT ON COLUMN api_keys.plain_key IS 'Hanya untuk publishable key (boleh disalin kapan saja). Secret key tidak pernah disimpan (CHECK).';
COMMENT ON COLUMN api_keys.expires_at IS 'Masa tenggang saat rotate: kunci lama tetap berlaku sampai waktu ini.';

CREATE TABLE sources (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_id      uuid NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  source_key  text NOT NULL,
  label       text,
  platform    text CHECK (platform IN ('web','android','ios','other')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (app_id, source_key)
);

-- ---------------------------------------------------------------- laporan
CREATE TABLE reports (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_id         uuid NOT NULL REFERENCES apps(id),
  account_id     uuid NOT NULL REFERENCES accounts(id),
  source_id      uuid REFERENCES sources(id),
  mode           text NOT NULL DEFAULT 'live' CHECK (mode IN ('live','test')),
  category       text NOT NULL DEFAULT 'general',
  status         text NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open','acknowledged','in_progress','resolved','cancelled','false_alarm')),
  status_message text,
  reporter_ref   text,
  reporter_name  text,
  reporter_phone text,
  message        text,
  lat            double precision,
  lng            double precision,
  accuracy_m     real,
  device         jsonb,
  metadata       jsonb,
  ip             inet,
  idempotency_key text NOT NULL,
  client_created_at timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  acknowledged_at timestamptz,
  resolved_at    timestamptz,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (app_id, idempotency_key)
);
CREATE INDEX ON reports (app_id, status, created_at DESC);
CREATE INDEX ON reports (account_id, created_at DESC);
COMMENT ON COLUMN reports.account_id IS 'Denormalisasi dari apps.account_id agar policy RLS tidak perlu join.';
COMMENT ON COLUMN reports.idempotency_key IS 'Dari header Idempotency-Key SDK. Retry dengan kunci sama mengembalikan laporan yang sama.';
COMMENT ON COLUMN reports.client_created_at IS 'Waktu tombol ditekan menurut perangkat; bisa jauh lebih awal dari created_at bila laporan tertahan di antrian offline.';
COMMENT ON COLUMN reports.status_message IS 'Teks untuk pengguna akhir di SDK, mis. "Petugas sedang menuju lokasi".';
COMMENT ON COLUMN reports.resolved_at IS 'Diisi saat status menjadi resolved, cancelled, atau false_alarm.';

CREATE TABLE report_locations (
  id          bigserial PRIMARY KEY,
  report_id   uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL REFERENCES accounts(id),
  lat         double precision NOT NULL,
  lng         double precision NOT NULL,
  accuracy_m  real,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON report_locations (report_id, recorded_at);

CREATE TABLE report_events (
  id          bigserial PRIMARY KEY,
  report_id   uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL REFERENCES accounts(id),
  actor_id    uuid REFERENCES users(id),
  actor_kind  text NOT NULL DEFAULT 'user' CHECK (actor_kind IN ('user','reporter','server','system')),
  type        text NOT NULL,
  from_status text,
  to_status   text,
  note        text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON report_events (report_id, created_at);
COMMENT ON COLUMN report_events.actor_kind IS 'reporter = pengguna akhir lewat SDK, server = backend klien lewat secret key.';

CREATE TABLE webhook_deliveries (
  id          bigserial PRIMARY KEY,
  app_id      uuid NOT NULL REFERENCES apps(id),
  account_id  uuid NOT NULL REFERENCES accounts(id),
  report_id   uuid REFERENCES reports(id),
  event       text NOT NULL,
  payload     jsonb NOT NULL,
  status_code int,
  attempts    int NOT NULL DEFAULT 0,
  last_error  text,
  next_retry_at timestamptz,
  delivered_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
  id          bigserial PRIMARY KEY,
  account_id  uuid,
  actor_kind  text NOT NULL CHECK (actor_kind IN ('user','platform_admin','system','server')),
  actor_id    uuid,
  action      text NOT NULL,
  target_type text,
  target_id   text,
  detail      jsonb,
  ip          inet,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON audit_logs (account_id, created_at DESC);
COMMENT ON TABLE audit_logs IS 'Jejak audit: keputusan review, akses dokumen, akses detail laporan, revoke kunci.';

-- ---------------------------------------------------------------- RLS
-- Tabel yang dicari sebelum tenant diketahui (accounts, users, apps, api_keys, email_tokens) tidak memakai RLS;
-- isolasinya di repository. Tabel data laporan & dokumen wajib RLS.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['account_documents','sources','reports','report_locations','report_events','webhook_deliveries']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I
      USING (app_is_platform() OR account_id = app_current_account())
      WITH CHECK (app_is_platform() OR account_id = app_current_account())$p$, t);
    EXECUTE format($c$COMMENT ON POLICY tenant_isolation ON %I IS
      'Baris hanya terlihat bila account_id = app.account_id transaksi, atau sesi admin platform (app.platform=on).'$c$, t);
  END LOOP;
END $$;
