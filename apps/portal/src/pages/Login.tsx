import { useState, type FormEvent } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { api, ApiError } from '../lib/api';
import { homeFor, useAuth } from '../lib/auth';
import { AuthLayout } from '../components/AuthLayout';
import { Alert, Button, TextField } from '../components/ui';

export function LoginPage() {
  const { signIn } = useAuth();
  const nav = useNavigate();
  const from = (useLocation().state as { from?: string } | null)?.from;
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);
  const [resent, setResent] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const r = await api<{ token: string }>('/portal/auth/login', { body: { email, password }, auth: false });
      const me = await signIn(r.token);
      nav(from && from !== '/login' ? from : homeFor(me), { replace: true });
    } catch (e) {
      setErr(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  async function resend() {
    await api('/portal/auth/resend-verification', { body: { email }, auth: false }).catch(() => {});
    setResent(true);
  }

  return (
    <AuthLayout>
      <div className="stack-sm">
        <h1>Masuk ke portal</h1>
        <p className="muted">Untuk pemilik akun, admin, dan responder.</p>
      </div>
      {err && (
        <Alert tone="error" title={err.message}>
          {err.code === 'email_not_verified' && (resent
            ? 'Tautan verifikasi baru sudah dikirim bila email terdaftar.'
            : <button className="btn btn-sm" style={{ marginTop: 8 }} onClick={resend}>Kirim ulang tautan verifikasi</button>)}
          {err.details?.note && <p>Catatan: {err.details.note}</p>}
        </Alert>
      )}
      <form className="stack" onSubmit={submit} noValidate>
        <TextField label="Email kerja" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        <TextField label="Password" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} />
        <Button variant="primary" type="submit" loading={busy} className="btn-block" disabled={!email || !password}>Masuk</Button>
      </form>
      <p className="small muted">Belum punya akun perusahaan? <Link to="/register">Daftar sekarang</Link></p>
    </AuthLayout>
  );
}
