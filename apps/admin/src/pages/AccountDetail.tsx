import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, CheckCircle, Eye, FileImage, FilePdf, Prohibit, Warning, XCircle } from '@phosphor-icons/react';
import { ACCOUNT_STATUS, DOC_LABEL, ENTITY_LABEL, fmtBytes, fmtDate } from '@portal/lib/format';
import type { AccountStatus, DocType } from '@portal/lib/types';
import { Alert, Badge, Button, Field, Modal, Spinner, useLoad, useToast } from '@portal/components/ui';
import { api } from '../lib/api';
import { RISK_LABEL } from './Accounts';

interface Doc { id: string; doc_type: DocType; original_name: string; mime_type: string; size_bytes: number; sha256: string; review_state: 'pending' | 'ok' | 'rejected'; review_note: string | null; uploaded_at: string; superseded_at: string | null }
interface Detail {
  account: Record<string, any> & { id: string; legal_name: string; status: AccountStatus; entity_type: keyof typeof ENTITY_LABEL; risk_flags: string[]; submitted_at: string | null; status_note: string | null };
  required_documents: DocType[];
  documents: Doc[];
  users: { id: string; email: string; full_name: string; phone: string | null; position: string | null; role: string; email_verified_at: string | null; created_at: string }[];
  reviews: { decision: string; reason: string | null; checklist: Record<string, boolean> | null; created_at: string; reviewer: string }[];
  apps: { id: string; name: string; disabled_at: string | null; created_at: string }[];
  verification_checklist: { key: string; label: string }[];
}

type Decision = 'approved' | 'needs_revision' | 'rejected' | 'suspended' | 'reinstated';
const DECISION: Record<Decision, { label: string; variant: 'primary' | 'danger' | 'default'; needsReason: boolean; confirm: string }> = {
  approved: { label: 'Setujui', variant: 'primary', needsReason: false, confirm: 'Kunci live langsung bisa dibuat dan PIC menerima email persetujuan.' },
  needs_revision: { label: 'Minta revisi', variant: 'default', needsReason: true, confirm: 'PIC diminta mengunggah ulang dokumen yang ditandai ditolak, lalu mengajukan kembali.' },
  rejected: { label: 'Tolak', variant: 'danger', needsReason: true, confirm: 'Semua kunci dicabut. Perusahaan baru bisa mendaftar ulang setelah 30 hari.' },
  suspended: { label: 'Bekukan akun', variant: 'danger', needsReason: true, confirm: 'Semua kunci dicabut dalam ≤ 60 detik dan pengguna tidak bisa login. Tombol SOS di aplikasi mereka berhenti bekerja.' },
  reinstated: { label: 'Pulihkan akun', variant: 'primary', needsReason: false, confirm: 'Akun kembali aktif. Kunci yang dicabut saat pembekuan perlu dibuat ulang oleh klien.' },
};
const ALLOWED: Partial<Record<AccountStatus, Decision[]>> = {
  pending_review: ['approved', 'needs_revision', 'rejected'],
  needs_revision: ['rejected'],
  approved: ['suspended'],
  suspended: ['reinstated'],
};
const DECISION_LABEL: Record<string, string> = { approved: 'Disetujui', needs_revision: 'Minta revisi', rejected: 'Ditolak', suspended: 'Dibekukan', reinstated: 'Dipulihkan' };

