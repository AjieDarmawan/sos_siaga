import { useEffect, useState } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { Buildings, ChartBar, List, ShieldCheck, SignOut, Tray } from '@phosphor-icons/react';
import { Badge } from '@portal/components/ui';
import { ThemeMenu } from '@portal/components/ThemeMenu';
import { api } from './lib/api';
import { useAdmin } from './lib/auth';

export function AdminMark({ size = 28 }: { size?: number }) {
  return <span className="brand-mark admin-mark" style={{ width: size, height: size }} aria-hidden><ShieldCheck size={size * 0.6} weight="fill" /></span>;
}

export function AdminLayout() {
  const { s, signOut } = useAdmin();
  const [open, setOpen] = useState(false);
  const [queue, setQueue] = useState<number | null>(null);
  const loc = useLocation();
  useEffect(() => setOpen(false), [loc.pathname]);
  // jumlah antrean untuk badge menu; diperbarui tiap pindah halaman
  useEffect(() => {
    api<{ counts: Record<string, number> }>('/admin/accounts?status=pending_review').then((r) => setQueue(r.counts.pending_review ?? 0)).catch(() => {});
  }, [loc.pathname]);
  if (!s) return null;

  const nav = [
    { to: '/', label: 'Ringkasan', icon: ChartBar, end: true },
    { to: '/queue', label: 'Antrean review', icon: Tray, badge: queue },
    { to: '/accounts', label: 'Semua perusahaan', icon: Buildings },
  ];
  return (
    <div className="shell">
      <a href="#main" className="skip-link">Lewati ke konten</a>
      <aside className={`sidebar ${open ? 'open' : ''}`} aria-label="Navigasi admin">
        <NavLink to="/" className="brand"><AdminMark />SiagaSOS <span className="admin-tag">Admin</span></NavLink>
        <nav className="stack-sm" style={{ gap: 2 }}>
          {nav.map(({ to, label, icon: Icon, badge, end }) => (
            <NavLink key={to} to={to} end={end} className="nav-link">
              <Icon size={20} />{label}
              {!!badge && <span className="nav-badge" aria-label={`${badge} menunggu`}>{badge}</span>}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-foot">
          <div className="user-chip">
            <strong style={{ overflowWrap: 'anywhere' }}>{s.admin.email}</strong>
            <span style={{ marginTop: 6 }}><Badge tone={s.admin.role === 'superadmin' ? 'sos' : 'info'}>{s.admin.role === 'superadmin' ? 'Superadmin' : 'Reviewer'}</Badge></span>
          </div>
          <ThemeMenu withLabel placement="up" />
          <button className="nav-link" style={{ border: 0, background: 'none', cursor: 'pointer', width: '100%' }} onClick={signOut}><SignOut size={20} />Keluar</button>
        </div>
      </aside>
      {open && <div className="scrim" onClick={() => setOpen(false)} aria-hidden />}
      <div className="main">
        <div className="mobile-bar">
          <button className="btn btn-ghost btn-icon" onClick={() => setOpen(true)} aria-label="Buka menu"><List size={22} /></button>
          <span className="brand" style={{ padding: 0 }}><AdminMark size={24} />Admin</span>
          <ThemeMenu />
        </div>
        <main id="main" tabIndex={-1} style={{ outline: 'none' }}><Outlet /></main>
      </div>
    </div>
  );
}
