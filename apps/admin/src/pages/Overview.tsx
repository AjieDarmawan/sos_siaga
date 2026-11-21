import { Link } from 'react-router-dom';
import { ArrowRight, Clock, Warning } from '@phosphor-icons/react';
import { ACCOUNT_STATUS, fmtDate, REPORT_STATUS } from '@portal/lib/format';
import type { AccountStatus, ReportStatus } from '@portal/lib/types';
import { Alert, Badge, Empty, Spinner, useLoad } from '@portal/components/ui';
import { api } from '../lib/api';
import type { AccountRow } from './Accounts';

interface Stats { accounts: { status: AccountStatus; n: number }[]; reports_30d: { mode: 'live' | 'test'; status: ReportStatus; n: number }[] }

const REPORT_COLOR: Record<ReportStatus, string> = {
  open: 'var(--sos)', acknowledged: '#d97706', in_progress: '#2563eb', resolved: '#16a34a', cancelled: '#94a3b8', false_alarm: '#64748b',
};

export function OverviewPage() {
  const stats = useLoad(() => api<Stats>('/admin/stats'));
  const queue = useLoad(() => api<{ data: AccountRow[]; counts: Record<string, number> }>('/admin/accounts?status=pending_review'));
  if ((stats.loading && !stats.data) || (queue.loading && !queue.data)) return <div className="page"><Spinner /></div>;
  if (stats.error || queue.error) return <div className="page"><Alert tone="error">{stats.error ?? queue.error}</Alert></div>;

  const c = queue.data!.counts;
  const total = Object.values(c).reduce((a, b) => a + b, 0);
  const late = queue.data!.data.filter((r) => r.sla_warning);
  const reports = stats.data!.reports_30d;
  const live = reports.filter((r) => r.mode === 'live');
  const liveTotal = live.reduce((a, r) => a + r.n, 0);
  const testTotal = reports.filter((r) => r.mode === 'test').reduce((a, r) => a + r.n, 0);
  const byStatus = (Object.keys(REPORT_COLOR) as ReportStatus[]).map((s) => ({ s, n: live.filter((r) => r.status === s).reduce((a, r) => a + r.n, 0) })).filter((x) => x.n);

  const cards: { k: string; label: string; to: string; tone?: string }[] = [
    { k: 'pending_review', label: 'Menunggu review', to: '/queue', tone: 'var(--warn)' },
    { k: 'drafting', label: 'Masih melengkapi dokumen', to: '/accounts?status=drafting' },
    { k: 'needs_revision', label: 'Perlu revisi', to: '/accounts?status=needs_revision' },
    { k: 'approved', label: 'Disetujui', to: '/accounts?status=approved', tone: 'var(--ok)' },
    { k: 'suspended', label: 'Dibekukan', to: '/accounts?status=suspended', tone: 'var(--sos)' },
  ];

  return (
    <div className="page">
      <div className="page-head">
        <div><h1>Ringkasan</h1><p>{total} perusahaan terdaftar</p></div>
      </div>

      {late.length > 0 && (
        <Alert tone="error" title={`${late.length} pendaftaran melewati batas 36 jam kerja`}>
          Target keputusan 2 hari kerja. <Link to="/queue">Buka antrean</Link>
        </Alert>
      )}

      <div className="stat-grid">
        {cards.map(({ k, label, to, tone }) => (
          <div key={k} className="card stat">
            <span className="n" style={{ color: tone }}>{c[k] ?? 0}</span>
            <span className="l">{label}</span>
            <Link to={to} className="row" style={{ gap: 4 }}>Lihat<ArrowRight size={12} /></Link>
          </div>
        ))}
      </div>

      <div className="grid-2" style={{ alignItems: 'start' }}>
        <div className="card">
          <div className="card-head"><div><h2>Antrean terlama</h2><p>Diurutkan dari yang paling lama menunggu</p></div><Link to="/queue" className="small">Semua</Link></div>
          {!queue.data!.data.length ? <Empty icon={<Clock size={32} />} title="Antrean kosong">Tidak ada pendaftaran yang menunggu review.</Empty> : (
            <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
              {queue.data!.data.slice(0, 6).map((r) => (
                <li key={r.id} style={{ borderBottom: '1px solid var(--border)' }}>
                  <Link to={`/accounts/${r.id}`} className="row-between" style={{ padding: '12px 20px', color: 'var(--text)', flexWrap: 'nowrap' }}>
                    <span style={{ minWidth: 0 }}>
                      <strong style={{ display: 'block' }}>{r.legal_name}</strong>
                      <span className="small muted">Diajukan {fmtDate(r.submitted_at)}</span>
                    </span>
                    {r.sla_warning ? <Badge tone="sos"><Warning size={12} weight="bold" />{r.waiting_business_hours} jam kerja</Badge>
                      : <Badge tone="warn">{r.waiting_business_hours ?? 0} jam kerja</Badge>}
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="card">
          <div className="card-head"><div><h2>Laporan SOS 30 hari</h2><p>Semua perusahaan</p></div></div>
          <div className="card-body">
            <div className="row" style={{ gap: 32 }}>
              <div className="stat" style={{ padding: 0 }}><span className="n">{liveTotal}</span><span className="l">laporan live</span></div>
              <div className="stat" style={{ padding: 0 }}><span className="n muted">{testTotal}</span><span className="l">laporan test</span></div>
            </div>
            {liveTotal > 0 && (
              <>
                <div className="bar" role="img" aria-label={byStatus.map((x) => `${REPORT_STATUS[x.s].label} ${x.n}`).join(', ')}>
                  {byStatus.map((x) => <span key={x.s} style={{ width: `${(x.n / liveTotal) * 100}%`, background: REPORT_COLOR[x.s] }} />)}
                </div>
                <div className="legend">
                  {byStatus.map((x) => <span key={x.s}><i style={{ background: REPORT_COLOR[x.s] }} />{REPORT_STATUS[x.s].label} {x.n}</span>)}
                </div>
              </>
            )}
            <p className="small muted">Status akun: {stats.data!.accounts.map((a) => `${ACCOUNT_STATUS[a.status]?.label ?? a.status} ${a.n}`).join(' · ')}</p>
          </div>
        </div>
      </div>
    </div>
  );
}
