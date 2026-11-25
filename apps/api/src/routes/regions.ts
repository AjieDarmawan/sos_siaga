import { Router } from 'express';
import { z } from 'zod';
import { ApiError, parse } from '../lib/errors.js';
import { enforce } from '../lib/rateLimit.js';
import { childRegions, isParentCode, reverseRegion } from '../lib/regions.js';

/**
 * Wilayah administratif untuk SDK (dipasang di sdkRouter, sudah lewat publishableKeyAuth).
 * GET /           → provinsi
 * GET /?parent=32 → anak langsung (kab/kota → kecamatan → desa)
 * GET /reverse?lat&lng → wilayah dari koordinat (isi otomatis; tetap bisa diubah pengguna)
 */
export const regionsRouter = Router();

regionsRouter.get('/', async (req, res) => {
  const parent = typeof req.query.parent === 'string' && req.query.parent !== '' ? req.query.parent : null;
  if (parent !== null && !isParentCode(parent)) throw new ApiError(422, 'invalid_parent', 'parent harus kode wilayah, mis. 32 atau 32.73');
  const regions = await childRegions(parent);
  // Data referensi jarang berubah: boleh di-cache klien.
  res.set('Cache-Control', 'public, max-age=86400').json({ parent, regions });
});

const reverseSchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
});

regionsRouter.get('/reverse', async (req, res) => {
  const k = req.key!;
  const { lat, lng } = parse(reverseSchema, req.query);
  await enforce(`regions-reverse:${k.appId}:${req.ip}`, 20, 600);
  const match = await reverseRegion(lat, lng);
  if (!match) throw new ApiError(503, 'geocoder_unavailable', 'Wilayah belum bisa dibaca dari lokasi. Pilih manual.');
  res.set('Cache-Control', 'no-store').json(match);
});
