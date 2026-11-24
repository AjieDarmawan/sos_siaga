-- Retensi data laporan per app + hapus data pengguna akhir (UU PDP).

ALTER TABLE apps ADD COLUMN retention_days int CHECK (retention_days BETWEEN 30 AND 3650);
COMMENT ON COLUMN apps.retention_days IS
  'Laporan live berstatus akhir (resolved/cancelled/false_alarm) dihapus permanen (beserta lokasi, timeline, media) N hari setelah ditutup. NULL = disimpan tanpa batas. Laporan mode test selalu dihapus 30 hari setelah ditutup.';

-- Laporan yang dihapus tidak boleh terhalang riwayat webhook; log pengiriman tetap ada tanpa tautan laporan.
ALTER TABLE webhook_deliveries DROP CONSTRAINT webhook_deliveries_report_id_fkey;
ALTER TABLE webhook_deliveries ADD CONSTRAINT webhook_deliveries_report_id_fkey
  FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE SET NULL;

-- Pencarian laporan basi oleh job retensi.
CREATE INDEX reports_closed_idx ON reports (app_id, resolved_at) WHERE resolved_at IS NOT NULL;
-- Hapus data per pengguna akhir (DELETE /v1/reporters/:ref).
CREATE INDEX reports_reporter_ref_idx ON reports (app_id, reporter_ref) WHERE reporter_ref IS NOT NULL;