export function AccountDetailPage() {
  const id = useParams().id!;
  const toast = useToast();
  const { data: d, loading, error, reload } = useLoad(() => api<Detail>(`/admin/accounts/${id}`), [id]);
  const [checks, setChecks] = useState<Record<string, boolean>>({});
  const [decide, setDecide] = useState<Decision | null>(null);
  const [preview, setPreview] = useState<Doc | null>(null);
  const [rejectDoc, setRejectDoc] = useState<Doc | null>(null);
  const [disableApp, setDisableApp] = useState<Detail['apps'][number] | null>(null);

  if (loading && !d) return <div className="page"><Spinner /></div>;
  if (error || !d) return <div className="page"><Alert tone="error">{error}</Alert></div>;

  const a = d.account;
  const st = ACCOUNT_STATUS[a.status];
  const current = d.documents.filter((x) => !x.superseded_at);
  const old = d.documents.filter((x) => x.superseded_at);
  const have = new Set(current.map((x) => x.doc_type));
  const missing = d.required_documents.filter((t) => !have.has(t));
  const flagged = current.filter((x) => x.review_state === 'rejected').length;
  const drafting = a.status === 'pending_review' && !a.submitted_at;
  const actions = drafting ? [] : ALLOWED[a.status] ?? [];
  const checklist = d.verification_checklist.filter((c) => (c.key === 'akta_ahu' ? ['pt', 'yayasan'].includes(a.entity_type) : c.key === 'surat_kuasa' ? !a.pic_is_director : true));

  async function markDoc(doc: Doc, review_state: Doc['review_state'], review_note?: string) {
    try {
      await api(`/admin/documents/${doc.id}`, { method: 'PATCH', body: { review_state, ...(review_note ? { review_note } : {}) } });
      toast(review_state === 'ok' ? 'Dokumen ditandai sesuai' : review_state === 'rejected' ? 'Dokumen ditandai perlu diunggah ulang' : 'Tanda dokumen dihapus');
      void reload();
    } catch (e) { toast((e as Error).message, 'error'); }
  }

  return (
    <div className="page" style={{ maxWidth: 1320 }}>
      <div className="stack-sm">
        <Link to={a.status === 'pending_review' && a.submitted_at ? '/queue' : '/accounts'} className="small row" style={{ gap: 4 }}><ArrowLeft size={14} />Kembali</Link>
        <div className="page-head">
          <div>
            <h1>{a.legal_name}</h1>
            <p>{ENTITY_LABEL[a.entity_type] ?? a.entity_type} · {a.industry} · terdaftar {fmtDate(a.created_at)}</p>
          </div>
          <div className="row">
            {a.risk_flags.map((f: string) => <Badge key={f} tone="warn"><Warning size={12} />{RISK_LABEL[f] ?? f}</Badge>)}
            {drafting ? <Badge tone="muted" dot>Belum diajukan</Badge> : <Badge tone={st.tone} dot>{st.label}</Badge>}
          </div>
        </div>
      </div>

      {drafting && <Alert tone="info" title="Perusahaan belum mengajukan review">Dokumen masih bisa berubah. Keputusan tersedia setelah PIC menekan "Ajukan untuk review".</Alert>}
      {a.status_note && <Alert tone="warn" title="Catatan keputusan terakhir">{a.status_note}</Alert>}

      <div className="detail-grid">
        <div className="stack">
          <div className="card">
            <div className="card-head"><h2>Data perusahaan</h2></div>
            <div className="card-body">
              <dl className="kv" style={{ gridTemplateColumns: '170px 1fr' }}>
                <dt>NIB</dt><dd className="mono">{a.nib}</dd>
                <dt>NPWP</dt><dd className="mono">{a.npwp}</dd>
                <dt>Alamat</dt><dd>{a.address}</dd>
                <dt>Telepon</dt><dd>{a.phone}</dd>
                <dt>Website</dt><dd>{a.website ? <a href={a.website} target="_blank" rel="noreferrer noopener">{a.website}</a> : '—'}</dd>
                <dt>Perkiraan pengguna</dt><dd>{Number(a.est_users).toLocaleString('id-ID')}</dd>
                <dt>Rencana penggunaan</dt><dd>{a.usage_plan}</dd>
                <dt>PIC direksi?</dt><dd>{a.pic_is_director ? 'Ya' : 'Tidak (wajib surat kuasa)'}</dd>
                <dt>Diajukan</dt><dd>{fmtDate(a.submitted_at)}</dd>
              </dl>
            </div>
          </div>

          <div className="card">
            <div className="card-head">
              <div><h2>Dokumen</h2><p>Buka setiap dokumen, cocokkan dengan data di atas, lalu tandai.</p></div>
              {missing.length > 0 && <Badge tone="sos">{missing.length} wajib belum ada</Badge>}
            </div>
            {missing.length > 0 && <div className="card-body" style={{ paddingBottom: 0 }}><Alert tone="warn">Belum diunggah: {missing.map((m) => DOC_LABEL[m].label).join(', ')}</Alert></div>}
            <div>
              {current.map((doc) => <DocRow key={doc.id} doc={doc} required={d.required_documents.includes(doc.doc_type)} editable={a.status === 'pending_review' && !!a.submitted_at}
                onPreview={() => setPreview(doc)} onOk={() => markDoc(doc, 'ok')} onReject={() => setRejectDoc(doc)} onReset={() => markDoc(doc, 'pending')} />)}
              {!current.length && <p className="card-body muted">Belum ada dokumen.</p>}
            </div>
            {old.length > 0 && (
              <details className="card-body" style={{ borderTop: '1px solid var(--border)' }}>
                <summary className="small" style={{ cursor: 'pointer', fontWeight: 600 }}>{old.length} versi lama (diganti)</summary>
                <div style={{ marginTop: 8 }}>{old.map((doc) => <DocRow key={doc.id} doc={doc} required={false} editable={false} onPreview={() => setPreview(doc)} />)}</div>
              </details>
            )}
          </div>

          <div className="card table-wrap">
            <div className="card-head"><h2>Pengguna</h2></div>
            <table className="table">
              <thead><tr><th>Nama</th><th>Peran</th><th>Email terverifikasi</th></tr></thead>
              <tbody>
                {d.users.map((u) => (
                  <tr key={u.id}>
                    <td><strong>{u.full_name}</strong><div className="small muted">{u.email}{u.phone ? ` · ${u.phone}` : ''}{u.position ? ` · ${u.position}` : ''}</div></td>
                    <td>{u.role}</td>
                    <td className="small">{u.email_verified_at ? fmtDate(u.email_verified_at) : <Badge tone="warn">Belum</Badge>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="card table-wrap">
            <div className="card-head"><div><h2>App</h2><p>Nonaktifkan app yang menyalahgunakan layanan (F-19).</p></div></div>
            {!d.apps.length ? <p className="card-body muted">Belum membuat app.</p> : (
              <table className="table">
                <tbody>
                  {d.apps.map((ap) => (
                    <tr key={ap.id}>
                      <td><strong>{ap.name}</strong><div className="small muted mono">{ap.id}</div></td>
                      <td>{ap.disabled_at ? <Badge tone="sos">Dinonaktifkan</Badge> : <Badge tone="ok">Aktif</Badge>}</td>
                      <td style={{ textAlign: 'right' }}>
                        {ap.disabled_at
                          ? <Button size="sm" onClick={async () => { try { await api(`/admin/apps/${ap.id}/enable`, { method: 'POST' }); toast('App diaktifkan'); void reload(); } catch (e) { toast((e as Error).message, 'error'); } }}>Aktifkan</Button>
                          : <Button size="sm" variant="ghost" style={{ color: 'var(--sos)' }} onClick={() => setDisableApp(ap)}><Prohibit size={14} />Nonaktifkan</Button>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>

        <div className="sticky-col">
          {actions.length > 0 && (
            <div className="card">
              <div className="card-head"><div><h2>Keputusan</h2><p>Checklist ikut tersimpan di riwayat review.</p></div></div>
              <div className="card-body">
                {a.status === 'pending_review' && (
                  <fieldset className="stack-sm" style={{ border: 0, padding: 0, margin: 0 }}>
                    <legend className="label" style={{ marginBottom: 8 }}>Checklist verifikasi</legend>
                    {checklist.map((c) => (
                      <label key={c.key} className="check small">
                        <input type="checkbox" checked={!!checks[c.key]} onChange={(e) => setChecks({ ...checks, [c.key]: e.target.checked })} />
                        <span>{c.label}</span>
                      </label>
                    ))}
                  </fieldset>
                )}
                {a.status === 'pending_review' && missing.length > 0 && <Alert tone="warn">Dokumen wajib belum lengkap.</Alert>}
                <div className="stack-sm">
                  {actions.map((k) => {
                    const disabled = k === 'needs_revision' && !flagged;
                    return (
                      <Button key={k} variant={DECISION[k].variant} className="btn-block" disabled={disabled} onClick={() => setDecide(k)}
                        title={disabled ? 'Tandai minimal satu dokumen "Perlu diunggah ulang" dulu' : undefined}>
                        {DECISION[k].label}
                      </Button>
                    );
                  })}
                  {actions.includes('needs_revision') && !flagged && <p className="small muted">"Minta revisi" aktif setelah minimal satu dokumen ditandai perlu diunggah ulang.</p>}
                </div>
              </div>
            </div>
          )}

          <div className="card">
            <div className="card-head"><h2>Riwayat review</h2></div>
            <div className="card-body">
              {!d.reviews.length ? <p className="small muted">Belum ada keputusan.</p> : (
                <ol className="timeline">
                  {d.reviews.map((r, i) => (
                    <li key={i}>
                      <span>
                        <strong>{DECISION_LABEL[r.decision] ?? r.decision}</strong>
                        <span className="muted"> · {fmtDate(r.created_at)} · {r.reviewer}</span>
                        {r.reason && <span style={{ display: 'block', color: 'var(--text-2)' }}>{r.reason}</span>}
                        {r.checklist && <span className="small muted" style={{ display: 'block' }}>Checklist: {Object.values(r.checklist).filter(Boolean).length}/{Object.keys(r.checklist).length} terpenuhi</span>}
                      </span>
                    </li>
                  ))}
                </ol>
              )}
            </div>
          </div>
        </div>
      </div>

      {decide && <DecisionModal decision={decide} accountId={a.id} name={a.legal_name} checklist={a.status === 'pending_review' ? Object.fromEntries(checklist.map((c) => [c.key, !!checks[c.key]])) : undefined}
        onClose={() => setDecide(null)} onDone={() => { setDecide(null); void reload(); }} />}
      {preview && <PreviewModal doc={preview} onClose={() => setPreview(null)} />}
      {rejectDoc && <ReasonModal title={`Tolak: ${DOC_LABEL[rejectDoc.doc_type].label}`} hint="Catatan ini dilihat PIC di halaman status, mis. &quot;Foto KTP buram, unggah ulang dengan cahaya cukup&quot;."
        confirm="Tandai perlu diunggah ulang" onClose={() => setRejectDoc(null)} onSubmit={async (note) => { await markDoc(rejectDoc, 'rejected', note); setRejectDoc(null); }} />}
      {disableApp && <ReasonModal title={`Nonaktifkan ${disableApp.name}?`} hint="Semua kunci app ini berhenti bekerja dalam ≤ 60 detik. Alasan dicatat di audit log." danger
        confirm="Nonaktifkan" onClose={() => setDisableApp(null)} onSubmit={async (reason) => {
          try { await api(`/admin/apps/${disableApp.id}/disable`, { body: { reason } }); toast('App dinonaktifkan'); void reload(); } catch (e) { toast((e as Error).message, 'error'); }
          setDisableApp(null);
        }} />}
    </div>
  );
}

function DocRow({ doc, required, editable, onPreview, onOk, onReject, onReset }: {
  doc: Doc; required: boolean; editable: boolean; onPreview: () => void; onOk?: () => void; onReject?: () => void; onReset?: () => void;
}) {
  const Icon = doc.mime_type === 'application/pdf' ? FilePdf : FileImage;
  return (
    <div className={`doc-row ${doc.superseded_at ? 'old' : ''}`}>
      <div className="row" style={{ gap: 12, flexWrap: 'nowrap', minWidth: 0 }}>
        <Icon size={28} style={{ flex: 'none', color: 'var(--text-2)' }} />
        <div style={{ minWidth: 0 }}>
          <div className="row" style={{ gap: 8 }}>
            <strong>{DOC_LABEL[doc.doc_type]?.label ?? doc.doc_type}</strong>
            {!required && !doc.superseded_at && <span className="small muted">opsional</span>}
            {doc.review_state === 'ok' && <Badge tone="ok"><CheckCircle size={12} weight="bold" />Sesuai</Badge>}
            {doc.review_state === 'rejected' && <Badge tone="sos"><XCircle size={12} weight="bold" />Perlu diunggah ulang</Badge>}
          </div>
          <p className="small muted" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {doc.original_name} · {fmtBytes(doc.size_bytes)} · {fmtDate(doc.uploaded_at)}
          </p>
          {doc.review_note && <p className="small" style={{ color: 'var(--sos)' }}>{doc.review_note}</p>}
        </div>
      </div>
      <div className="doc-actions">
        <Button size="sm" onClick={onPreview}><Eye size={14} />Lihat</Button>
        {editable && doc.review_state !== 'ok' && <Button size="sm" variant="ghost" style={{ color: 'var(--ok)' }} onClick={onOk}><CheckCircle size={14} />Sesuai</Button>}
        {editable && doc.review_state !== 'rejected' && <Button size="sm" variant="ghost" style={{ color: 'var(--sos)' }} onClick={onReject}><XCircle size={14} />Tolak</Button>}
        {editable && doc.review_state !== 'pending' && <Button size="sm" variant="ghost" onClick={onReset}>Reset</Button>}
      </div>
    </div>
  );
}

/** Ambil file lewat signed URL 5 menit, tampilkan sebagai blob (tidak meninggalkan URL di riwayat browser). */
function PreviewModal({ doc, onClose }: { doc: Doc; onClose: () => void }) {
  const [src, setSrc] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    let url: string | null = null;
    (async () => {
      try {
        const { url: signed } = await api<{ url: string }>(`/admin/documents/${doc.id}/url`);
        const res = await fetch(signed);
        if (!res.ok) throw new Error(`Gagal memuat dokumen (${res.status})`);
        url = URL.createObjectURL(await res.blob());
        setSrc(url);
      } catch (e) { setErr((e as Error).message); }
    })();
    return () => { if (url) URL.revokeObjectURL(url); };
  }, [doc.id]);
  return (
    <div className="modal-scrim" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="card modal" role="dialog" aria-modal="true" aria-label={`Pratinjau ${DOC_LABEL[doc.doc_type]?.label}`} style={{ width: 'min(1000px, 100%)' }}>
        <div className="card-head">
          <div style={{ minWidth: 0 }}>
            <h2>{DOC_LABEL[doc.doc_type]?.label ?? doc.doc_type}</h2>
            <p className="mono" style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{doc.original_name} · sha256 {doc.sha256.slice(0, 16)}…</p>
          </div>
          <div className="row" style={{ flexWrap: 'nowrap' }}>
            {src && <a className="btn btn-sm" href={src} target="_blank" rel="noreferrer">Buka di tab baru</a>}
            <button className="btn btn-ghost btn-icon" onClick={onClose} aria-label="Tutup"><XCircle size={20} /></button>
          </div>
        </div>
        <div className="card-body">
          {err ? <Alert tone="error">{err}</Alert> : !src ? <Spinner label="Memuat dokumen" />
            : doc.mime_type === 'application/pdf' ? <iframe className="preview" src={src} title={doc.original_name} />
            : <div className="preview" style={{ display: 'grid', placeItems: 'center', overflow: 'auto' }}><img src={src} alt={DOC_LABEL[doc.doc_type]?.label} /></div>}
          <p className="small muted">Setiap pembukaan dokumen tercatat di audit log.</p>
        </div>
      </div>
    </div>
  );
}

function ReasonModal({ title, hint, confirm, danger, onClose, onSubmit }: { title: string; hint: string; confirm: string; danger?: boolean; onClose: () => void; onSubmit: (s: string) => Promise<void> }) {
  const [v, setV] = useState('');
  const [busy, setBusy] = useState(false);
  return (
    <Modal title={title} onClose={onClose} footer={<>
      <Button onClick={onClose}>Batal</Button>
      <Button variant={danger ? 'danger' : 'primary'} loading={busy} disabled={v.trim().length < 3} onClick={async () => { setBusy(true); await onSubmit(v.trim()); setBusy(false); }}>{confirm}</Button>
    </>}>
      <Field label="Alasan / catatan" htmlFor="reason" hint={hint}>
        <textarea id="reason" className="textarea" rows={3} maxLength={500} value={v} onChange={(e) => setV(e.target.value)} />
      </Field>
    </Modal>
  );
}

function DecisionModal({ decision, accountId, name, checklist, onClose, onDone }: { decision: Decision; accountId: string; name: string; checklist?: Record<string, boolean>; onClose: () => void; onDone: () => void }) {
  const toast = useToast();
  const meta = DECISION[decision];
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const unchecked = checklist ? Object.values(checklist).filter((x) => !x).length : 0;
  return (
    <Modal title={`${meta.label}: ${name}`} onClose={onClose} footer={<>
      <Button onClick={onClose}>Batal</Button>
      <Button variant={meta.variant === 'default' ? 'primary' : meta.variant} loading={busy} disabled={meta.needsReason && reason.trim().length < 3} onClick={async () => {
        setBusy(true);
        setErr(null);
        try {
          await api(`/admin/accounts/${accountId}/decision`, { body: { decision, ...(reason.trim() ? { reason: reason.trim() } : {}), ...(checklist ? { checklist } : {}) } });
          toast(`Keputusan tersimpan: ${meta.label}`);
          onDone();
        } catch (e) { setErr((e as Error).message); setBusy(false); }
      }}>{meta.label}</Button>
    </>}>
      {err && <Alert tone="error">{err}</Alert>}
      <p>{meta.confirm}</p>
      {decision === 'approved' && unchecked > 0 && <Alert tone="warn">{unchecked} butir checklist belum dicentang.</Alert>}
      <Field label={meta.needsReason ? 'Alasan (wajib, dikirim ke PIC lewat email)' : 'Catatan (opsional)'} htmlFor="dec-reason">
        <textarea id="dec-reason" className="textarea" rows={3} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)} />
      </Field>
    </Modal>
  );
}
