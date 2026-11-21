import { StrictMode, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { SOSAttach, SOSButton, SOSProvider, useSOS } from '@siagasos/react';
import './demo.css';

/**
 * Contoh aplikasi klien (mis. aplikasi karyawan / warga) yang memasang SiagaSOS:
 * tahan tombol SOS → laporan terkirim → tambahkan foto, video, atau rekaman suara.
 * Kunci: ?key=pk_... di URL, atau VITE_SOS_KEY di .env.
 */
const params = new URLSearchParams(location.search);
const KEY = params.get('key') ?? (import.meta.env.VITE_SOS_KEY as string | undefined) ?? '';
const BASE = (import.meta.env.VITE_API_URL as string | undefined) ?? 'http://localhost:4000';
const USER = { ref: 'demo-user-01', name: params.get('name') ?? 'Budi (demo)', phone: '+628111222333' };

const STATUS_TEXT: Record<string, string> = {
  idle: 'Tahan tombol 3 detik bila Anda dalam bahaya',
  sending: 'Mengirim laporan…',
  queued: 'Tidak ada sinyal. Laporan dikirim otomatis saat online.',
  open: 'Laporan terkirim. Menunggu petugas…',
  acknowledged: 'Petugas sudah menerima laporan Anda',
  in_progress: 'Petugas sedang menuju / menangani',
  resolved: 'Laporan selesai ditangani',
  cancelled: 'Laporan dibatalkan',
  false_alarm: 'Ditandai sebagai alarm palsu',
};

function Screen() {
  const { status, activeReport, cancel, reset } = useSOS();
  const done = ['resolved', 'cancelled', 'false_alarm'].includes(status);
  return (
    <div className="screen">
      <header>
        <div><b>Aplikasi Karyawan</b><small>{USER.name}</small></div>
        {KEY.startsWith('pk_test_') && <span className="tag">TEST</span>}
      </header>
      <main>
        <p className={`status s-${status}`} aria-live="polite">{activeReport?.statusMessage ?? STATUS_TEXT[status] ?? status}</p>
        <SOSButton category="kriminal" holdToConfirm={3} />
        <SOSAttach />
        {activeReport && !done && status === 'open' && <button className="link" onClick={() => cancel('Salah tekan')}>Batalkan (salah tekan)</button>}
        {done && <button className="link" onClick={reset}>Selesai, kembali</button>}
      </main>
      <footer>Dalam bahaya langsung? Hubungi <a href="tel:110">110</a></footer>
    </div>
  );
}

function KeyForm() {
  const [k, setK] = useState('');
  return (
    <form className="screen keyform" onSubmit={(e) => { e.preventDefault(); location.search = `?key=${encodeURIComponent(k.trim())}`; }}>
      <h1>Demo aplikasi klien</h1>
      <p>Tempel publishable key dari portal (App & kunci API). Origin <code>{location.origin}</code> harus terdaftar di app tersebut.</p>
      <input value={k} onChange={(e) => setK(e.target.value)} placeholder="pk_test_..." aria-label="Publishable key" />
      <button disabled={!/^pk_(test|live)_/.test(k.trim())}>Mulai</button>
    </form>
  );
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    {KEY ? <SOSProvider apiKey={KEY} baseUrl={BASE} sourceKey="demo-react" user={USER}><Screen /></SOSProvider> : <KeyForm />}
  </StrictMode>,
);
