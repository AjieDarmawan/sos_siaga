-- Wilayah tugas Nomor Darurat (mis. Bhabinkamtibmas: provinsi → desa). Nullable: kontak lama tidak terpengaruh.
ALTER TABLE emergency_contacts ADD COLUMN area jsonb;
COMMENT ON COLUMN emergency_contacts.area IS
  'Wilayah tugas kontak dari SDK: {province, regency, district, village}, masing-masing {code, name} (kode tabel wilayah) atau null. Diisi untuk jabatan berwilayah seperti Bhabinkamtibmas.';
