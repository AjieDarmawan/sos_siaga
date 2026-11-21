-- Media laporan SOS (foto, video, rekaman suara). File ada di object storage (MinIO/S3), tabel ini hanya metadata.
CREATE TABLE report_media (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id    uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  account_id   uuid NOT NULL REFERENCES accounts(id),
  kind         text NOT NULL CHECK (kind IN ('image','video','audio')),
  content_type text NOT NULL,
  size_bytes   bigint NOT NULL CHECK (size_bytes > 0),
  duration_s   real,
  storage_key  text NOT NULL UNIQUE,
  status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','ready')),
  uploaded_by  text NOT NULL DEFAULT 'reporter' CHECK (uploaded_by IN ('reporter','user','server')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  uploaded_at  timestamptz
);
CREATE INDEX ON report_media (report_id, created_at);
CREATE INDEX ON report_media (status, created_at) WHERE status = 'pending';

COMMENT ON TABLE report_media IS 'Lampiran laporan SOS. Diunggah langsung dari perangkat ke object storage lewat presigned PUT; API tidak meneruskan byte file.';
COMMENT ON COLUMN report_media.storage_key IS 'Key objek di bucket S3_BUCKET: accounts/<account_id>/reports/<report_id>/<media_id>.<ext>. Bucket privat; dibaca lewat presigned GET berumur pendek.';
COMMENT ON COLUMN report_media.status IS 'pending = URL upload sudah diberikan, file belum dikonfirmasi; ready = HEAD objek cocok (ukuran & tipe) lalu tampil di dashboard.';
COMMENT ON COLUMN report_media.size_bytes IS 'Ukuran yang dideklarasikan klien saat meminta URL upload; diverifikasi ulang dengan HEAD objek saat complete.';
COMMENT ON COLUMN report_media.duration_s IS 'Durasi video/suara dalam detik bila dikirim klien (informasi tampilan saja).';

ALTER TABLE report_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_media FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON report_media
  USING (app_is_platform() OR account_id = app_current_account())
  WITH CHECK (app_is_platform() OR account_id = app_current_account());
COMMENT ON POLICY tenant_isolation ON report_media IS
  'Baris hanya terlihat bila account_id = app.account_id transaksi, atau sesi admin platform (app.platform=on).';
