import { useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { CheckCircle, Clock, FileArrowUp, FilePdf, FileImage, Flask, PaperPlaneTilt, WarningCircle } from '@phosphor-icons/react';
import { api, ApiError } from '../lib/api';
import { useAuth } from '../lib/auth';
import { ACCOUNT_STATUS, DOC_LABEL, fmtBytes, fmtDate } from '../lib/format';
import type { DocType, OnboardingStatus } from '../lib/types';
import { Alert, Badge, Button, Spinner, useLoad, useToast } from '../components/ui';

const MAX = 5 * 1024 * 1024;
const ACCEPT = 'application/pdf,image/jpeg,image/png';

export function OnboardingPage() {
  const { me, refresh, can } = useAuth();
  const toast = useToast();
  const justVerified = useSearchParams()[0].get('verified') === '1';
  const { data: s, loading, error, reload } = useLoad(() => api<OnboardingStatus>('/portal/onboarding/status'));
  const [submitting, setSubmitting] = useState(false);

  if (loading && !s) return <div className="page"><Spinner /></div>;
  if (error || !s) return <div className="page"><Alert tone="error">{error}</Alert></div>;

  const st = ACCOUNT_STATUS[s.status];
  const editable = !s.in_review && ['pending_review', 'needs_revision'].includes(s.status);
  const isOwner = can('owner');
  const docByType = new Map(s.documents.map((d) => [d.doc_type, d]));
  const list: DocType[] = [...s.required_documents, ...(docByType.has('lainnya') && !s.required_documents.includes('lainnya') ? (['lainnya'] as DocType[]) : [])];
  const done = s.required_documents.length - s.missing_documents.length;

  async function submit() {
    setSubmitting(true);
    try {
      await api('/portal/onboarding/submit', { method: 'POST' });
      toast('Pendaftaran diajukan untuk review');
      await Promise.all([reload(), refresh()]);
    } catch (e) {
      toast((e as Error).message, 'error');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h1>Status verifikasi</h1>
          <p>{me?.account.legal_name}</p>
        </div>
        <Badge tone={st.tone} dot>{st.label}</Badge>
      </div>

      {justVerified && s.status === 'pending_review' && !s.in_review && (
        <Alert tone="ok" title="Email terverifikasi">Kunci test sudah bisa dipakai. Lengkapi dokumen di bawah untuk mengaktifkan kunci live.</Alert>
      )}

      <StatusPanel s={s} />

      <div className="card">
        <div className="card-head">
          <div>
            <h2>Dokumen perusahaan</h2>
            <p>PDF, JPG, atau PNG, maks. 5 MB per file. Disimpan terenkripsi dan hanya dibuka oleh tim review.</p>
          </div>
          <span className="small muted" aria-label={`${done} dari ${s.required_documents.length} dokumen wajib`}>{done}/{s.required_documents.length} wajib</span>
        </div>
        <ul className="table-wrap" style={{ listStyle: 'none', margin: 0, padding: 0 }}>
          {list.map((t) => (
            <DocRow key={t} type={t} doc={docByType.get(t)} required={s.required_documents.includes(t)}
              rejected={s.needs_reupload.includes(t)} editable={editable && isOwner} onUploaded={reload} />
          ))}
        </ul>
        {editable && isOwner && (
          <div className="card-body row-between" style={{ borderTop: '1px solid var(--border)' }}>
            <span className="small muted">
              {s.missing_documents.length ? `Belum lengkap: ${s.missing_documents.map((m) => DOC_LABEL[m].label).join(', ')}` : 'Semua dokumen wajib sudah diunggah.'}
            </span>
            <Button variant="primary" disabled={s.missing_documents.length > 0} loading={submitting} onClick={submit}>
              <PaperPlaneTilt size={16} />{s.status === 'needs_revision' ? 'Ajukan ulang' : 'Ajukan untuk review'}
            </Button>
          </div>
        )}
        {!isOwner && editable && <div className="card-body"><p className="small muted">Hanya pemilik akun (owner) yang bisa mengunggah dokumen.</p></div>}
      </div>

      {s.test_mode_available && (
        <div className="card card-pad row-between">
          <div className="row" style={{ gap: 12, flexWrap: 'nowrap' }}>
            <Flask size={28} />
            <div>
              <h3>Coba integrasi sekarang dengan kunci test</h3>
              <p className="small muted">Maks. 50 laporan test per hari. Ganti ke <code>pk_live_</code> setelah disetujui, tanpa ubah kode lain.</p>
            </div>
          </div>
          <Link to="/apps" className="btn">Buka App & kunci</Link>
        </div>
      )}
    </div>
  );
}

function StatusPanel({ s }: { s: OnboardingStatus }) {
  if (s.status === 'approved') return <Alert tone="ok" title="Perusahaan disetujui">Kunci live sudah bisa dibuat di halaman App & kunci API.</Alert>;
  if (s.status === 'needs_revision') {
    return (
      <Alert tone="error" title="Perlu perbaikan dari tim review">
        {s.note && <p style={{ marginBottom: 4 }}>{s.note}</p>}
        Unggah ulang dokumen yang ditandai, lalu ajukan kembali.
      </Alert>
    );
  }
  if (s.in_review) {
    return (
      <div className="card card-pad row" style={{ gap: 16, flexWrap: 'nowrap', alignItems: 'flex-start' }}>
        <Clock size={28} style={{ flex: 'none', color: 'var(--warn)' }} />
        <div className="stack-sm">
          <h2>Sedang direview</h2>
          <p className="muted">Diajukan {fmtDate(s.submitted_at)}. Perkiraan keputusan paling lambat <strong style={{ color: 'var(--text)' }}>{fmtDate(s.estimated_decision_by)}</strong> (2 hari kerja). Anda akan menerima email setiap ada perubahan status.</p>
          <p className="small muted">Dokumen dikunci selama review.</p>
        </div>
      </div>
    );
  }
  return null;
}

function DocRow({ type, doc, required, rejected, editable, onUploaded }: {
  type: DocType; doc?: OnboardingStatus['documents'][number]; required: boolean; rejected: boolean; editable: boolean; onUploaded: () => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const toast = useToast();
  const meta = DOC_LABEL[type];

  async function upload(file: File) {
    setErr(null);
    if (file.size > MAX) return setErr(`File ${fmtBytes(file.size)}; maksimal 5 MB`);
    if (!ACCEPT.split(',').includes(file.type)) return setErr('Hanya PDF, JPG, atau PNG');
    const form = new FormData();
    form.append('doc_type', type);
    form.append('file', file);
    setBusy(true);
    try {
      await api('/portal/onboarding/documents', { form });
      toast(`${meta.label} terunggah`);
      onUploaded();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : String(e));
    } finally {
      setBusy(false);
      if (input.current) input.current.value = '';
    }
  }

  const Icon = doc?.mime_type === 'application/pdf' ? FilePdf : FileImage;
  const state = rejected ? { tone: 'sos' as const, label: 'Ditolak, unggah ulang' }
    : doc?.review_state === 'ok' ? { tone: 'ok' as const, label: 'Diterima' }
    : doc ? { tone: 'muted' as const, label: 'Terunggah' }
    : required ? { tone: 'warn' as const, label: 'Belum ada' } : null;

  return (
    <li className="row-between" style={{ padding: '14px 20px', borderBottom: '1px solid var(--border)', flexWrap: 'nowrap' }}>
      <div className="row" style={{ gap: 12, flexWrap: 'nowrap', minWidth: 0 }}>
        {doc ? <Icon size={26} style={{ flex: 'none', color: 'var(--text-2)' }} />
          : <WarningCircle size={26} style={{ flex: 'none', color: 'var(--text-3)' }} />}
        <div style={{ minWidth: 0 }}>
          <div className="row" style={{ gap: 8 }}>
            <strong>{meta.label}</strong>
            {!required && <span className="small muted">opsional</span>}
            {state && <Badge tone={state.tone}>{state.tone === 'ok' && <CheckCircle size={12} weight="bold" />}{state.label}</Badge>}
          </div>
          <p className="small muted" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {doc ? `${doc.original_name} · ${fmtBytes(doc.size_bytes)} · ${fmtDate(doc.uploaded_at)}` : meta.hint}
          </p>
          {doc?.review_note && <p className="small" style={{ color: 'var(--sos)' }}>Catatan reviewer: {doc.review_note}</p>}
          {err && <p className="small" role="alert" style={{ color: 'var(--sos)' }}>{err}</p>}
        </div>
      </div>
      {editable && (
        <>
          <input ref={input} type="file" accept={ACCEPT} hidden aria-label={`Pilih file ${meta.label}`}
            onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])} />
          <Button size="sm" variant={doc && !rejected ? 'ghost' : 'default'} loading={busy} onClick={() => input.current?.click()}>
            <FileArrowUp size={16} />{doc ? 'Ganti' : 'Unggah'}
          </Button>
        </>
      )}
    </li>
  );
}
