-- Penerima SOS via WhatsApp (gaya tata-warga): nomor yang diatur pemilik app di portal, plus kontak darurat
-- pribadi yang dikirim pelapor bersama laporan SOS.
CREATE TABLE sos_recipients (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id  uuid NOT NULL REFERENCES accounts(id),
  app_id      uuid NOT NULL REFERENCES apps(id) ON DELETE CASCADE,
  source_id   uuid REFERENCES sources(id) ON DELETE CASCADE,
  name        text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  phone       text NOT NULL CHECK (phone ~ '^62[0-9]{8,13}$'),
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);
-- Satu nomor sekali per cakupan (seluruh app, atau satu source).
CREATE UNIQUE INDEX sos_recipients_scope_phone ON sos_recipients (app_id, coalesce(source_id, '00000000-0000-0000-0000-000000000000'::uuid), phone);
CREATE INDEX ON sos_recipients (app_id, active);

COMMENT ON TABLE sos_recipients IS 'Penerima SOS: nomor WhatsApp yang dikabari tiap laporan SOS live dari app ini (bukan pengaduan). Diatur pemilik app di portal.';
COMMENT ON COLUMN sos_recipients.source_id IS 'NULL = menerima SOS dari semua source app; terisi = hanya SOS dari source itu (mis. satu outlet).';
COMMENT ON COLUMN sos_recipients.phone IS 'Nomor WhatsApp ternormalisasi 62xxxxxxxxxx (08xx / +62 diubah saat disimpan).';

ALTER TABLE sos_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_recipients FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON sos_recipients
  USING (app_is_platform() OR account_id = app_current_account())
  WITH CHECK (app_is_platform() OR account_id = app_current_account());
COMMENT ON POLICY tenant_isolation ON sos_recipients IS
  'Baris hanya terlihat bila account_id = app.account_id transaksi, atau sesi admin platform (app.platform=on).';

ALTER TABLE reports ADD COLUMN emergency_contacts jsonb;
COMMENT ON COLUMN reports.emergency_contacts IS 'Kontak darurat pribadi pelapor yang dikirim SDK bersama SOS ([{name, phone}], maks. 5, phone 62xx). Ikut dikabari WhatsApp; disimpan untuk jejak siapa yang dihubungi.';
