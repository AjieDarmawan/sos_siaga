import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { ArrowLeft, ArrowRight, CloudCheck, EnvelopeSimple } from '@phosphor-icons/react';
import { api, ApiError } from '../lib/api';
import { ENTITY_LABEL } from '../lib/format';
import { AuthLayout } from '../components/AuthLayout';
import { Alert, Button, Field, TextField } from '../components/ui';

const DRAFT_KEY = 'siagasos.register.draft';

const empty = {
  legal_name: '', entity_type: 'pt', nib: '', npwp: '', address: '', phone: '', website: '', industry: '',
  full_name: '', email: '', pic_phone: '', position: '', is_director: true, password: '',
  est_users: '', usage_plan: '', accept_terms: false,
};
type Form = typeof empty;
type Errors = Partial<Record<keyof Form, string>>;

const FREE_MAIL = /@(gmail|yahoo|ymail|hotmail|outlook|live|icloud|aol|proton(mail)?)\.[a-z.]+$/i;
const PHONE = /^\+?[0-9 ()-]{6,20}$/;

/** Aturan sama dengan validasi server (routes/portal/auth.ts) supaya error muncul saat blur, bukan setelah submit. */
function validate(f: Form, step: number): Errors {
  const e: Errors = {};
  if (step === 0) {
    if (f.legal_name.trim().length < 3) e.legal_name = 'Nama badan usaha minimal 3 karakter';
    if (!/^\d{13}$/.test(f.nib)) e.nib = 'NIB terdiri dari 13 digit angka';
    if (!/^\d{15,16}$/.test(f.npwp.replace(/[.\-\s]/g, ''))) e.npwp = 'NPWP 15 atau 16 digit';
    if (f.address.trim().length < 10) e.address = 'Alamat minimal 10 karakter';
    if (!PHONE.test(f.phone)) e.phone = 'Nomor telepon tidak valid';
    if (f.website && !/^https?:\/\/\S+\.\S+/.test(f.website)) e.website = 'Awali dengan https://';
    if (f.industry.trim().length < 2) e.industry = 'Wajib diisi';
  }
  if (step === 1) {
    if (f.full_name.trim().length < 2) e.full_name = 'Wajib diisi';
    if (!/^\S+@\S+\.\S+$/.test(f.email)) e.email = 'Email tidak valid';
    if (!PHONE.test(f.pic_phone)) e.pic_phone = 'Nomor HP tidak valid';
    if (f.position.trim().length < 2) e.position = 'Wajib diisi';
    if (f.password.length < 8) e.password = 'Minimal 8 karakter';
  }
  if (step === 2) {
    const n = Number(f.est_users);
    if (!Number.isInteger(n) || n < 1) e.est_users = 'Isi perkiraan jumlah pengguna (angka)';
    if (f.usage_plan.trim().length < 10) e.usage_plan = 'Ceritakan singkat rencana penggunaan (min. 10 karakter)';
    if (!f.accept_terms) e.accept_terms = 'Syarat & ketentuan wajib disetujui';
  }
  return e;
}

const STEPS = ['Data perusahaan', 'Penanggung jawab', 'Rencana & persetujuan'];

