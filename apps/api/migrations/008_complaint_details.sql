-- Detail pengaduan gaya Lapor Keamanan (judul, kronologi, lokasi, waktu, ciri pelaku, saksi).
-- Kolom baru & nullable: pengaduan lama dan SOS tidak terpengaruh.

ALTER TABLE reports ADD COLUMN complaint_details jsonb;
COMMENT ON COLUMN reports.complaint_details IS
  'Detail pengaduan dari SDK: {title, description, location_text, occurred_at, suspect, witness}. NULL untuk SOS dan pengaduan lama.';
