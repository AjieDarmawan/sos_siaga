import { useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { EnvelopeSimpleOpen } from '@phosphor-icons/react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { AuthLayout } from '../components/AuthLayout';
import { Alert, Empty, Spinner } from '../components/ui';

export function VerifyEmailPage() {
  const [sp] = useSearchParams();
  const token = sp.get('token');
  const { signIn } = useAuth();
  const nav = useNavigate();
  const [err, setErr] = useState<string | null>(null);
  const ran = useRef(false);

  useEffect(() => {
    if (!token || ran.current) return;
    ran.current = true; // StrictMode memanggil effect 2x; token sekali pakai
    api<{ token: string }>('/portal/auth/verify-email', { body: { token }, auth: false })
      .then((r) => signIn(r.token))
      .then(() => nav('/onboarding?verified=1', { replace: true }))
      .catch((e) => setErr(e.message));
  }, [token, signIn, nav]);

  return (
    <AuthLayout>
      {!token ? (
        <Empty icon={<EnvelopeSimpleOpen size={40} />} title="Cek kotak masuk Anda">
          Kami mengirim tautan verifikasi ke email PIC. Tautan berlaku 48 jam. <Link to="/login">Kembali ke halaman masuk</Link>
        </Empty>
      ) : err ? (
        <>
          <Alert tone="error" title="Verifikasi gagal">{err}</Alert>
          <p className="small">Minta tautan baru dari <Link to="/login">halaman masuk</Link>.</p>
        </>
      ) : (
        <Spinner label="Memverifikasi email" />
      )}
    </AuthLayout>
  );
}
