import { useEffect, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { Buildings, CaretRight, MagnifyingGlass, Tray, Warning } from '@phosphor-icons/react';
import { ACCOUNT_STATUS, ENTITY_LABEL, fmtDate } from '@portal/lib/format';
import type { AccountStatus } from '@portal/lib/types';
import { Alert, Badge, Empty, Spinner, useLoad } from '@portal/components/ui';
import { api } from '../lib/api';

export interface AccountRow {
  id: string; legal_name: string; entity_type: keyof typeof ENTITY_LABEL; nib: string; industry: string; est_users: number;
  status: AccountStatus; risk_flags: string[]; submitted_at: string | null; created_at: string; approved_at: string | null;
  pic_name: string | null; pic_email: string | null; waiting_business_hours: number | null; sla_warning: boolean;
}

/** `drafting` = status pending_review tapi belum menekan "Ajukan" (masih melengkapi dokumen). Bukan status DB. */
type Tab = 'all' | 'pending_review' | 'drafting' | 'needs_revision' | 'approved' | 'pending_email' | 'rejected' | 'suspended';
const TABS: [Tab, string][] = [
  ['all', 'Semua'], ['pending_review', 'Antrean review'], ['drafting', 'Melengkapi dokumen'], ['needs_revision', 'Perlu revisi'],
  ['approved', 'Disetujui'], ['pending_email', 'Belum verifikasi email'], ['rejected', 'Ditolak'], ['suspended', 'Dibekukan'],
];

export const RISK_LABEL: Record<string, string> = { free_email_domain: 'Email gratis' };

export function AccountsPage({ mode }: { mode: 'queue' | 'all' }) {
  const [sp, setSp] = useSearchParams();
  const tab: Tab = mode === 'queue' ? 'pending_review' : ((sp.get('status') as Tab) ?? 'all');
  const [q, setQ] = useState(sp.get('q') ?? '');
  const [search, setSearch] = useState(q);
  const nav = useNavigate();
  useEffect(() => { const t = setTimeout(() => setSearch(q.trim()), 300); return () => clearTimeout(t); }, [q]);

  const apiStatus = tab === 'drafting' ? 'all' : tab;
  const { data, loading, error } = useLoad(
    () => api<{ data: AccountRow[]; counts: Record<string, number> }>(`/admin/accounts?status=${apiStatus}${search ? `&search=${encodeURIComponent(search)}` : ''}`),
    [apiStatus, search],
  );
  const rows = (data?.data ?? []).filter((r) => tab !== 'drafting' || (r.status === 'pending_review' && !r.submitted_at));
  const counts = data?.counts ?? {};
  const total = Object.values(counts).reduce((a, b) => a + b, 0);

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h1>{mode === 'queue' ? 'Antrean review' : 'Semua perusahaan'}</h1>
          <p>{mode === 'queue' ? 'Terlama di atas. Target keputusan maksimal 2 hari kerja (peringatan setelah 36 jam kerja).' : 'Setiap perusahaan yang pernah mendaftar, terbaru di atas.'}</p>
        </div>
        <label className="row" style={{ gap: 0, position: 'relative', minWidth: 260 }}>
          <span className="sr-only">Cari perusahaan</span>
          <MagnifyingGlass size={16} style={{ position: 'absolute', left: 12, color: 'var(--text-3)' }} aria-hidden />
          <input className="input" style={{ paddingLeft: 36 }} placeholder="Nama, NIB, atau email PIC" value={q}
            onChange={(e) => { setQ(e.target.value); const n = new URLSearchParams(sp); e.target.value ? n.set('q', e.target.value) : n.delete('q'); setSp(n, { replace: true }); }} />
        </label>
      </div>

      {mode === 'all' && (
        <div className="tabs" role="tablist" aria-label="Filter status">
          {TABS.map(([k, l]) => {
            const n = k === 'all' ? total : counts[k] ?? 0;
            return (
              <button key={k} role="tab" aria-selected={tab === k} className="tab" onClick={() => { const p = new URLSearchParams(sp); k === 'all' ? p.delete('status') : p.set('status', k); setSp(p); }}>
                {l}<span className="muted" style={{ marginLeft: 6, fontWeight: 500 }}>{n}</span>
              </button>
            );
          })}
        </div>
      )}

      <div className="card table-wrap">
        {loading && !data ? <Spinner /> : error ? <div className="card-body"><Alert tone="error">{error}</Alert></div> : !rows.length ? (
          <Empty icon={mode === 'queue' ? <Tray size={36} /> : <Buildings size={36} />} title={mode === 'queue' ? 'Antrean kosong' : 'Tidak ada perusahaan'}>
            {search ? `Tidak ada hasil untuk "${search}".` : mode === 'queue' ? 'Semua pendaftaran sudah diputuskan.' : undefined}
          </Empty>
        ) : (
          <table className="table">
            <thead>
              <tr>
                <th>Perusahaan</th><th>PIC</th><th>Status</th>
                <th>{mode === 'queue' ? 'Menunggu' : 'Terdaftar'}</th><th><span className="sr-only">Buka</span></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const st = ACCOUNT_STATUS[r.status];
                const drafting = r.status === 'pending_review' && !r.submitted_at;
                return (
                  <tr key={r.id} style={{ cursor: 'pointer' }} onClick={() => nav(`/accounts/${r.id}`)}>
                    <td>
                      <Link to={`/accounts/${r.id}`} onClick={(e) => e.stopPropagation()} style={{ fontWeight: 600, color: 'var(--text)' }}>{r.legal_name}</Link>
                      <div className="small muted">{ENTITY_LABEL[r.entity_type] ?? r.entity_type} · NIB <span className="mono">{r.nib}</span> · {r.industry}</div>
                      {r.risk_flags.length > 0 && <div className="row" style={{ marginTop: 4 }}>{r.risk_flags.map((f) => <Badge key={f} tone="warn"><Warning size={12} />{RISK_LABEL[f] ?? f}</Badge>)}</div>}
                    </td>
                    <td><div>{r.pic_name ?? '—'}</div><div className="small muted">{r.pic_email}</div></td>
                    <td>{drafting ? <Badge tone="muted">Melengkapi dokumen</Badge> : <Badge tone={st.tone}>{st.label}</Badge>}</td>
                    <td className="small">
                      {mode === 'queue' || (r.status === 'pending_review' && r.submitted_at) ? (
                        <>
                          {r.sla_warning ? <Badge tone="sos"><Warning size={12} weight="bold" />{r.waiting_business_hours} jam kerja</Badge>
                            : <span>{r.waiting_business_hours ?? 0} jam kerja</span>}
                          <div className="muted">Diajukan {fmtDate(r.submitted_at)}</div>
                        </>
                      ) : <span className="muted">{fmtDate(r.created_at)}</span>}
                    </td>
                    <td style={{ width: 40 }}><CaretRight size={16} aria-hidden /></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
