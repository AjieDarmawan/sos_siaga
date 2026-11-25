-- Perangkat app Polmas Keamanan untuk push FCM SOS (docs/POLMAS_KEAMANAN.md §9: WA & sirene lokal diganti push +
-- sirene di app penerima). Token tidak diikat ke sesi 12 jam supaya SOS tetap sampai walau sesi sudah berakhir;
-- dihapus saat logout, "Lupakan perangkat", atau FCM menjawab UNREGISTERED.

CREATE TABLE pk_devices (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES pk_users(id) ON DELETE CASCADE,
  fcm_token   text NOT NULL UNIQUE CHECK (length(fcm_token) BETWEEN 10 AND 4096),
  platform    text CHECK (platform IN ('android','ios','web','other')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON pk_devices (user_id);
COMMENT ON TABLE pk_devices IS 'Token FCM app Polmas Keamanan per pengguna (project Firebase PK_FCM_SERVICE_ACCOUNT). Satu token = satu perangkat; token yang sama pindah pemilik saat login nomor lain.';
COMMENT ON COLUMN pk_devices.fcm_token IS 'Token Firebase Cloud Messaging; dihapus otomatis bila FCM menjawab UNREGISTERED.';

ALTER TABLE pk_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE pk_devices FORCE ROW LEVEL SECURITY;
CREATE POLICY platform_only ON pk_devices USING (app_is_platform()) WITH CHECK (app_is_platform());
COMMENT ON POLICY platform_only ON pk_devices IS 'Tabel platform Polmas Keamanan: hanya terlihat dalam withPlatform() (app.platform=on).';

-- SOS yang sudah dikirimi push ke pengguna tertentu (cegah dobel: kontak darurat + Bhabinkamtibmas kecamatan).
CREATE TABLE pk_push_log (
  report_id  uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES pk_users(id) ON DELETE CASCADE,
  reason     text NOT NULL CHECK (reason IN ('contact','kecamatan')),
  result     text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (report_id, user_id)
);
COMMENT ON TABLE pk_push_log IS 'Push SOS Polmas Keamanan per penerima: alasan (contact = nomornya di Nomor Darurat SOS, kecamatan = Bhabinkamtibmas wilayah) dan hasil terakhir (sent/stub/failed/no_device).';

ALTER TABLE pk_push_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE pk_push_log FORCE ROW LEVEL SECURITY;
CREATE POLICY platform_only ON pk_push_log USING (app_is_platform()) WITH CHECK (app_is_platform());
COMMENT ON POLICY platform_only ON pk_push_log IS 'Tabel platform Polmas Keamanan: hanya terlihat dalam withPlatform() (app.platform=on).';
