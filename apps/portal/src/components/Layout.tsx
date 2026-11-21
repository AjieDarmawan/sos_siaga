import { Suspense, useEffect, useState } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { Broadcast, ClipboardText, List, SignOut, SquaresFour, UsersThree } from '@phosphor-icons/react';
import { useAuth } from '../lib/auth';
import { ACCOUNT_STATUS } from '../lib/format';
import { Badge, Spinner } from './ui';

export function BrandMark({ size = 28 }: { size?: number }) {
  return (
    <span className="brand-mark" style={{ width: size, height: size }} aria-hidden>
      <svg width={size * 0.55} height={size * 0.55} viewBox="0 0 16 16" fill="none">
        <path d="M8 2v7.5M8 12.5V14" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
      </svg>
    </span>
  );
}

export function Layout() {
  const { me, signOut, can } = useAuth();
  const [open, setOpen] = useState(false);
  const loc = useLocation();
  useEffect(() => setOpen(false), [loc.pathname]);
  if (!me) return null;
  const st = ACCOUNT_STATUS[me.account.status];

  const nav = [
    { to: '/dashboard', label: 'Dashboard laporan', icon: Broadcast, show: true },
    { to: '/apps', label: 'App & kunci API', icon: SquaresFour, show: can('owner', 'admin') },
    { to: '/team', label: 'Tim', icon: UsersThree, show: can('owner', 'admin') },
    { to: '/onboarding', label: 'Status verifikasi', icon: ClipboardText, show: can('owner', 'admin') },
  ].filter((n) => n.show);

  return (
    <div className="shell">
      <a href="#main" className="skip-link">Lewati ke konten</a>
      <aside className={`sidebar ${open ? 'open' : ''}`} aria-label="Navigasi utama">
        <NavLink to="/dashboard" className="brand"><BrandMark />SiagaSOS</NavLink>
        <nav className="stack-sm" style={{ gap: 2 }}>
          {nav.map(({ to, label, icon: Icon }) => (
            <NavLink key={to} to={to} className="nav-link">
              <Icon size={20} />{label}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-foot">
          <div className="user-chip">
            <strong>{me.user.full_name}</strong>
            <span className="muted">{me.account.legal_name}</span>
            <span style={{ marginTop: 6 }}><Badge tone={st.tone}>{st.label}</Badge></span>
          </div>
          <button className="nav-link btn-ghost" style={{ border: 0, background: 'none', cursor: 'pointer', width: '100%' }} onClick={signOut}>
            <SignOut size={20} />Keluar
          </button>
        </div>
      </aside>
      {open && <div className="scrim" onClick={() => setOpen(false)} aria-hidden />}
      <div className="main">
        <div className="mobile-bar">
          <button className="btn btn-ghost btn-icon" onClick={() => setOpen(true)} aria-label="Buka menu"><List size={22} /></button>
          <span className="brand" style={{ padding: 0 }}><BrandMark size={24} />SiagaSOS</span>
          <span style={{ width: 40 }} />
        </div>
        <main id="main" tabIndex={-1} style={{ outline: 'none', minHeight: 0, flex: 1 }}>
          <Suspense fallback={<Spinner />}><Outlet /></Suspense>
        </main>
      </div>
    </div>
  );
}

export function TestModeNotice() {
  const { me } = useAuth();
  if (!me?.account.limited) return null;
  return (
    <div className="alert alert-warn" role="status">
      <strong>Mode test.</strong>
      <span>Perusahaan belum disetujui. Hanya kunci <code>pk_test_</code> yang aktif (maks. 50 laporan/hari) dan dashboard hanya menampilkan laporan test.</span>
    </div>
  );
}
