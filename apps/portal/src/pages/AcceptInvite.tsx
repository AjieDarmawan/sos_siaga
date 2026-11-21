import { useState, type FormEvent } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { api, ApiError } from '../lib/api';
import { homeFor, useAuth } from '../lib/auth';
import { AuthLayout } from '../components/AuthLayout';
import { Alert, Button, TextField } from '../components/ui';

export function AcceptInvitePage() {
  const token = useSearchParams()[0].get('token') ?? '';
  const { signIn } = useAuth();
  const nav = useNavigate();
  const [f, setF] = useState({ full_name: '', phone: '', password: '', confirm: '' });
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const mismatch = f.confirm.length > 0 && f.confirm !== f.password;

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const r = await api<{ token: string }>('/portal/auth/accept-invite', {
        auth: false, body: { token, full_name: f.full_name, password: f.password, ...(f.phone ? { phone: f.phone } : {}) },
      });
      nav(homeFor(await signIn(r.token)), { replace: true });
    } catch (e) {
      setErr(e instanceof ApiError ? e.detailMessage : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <AuthLayout>
      <div className="stack-sm">
        <h1>Gabung ke tim</h1>
        <p className="muted">Lengkapi data Anda untuk menerima undangan.</p>
      </div>
      {!token && <Alert tone="error">Tautan undangan tidak lengkap.</Alert>}
      {err && <Alert tone="error">{err}</Alert>}
      <form className="stack" onSubmit={submit}>
        <TextField label="Nama lengkap" required autoComplete="name" value={f.full_name} onChange={(e) => setF({ ...f, full_name: e.target.value })} />
        <TextField label="No. HP" hint="Opsional, untuk notifikasi darurat" type="tel" autoComplete="tel" value={f.phone} onChange={(e) => setF({ ...f, phone: e.target.value })} />
        <TextField label="Password" hint="Minimal 8 karakter" type="password" autoComplete="new-password" minLength={8} required value={f.password} onChange={(e) => setF({ ...f, password: e.target.value })} />
        <TextField label="Ulangi password" type="password" autoComplete="new-password" required value={f.confirm} error={mismatch ? 'Password tidak sama' : undefined} onChange={(e) => setF({ ...f, confirm: e.target.value })} />
        <Button variant="primary" type="submit" loading={busy} disabled={!token || mismatch || f.password.length < 8 || f.full_name.length < 2}>Terima undangan</Button>
      </form>
    </AuthLayout>
  );
}
