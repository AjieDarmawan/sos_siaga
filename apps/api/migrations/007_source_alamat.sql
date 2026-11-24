-- Alamat wilayah per kios/source (dipakai sebagai lokasi di WA SOS).

ALTER TABLE sources ADD COLUMN alamat text CHECK (alamat IS NULL OR char_length(alamat) <= 300);
COMMENT ON COLUMN sources.alamat IS
  'Alamat kios untuk baris lokasi di WA SOS, mis. "Kel. X, Kec. Y, Kab. Z, Prov. W". NULL = pakai nama app · source.';
