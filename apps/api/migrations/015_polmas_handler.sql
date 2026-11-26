-- Polmas Keamanan: penanggung jawab laporan. Satu SOS bisa memanggil beberapa penerima (satpam, ketua RT,
-- Bhabinkamtibmas); yang pertama menekan "Terima" menjadi penanggung jawab, penerima lain bisa "Ambil alih".
ALTER TABLE pk_responses DROP CONSTRAINT pk_responses_action_check;
ALTER TABLE pk_responses ADD CONSTRAINT pk_responses_action_check
  CHECK (action IN ('terima','hubungi','verifikasi','tangani','selesai','tidak_valid','catatan','ambil_alih'));
COMMENT ON COLUMN pk_responses.action IS 'terima → acknowledged (+ penanggung jawab), ambil_alih = penanggung jawab pindah ke penerima ini, verifikasi → verified_at, tangani → in_progress, selesai → resolved, tidak_valid → false_alarm, hubungi/catatan = tanpa ubah status.';
CREATE INDEX IF NOT EXISTS pk_responses_handler_idx ON pk_responses (report_id, created_at DESC) WHERE action IN ('terima','ambil_alih');
