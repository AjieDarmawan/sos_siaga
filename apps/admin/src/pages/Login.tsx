import { useState, type FormEvent } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { LockKey } from '@phosphor-icons/react';
import { Alert, Button, TextField } from '@portal/components/ui';
import { useAdmin } from '../lib/auth';
import { AdminMark } from '../Layout';
import { ThemeMenu } from '@portal/components/ThemeMenu';

export function LoginPage() {
  const { s, signIn } = useAdmin();
  const nav = useNavigate();
  const from = (useLocation().state as { from?: string } | null)?.from ?? '/';
  const [f, setF] = useState({ email: '', password: '', totp: '' });
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  if (s) return <Navigate to={from} replace />;

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      await signIn(f.email.trim(), f.password, f.totp);
      nav(from, { replace: true });
    } catch (e) {
      setErr((e as Error).message);
      setF((x) => ({ ...x, totp: '' }));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="auth-main" style={{ minHeight: '100vh', background: 'var(--bg)', position: 'relative' }}>
      <div style={{ position: 'absolute', top: 16, right: 16 }}><ThemeMenu /></div>
      <form className="card card-pad auth-card" onSubmit={submit} style={{ gap: 20 }}>
        <div className="row" style={{ gap: 12 }}>
          <AdminMark size={36} />
          <div>
            <h1 style={{ fontSize: 20 }}>Panel admin SiagaSOS</h1>
            <p className="small muted">Khusus tim review & superadmin platform</p>
          </div>
        </div>
        {err && <Alert tone="error">{err}</Alert>}
        <TextField label="Email" type="email" autoComplete="username" required value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} />
        <TextField label="Password" type="password" autoComplete="current-password" required value={f.password} onChange={(e) => setF({ ...f, password: e.target.value })} />
        <TextField label="Kode 2FA" className="input otp" inputMode="numeric" autoComplete="one-time-code" maxLength={6} required
          hint={import.meta.env.DEV ? 'Dev: jalankan pnpm admin:otp untuk kode saat ini' : 'Dari aplikasi authenticator (Google Authenticator, 1Password, dll.)'}
          value={f.totp} onChange={(e) => setF({ ...f, totp: e.target.value.replace(/\D/g, '').slice(0, 6) })} />
        <Button variant="primary" type="submit" loading={busy} disabled={!f.email || !f.password || f.totp.length !== 6}><LockKey size={16} />Masuk</Button>
      </form>
    </div>
  );
}
