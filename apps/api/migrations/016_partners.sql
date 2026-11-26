-- API mitra /partner/v1 (docs/INTEGRASI_POLMAS.md §3c): Polmas Digital membaca laporan lintas tenant lewat kunci
-- ptk_live_, dibatasi RLS ke laporan live dari app yang memilih pilar Polmas dan ke wilayah mitra.

CREATE TABLE partners (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  max_scope   text REFERENCES wilayah(kode),
  disabled_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE partners IS 'Mitra lintas tenant (mis. Polmas Digital). Tanpa RLS: dicari sebelum konteks diketahui, seperti api_keys.';
COMMENT ON COLUMN partners.max_scope IS 'Prefiks kode wilayah terluas yang boleh dibaca mitra (32 = Jawa Barat, 32.71 = Kota Bogor). NULL = nasional.';

CREATE TABLE partner_keys (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id   uuid NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  prefix       text NOT NULL,
  key_hash     text NOT NULL UNIQUE,
  revoked_at   timestamptz,
  last_used_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON partner_keys (partner_id);
COMMENT ON COLUMN partner_keys.prefix IS 'Awal kunci yang aman ditampilkan (ptk_live_XXXX); kunci utuh hanya ditampilkan sekali saat dibuat.';
COMMENT ON COLUMN partner_keys.key_hash IS 'sha256 kunci ptk_live_; kunci asli tidak disimpan.';

CREATE OR REPLACE FUNCTION app_current_partner() RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.partner_id', true), '')::uuid $$;
CREATE OR REPLACE FUNCTION app_partner_scope() RETURNS text
LANGUAGE sql STABLE AS $$ SELECT coalesce(current_setting('app.partner_scope', true), '') $$;
COMMENT ON FUNCTION app_partner_scope() IS 'Prefiks wilayah transaksi withPartner(); string kosong = nasional.';

-- Hanya SELECT: mitra menulis lewat changeReport() setelah transaksi beralih ke konteks tenant pemilik laporan.
-- Laporan tanpa kecamatan (belum/tidak bisa ditentukan dari GPS) hanya terlihat oleh cakupan nasional.
CREATE POLICY partner_read ON reports FOR SELECT USING (
  app_current_partner() IS NOT NULL
  AND mode = 'live'
  AND EXISTS (SELECT 1 FROM apps a WHERE a.id = reports.app_id AND a.polmas_source IS NOT NULL AND a.disabled_at IS NULL)
  AND (app_partner_scope() = '' OR (kecamatan_code IS NOT NULL AND (kecamatan_code = app_partner_scope() OR kecamatan_code LIKE app_partner_scope() || '.%')))
);
COMMENT ON POLICY partner_read ON reports IS
  'Mitra (app.partner_id) hanya membaca laporan live dari app berpilar Polmas, di dalam prefiks wilayah app.partner_scope.';

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['report_events','report_locations','report_media']
  LOOP
    EXECUTE format($p$CREATE POLICY partner_read ON %I FOR SELECT
      USING (app_current_partner() IS NOT NULL AND EXISTS (SELECT 1 FROM reports r WHERE r.id = %I.report_id))$p$, t, t);
    EXECUTE format($c$COMMENT ON POLICY partner_read ON %I IS
      'Mitra hanya membaca baris milik laporan yang lolos partner_read di reports.'$c$, t);
  END LOOP;
END $$;

ALTER TABLE report_events DROP CONSTRAINT report_events_actor_kind_check;
ALTER TABLE report_events ADD CONSTRAINT report_events_actor_kind_check
  CHECK (actor_kind IN ('user','reporter','server','system','responder','partner'));
COMMENT ON COLUMN report_events.actor_kind IS 'reporter = pengguna akhir lewat SDK, server = backend klien lewat secret key, responder = satpam/nomor darurat yang login di app, partner = mitra (Polmas Digital) lewat /partner/v1.';

ALTER TABLE audit_logs DROP CONSTRAINT audit_logs_actor_kind_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_actor_kind_check
  CHECK (actor_kind IN ('user','platform_admin','system','server','partner'));