export function RegisterPage() {
  const [f, setF] = useState<Form>(() => {
    try { return { ...empty, ...JSON.parse(localStorage.getItem(DRAFT_KEY) ?? '{}'), password: '' }; } catch { return empty; }
  });
  const [step, setStep] = useState(0);
  const [touched, setTouched] = useState<Set<string>>(new Set());
  const [showAll, setShowAll] = useState(false);
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState<{ email: string; devToken?: string } | null>(null);
  const headRef = useRef<HTMLHeadingElement>(null);

  // Draf otomatis (F-21). Password tidak pernah disimpan.
  useEffect(() => {
    const t = setTimeout(() => {
      try {
        const { password: _pw, ...rest } = f;
        localStorage.setItem(DRAFT_KEY, JSON.stringify(rest));
        setSaved(true);
      } catch { /* storage diblokir */ }
    }, 600);
    setSaved(false);
    return () => clearTimeout(t);
  }, [f]);

  useEffect(() => { headRef.current?.focus(); }, [step]);

  const errors = validate(f, step);
  const show = (k: keyof Form) => (showAll || touched.has(k) ? errors[k] : undefined);
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setF((x) => ({ ...x, [k]: v }));
  const bind = (k: keyof Form) => ({
    value: String(f[k]),
    onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => set(k, e.target.value as never),
    onBlur: () => setTouched((t) => new Set(t).add(k)),
    error: show(k),
  });
  /** Untuk elemen DOM langsung (textarea) yang tidak menerima prop `error`. */
  const raw = (k: keyof Form) => { const { error: _e, ...r } = bind(k); return r; };

  async function next(e: FormEvent) {
    e.preventDefault();
    if (Object.keys(errors).length) {
      setShowAll(true);
      return;
    }
    setShowAll(false);
    if (step < 2) return setStep(step + 1);

    setBusy(true);
    setErr(null);
    try {
      const r = await api<{ dev_verification_token?: string }>('/portal/auth/register', {
        auth: false,
        body: {
          company: {
            legal_name: f.legal_name.trim(), entity_type: f.entity_type, nib: f.nib, npwp: f.npwp, address: f.address.trim(),
            phone: f.phone, ...(f.website ? { website: f.website } : {}), industry: f.industry.trim(),
            est_users: Number(f.est_users), usage_plan: f.usage_plan.trim(),
          },
          pic: { full_name: f.full_name.trim(), email: f.email.trim(), phone: f.pic_phone, position: f.position.trim(), is_director: f.is_director, password: f.password },
          accept_terms: true,
        },
      });
      try { localStorage.removeItem(DRAFT_KEY); } catch { /* */ }
      setDone({ email: f.email, devToken: r.dev_verification_token });
    } catch (e) {
      const ae = e as ApiError;
      setErr(ae.detailMessage ?? ae.message);
      if (ae.code === 'nib_registered' || ae.code === 'reapply_too_soon') setStep(0);
      if (ae.code === 'email_registered') setStep(1);
    } finally {
      setBusy(false);
    }
  }

  if (done) {
    return (
      <AuthLayout>
        <div className="stack" style={{ justifyItems: 'start' }}>
          <EnvelopeSimple size={40} />
          <h1>Verifikasi email Anda</h1>
          <p className="muted">Kami mengirim tautan verifikasi ke <strong>{done.email}</strong>. Setelah verifikasi, Anda bisa langsung memakai kunci test dan mengunggah dokumen perusahaan.</p>
          {done.devToken && (
            <Alert tone="info" title="Mode pengembangan">
              Email tidak dikirim tanpa SMTP. <Link to={`/verify-email?token=${done.devToken}`}>Verifikasi sekarang</Link>
            </Alert>
          )}
          <Link to="/login" className="small">Kembali ke halaman masuk</Link>
        </div>
      </AuthLayout>
    );
  }

  const picHint = f.is_director ? undefined : 'Anda perlu mengunggah surat kuasa dari direksi setelah verifikasi email.';

  return (
    <AuthLayout wide>
      <div className="stack-sm">
        <ol className="stepper" aria-label="Langkah pendaftaran">
          {STEPS.map((s, i) => (
            <li key={s} data-state={i < step ? 'done' : i === step ? 'current' : 'todo'} aria-current={i === step ? 'step' : undefined}>
              {i + 1}. {s}
            </li>
          ))}
        </ol>
        <div className="row-between" style={{ marginTop: 12 }}>
          <h1 ref={headRef} tabIndex={-1} style={{ outline: 'none' }}>{STEPS[step]}</h1>
          <span className="small muted row" aria-live="polite" style={{ gap: 4 }}>
            {saved && <><CloudCheck size={16} />Draf tersimpan</>}
          </span>
        </div>
        <p className="muted small">Langkah {step + 1} dari 3. Data dicocokkan dengan dokumen legal saat review.</p>
      </div>

      {err && <Alert tone="error">{err}</Alert>}

      <form className="stack" onSubmit={next} noValidate>
        {step === 0 && (
          <>
            <div className="grid-2">
              <TextField label="Nama badan usaha (sesuai akta)" autoComplete="organization" {...bind('legal_name')} />
              <Field label="Bentuk usaha" htmlFor="entity_type">
                <select id="entity_type" className="select" value={f.entity_type} onChange={(e) => set('entity_type', e.target.value)}>
                  {Object.entries(ENTITY_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </Field>
              <TextField label="NIB" inputMode="numeric" maxLength={13} hint="13 digit dari OSS" {...bind('nib')}
                onChange={(e) => set('nib', e.target.value.replace(/\D/g, ''))} />
              <TextField label="NPWP badan" inputMode="numeric" hint="15 atau 16 digit" {...bind('npwp')} />
            </div>
            <Field label="Alamat kantor" htmlFor="address" error={show('address')}>
              <textarea id="address" className="textarea" rows={2} aria-invalid={!!show('address') || undefined} {...raw('address')} />
            </Field>
            <div className="grid-2">
              <TextField label="Telepon kantor" type="tel" autoComplete="tel" {...bind('phone')} />
              <TextField label="Website" hint="Opsional" type="url" placeholder="https://" {...bind('website')} />
              <TextField label="Industri" placeholder="mis. Logistik, Properti, Pendidikan" {...bind('industry')} />
            </div>
          </>
        )}

        {step === 1 && (
          <>
            <div className="grid-2">
              <TextField label="Nama lengkap PIC" autoComplete="name" {...bind('full_name')} />
              <TextField label="Jabatan" autoComplete="organization-title" {...bind('position')} />
              <TextField label="Email kerja" type="email" autoComplete="email" {...bind('email')}
                hint={FREE_MAIL.test(f.email) ? 'Email gratis boleh, tetapi email domain perusahaan mempercepat review.' : 'Dipakai untuk login dan notifikasi status'} />
              <TextField label="No. HP PIC" type="tel" autoComplete="tel" {...bind('pic_phone')} />
            </div>
            <label className="check">
              <input type="checkbox" checked={f.is_director} onChange={(e) => set('is_director', e.target.checked)} />
              <span>PIC adalah anggota direksi / pengurus yang tercantum di akta</span>
            </label>
            {picHint && <Alert tone="info">{picHint}</Alert>}
            <TextField label="Password" type="password" autoComplete="new-password" hint="Minimal 8 karakter. Tidak ikut disimpan di draf." {...bind('password')} />
          </>
        )}

        {step === 2 && (
          <>
            <div className="grid-2">
              <TextField label="Perkiraan jumlah pengguna akhir" inputMode="numeric" {...bind('est_users')}
                onChange={(e) => set('est_users', e.target.value.replace(/\D/g, ''))} />
            </div>
            <Field label="Rencana penggunaan" htmlFor="usage_plan" error={show('usage_plan')}
              hint="Siapa yang menekan tombol SOS, siapa yang merespons, dan di aplikasi apa.">
              <textarea id="usage_plan" className="textarea" rows={4} aria-invalid={!!show('usage_plan') || undefined} {...raw('usage_plan')} />
            </Field>
            <div className="card card-pad stack-sm" style={{ background: 'var(--surface-2)', boxShadow: 'none' }}>
              <h3>Ringkasan</h3>
              <dl className="kv">
                <dt>Perusahaan</dt><dd>{f.legal_name} <span className="muted">({ENTITY_LABEL[f.entity_type as keyof typeof ENTITY_LABEL]})</span></dd>
                <dt>NIB / NPWP</dt><dd className="mono">{f.nib} · {f.npwp}</dd>
                <dt>PIC</dt><dd>{f.full_name} ({f.position}) · {f.email}</dd>
              </dl>
            </div>
            <div className="field">
              <label className="check">
                <input type="checkbox" checked={f.accept_terms} onChange={(e) => set('accept_terms', e.target.checked)} aria-invalid={!!show('accept_terms') || undefined} />
                <span>Saya menyetujui Syarat & Ketentuan dan Kebijakan Privasi SiagaSOS, dan menyatakan data di atas benar.</span>
              </label>
              {show('accept_terms') && <span className="error" role="alert">{show('accept_terms')}</span>}
            </div>
          </>
        )}

        <div className="row-between" style={{ marginTop: 8 }}>
          {step > 0
            ? <Button type="button" onClick={() => { setShowAll(false); setStep(step - 1); }}><ArrowLeft size={16} />Kembali</Button>
            : <span className="small muted">Sudah punya akun? <Link to="/login">Masuk</Link></span>}
          <Button variant="primary" type="submit" loading={busy}>
            {step < 2 ? <>Lanjut<ArrowRight size={16} /></> : 'Daftar & kirim verifikasi'}
          </Button>
        </div>
      </form>
    </AuthLayout>
  );
}
