import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { DOC_TYPES, type DocType } from '@siagasos/shared';
import { q, withTenant } from '../../db.js';
import { config } from '../../config.js';
import { ApiError, parse } from '../../lib/errors.js';
import { putPrivate, sniffMime } from '../../lib/storage.js';
import { sha256 } from '../../lib/crypto.js';
import { sendStatusEmail } from '../../lib/mailer.js';
import { addBusinessDays } from '../../lib/businessTime.js';
import { requireRole, requireUser } from '../../middleware/portalAuth.js';

export const onboardingRouter = Router();
onboardingRouter.use(requireUser);

export function requiredDocs(entityType: string, picIsDirector: boolean): DocType[] {
  const docs: DocType[] = ['nib', 'npwp', 'ktp_pic'];
  if (entityType === 'pt' || entityType === 'yayasan') docs.push('akta', 'sk_kemenkumham');
  if (!picIsDirector) docs.push('surat_kuasa');
  return docs;
}

async function loadState(accountId: string) {
  const acc = (await q(`SELECT * FROM accounts WHERE id = $1`, [accountId])).rows[0];
  const docs = await withTenant(accountId, (c) =>
    c.query(
      `SELECT id, doc_type, original_name, mime_type, size_bytes, review_state, review_note, uploaded_at
       FROM account_documents WHERE account_id = $1 AND superseded_at IS NULL ORDER BY uploaded_at`,
      [accountId],
    ),
  );
  const required = requiredDocs(acc.entity_type, acc.pic_is_director);
  const have = new Set(docs.rows.filter((d) => d.review_state !== 'rejected').map((d) => d.doc_type));
  return {
    acc,
    documents: docs.rows,
    required,
    missing: required.filter((d) => !have.has(d)),
    needs_reupload: docs.rows.filter((d) => d.review_state === 'rejected').map((d) => d.doc_type),
    /** true = sedang di antrean admin; dokumen dikunci sampai ada keputusan. */
    in_review: acc.status === 'pending_review' && acc.submitted_at != null,
  };
}

onboardingRouter.get('/status', async (req, res) => {
  const s = await loadState(req.user!.accountId);
  res.json({
    status: s.acc.status,
    note: s.acc.status_note,
    submitted_at: s.acc.submitted_at,
    estimated_decision_by: s.in_review ? addBusinessDays(new Date(s.acc.submitted_at), 2).toISOString() : null,
    in_review: s.in_review,
    required_documents: s.required,
    missing_documents: s.missing,
    needs_reupload: s.needs_reupload,
    documents: s.documents,
    test_mode_available: s.acc.status !== 'approved',
  });
});

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: config.maxUploadBytes, files: 1 } });

onboardingRouter.post('/documents', requireRole('owner'), upload.single('file'), async (req, res) => {
  const { doc_type } = parse(z.object({ doc_type: z.enum(DOC_TYPES) }), req.body);
  if (!req.file) throw new ApiError(400, 'file_required', 'Field "file" wajib berisi dokumen');
  const s = await loadState(req.user!.accountId);
  if (!['pending_review', 'needs_revision'].includes(s.acc.status)) throw new ApiError(409, 'not_editable', 'Dokumen tidak bisa diubah pada status ini');
  if (s.in_review) throw new ApiError(409, 'under_review', 'Dokumen sedang direview admin dan tidak bisa diubah');

  const mime = sniffMime(req.file.buffer);
  if (!mime) throw new ApiError(415, 'unsupported_file', 'Hanya PDF, JPG, atau PNG (dicek dari isi file, bukan ekstensi)');
  // TODO(M5): pindai antivirus (ClamAV) sebelum disimpan.
  const storageKey = await putPrivate(`accounts/${s.acc.id}`, req.file.buffer);

  const doc = await withTenant(s.acc.id, async (c) => {
    await c.query(`UPDATE account_documents SET superseded_at = now() WHERE account_id = $1 AND doc_type = $2 AND superseded_at IS NULL`, [s.acc.id, doc_type]);
    const { rows } = await c.query(
      `INSERT INTO account_documents (account_id, doc_type, storage_key, original_name, mime_type, size_bytes, sha256)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id, doc_type, original_name, mime_type, size_bytes, review_state, uploaded_at`,
      [s.acc.id, doc_type, storageKey, req.file!.originalname.slice(0, 200), mime, req.file!.size, sha256(req.file!.buffer)],
    );
    return rows[0];
  });
  res.status(201).json(doc);
});

onboardingRouter.post('/submit', requireRole('owner'), async (req, res) => {
  const s = await loadState(req.user!.accountId);
  if (s.in_review) throw new ApiError(409, 'already_submitted', 'Pendaftaran sudah diajukan');
  if (!['pending_review', 'needs_revision'].includes(s.acc.status)) throw new ApiError(409, 'not_submittable', `Tidak bisa diajukan dari status ${s.acc.status}`);
  if (s.missing.length) throw new ApiError(422, 'documents_missing', 'Dokumen wajib belum lengkap', { missing: s.missing });
  await q(`UPDATE accounts SET status = 'pending_review', submitted_at = now(), updated_at = now() WHERE id = $1`, [s.acc.id]);
  if (s.acc.status === 'needs_revision') sendStatusEmail(req.user!.email, 'pending_review');
  res.json({ status: 'pending_review', submitted: true });
});
