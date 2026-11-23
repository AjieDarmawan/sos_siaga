-- Jenis laporan: SOS darurat atau pengaduan (non-darurat) dari tombol melayang SDK.
ALTER TABLE reports ADD COLUMN kind text NOT NULL DEFAULT 'sos' CHECK (kind IN ('sos','pengaduan'));
COMMENT ON COLUMN reports.kind IS 'sos = tombol darurat (notifikasi responder, lokasi live, bunyi di dashboard); pengaduan = laporan non-darurat dari menu "Laporan pengaduan" SDK, tanpa notifikasi darurat dan tanpa lokasi live.';
CREATE INDEX ON reports (account_id, kind, created_at DESC);
