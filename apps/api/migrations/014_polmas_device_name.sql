-- Polmas Keamanan: nama perangkat untuk daftar "Perangkat terdaftar" di Profil (mis. "Samsung SM-A546E").
ALTER TABLE pk_devices ADD COLUMN device_name text CHECK (length(device_name) <= 80);
COMMENT ON COLUMN pk_devices.device_name IS 'Merek + model HP yang dikirim app saat mendaftarkan token FCM; hanya untuk ditampilkan ke pemiliknya.';
