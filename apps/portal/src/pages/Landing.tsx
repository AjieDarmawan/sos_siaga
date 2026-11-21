import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import {
  ArrowRight, Bell, Buildings, CheckCircle, Code, CloudArrowUp, Copy, FileLock, GraduationCap, Key, List,
  MapPinLine, Package, PlugsConnected, ShieldCheck, Siren, Storefront, Truck, UsersThree, WifiSlash, X,
} from '@phosphor-icons/react';
import { useAuth } from '../lib/auth';
import { BrandMark } from '../components/Layout';
import { ThemeMenu } from '../components/ThemeMenu';
import '../landing.css';

/**
 * Elemen `.reveal` muncul (fade + naik) saat masuk viewport.
 * IntersectionObserver saja tidak cukup: saat scroll cepat / lompat lewat anchor, elemen bisa melompat dari bawah ke atas
 * viewport tanpa pernah "berpotongan" di satu frame pun, jadi tidak pernah muncul. Fallback scroll (rAF) menangani itu.
 */
function useReveal() {
  useEffect(() => {
    const pending = new Set<HTMLElement>(Array.from(document.querySelectorAll<HTMLElement>('.lp .reveal:not(.in)')));
    const show = (e: Element) => { e.classList.add('in'); pending.delete(e as HTMLElement); io?.unobserve(e); };
    const io = 'IntersectionObserver' in window
      ? new IntersectionObserver((es) => es.forEach((e) => e.isIntersecting && show(e.target)), { rootMargin: '0px 0px -8% 0px', threshold: 0.12 })
      : null;
    pending.forEach((e) => io?.observe(e));
    let raf = 0;
    const sweep = () => {
      raf = 0;
      const limit = window.innerHeight * 0.92;
      pending.forEach((e) => e.getBoundingClientRect().top < limit && show(e));
      if (!pending.size) window.removeEventListener('scroll', onScroll);
    };
    const onScroll = () => { raf ||= requestAnimationFrame(sweep); };
    window.addEventListener('scroll', onScroll, { passive: true });
    sweep();
    return () => { io?.disconnect(); window.removeEventListener('scroll', onScroll); cancelAnimationFrame(raf); };
  }, []);
}

function CountUp({ to, suffix = '', decimals = 0 }: { to: number; suffix?: string; decimals?: number }) {
  const ref = useRef<HTMLSpanElement>(null);
  const [v, setV] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) { setV(to); return; }
    const io = new IntersectionObserver(([e]) => {
      if (!e?.isIntersecting) return;
      io.disconnect();
      const t0 = performance.now();
      const tick = (t: number) => {
        const p = Math.min(1, (t - t0) / 1200);
        setV(to * (1 - Math.pow(1 - p, 3)));
        if (p < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    }, { threshold: 0.5 });
    io.observe(el);
    return () => io.disconnect();
  }, [to]);
  return <span ref={ref}>{v.toLocaleString('id-ID', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}{suffix}</span>;
}

const NAV = [['#cara-kerja', 'Cara kerja'], ['#fitur', 'Fitur'], ['#developer', 'Developer'], ['#harga', 'Harga'], ['#faq', 'FAQ']];
const DocsLink = () => <Link to="/docs">Dokumentasi</Link>;

export function LandingPage() {
  const { me } = useAuth();
  const [menu, setMenu] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  useReveal();
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 12);
    on();
    window.addEventListener('scroll', on, { passive: true });
    return () => window.removeEventListener('scroll', on);
  }, []);
  useEffect(() => { document.title = 'SiagaSOS — Tombol darurat siap pakai untuk aplikasi Anda'; }, []);

  return (
    <div className="lp">
      <a href="#isi" className="skip-link">Lewati ke konten</a>
      <header className={`lp-nav ${scrolled ? 'scrolled' : ''}`}>
        <div className="lp-wrap lp-nav-in">
          <Link to="/" className="lp-brand" aria-label="SiagaSOS beranda"><BrandMark size={30} /><span>SiagaSOS</span></Link>
          <nav className="lp-links" aria-label="Navigasi">
            {NAV.map(([h, l]) => <a key={h} href={h}>{l}</a>)}
            <DocsLink />
          </nav>
          <div className="lp-nav-cta">
            <ThemeMenu variant="dark" />
            {me ? <Link to="/dashboard" className="lp-btn lp-btn-light">Buka dashboard<ArrowRight size={16} weight="bold" /></Link> : (
              <>
                <Link to="/login" className="lp-btn lp-btn-ghost">Masuk</Link>
                <Link to="/register" className="lp-btn lp-btn-sos">Coba gratis</Link>
              </>
            )}
            <button className="lp-menu-btn" aria-label={menu ? 'Tutup menu' : 'Buka menu'} aria-expanded={menu} onClick={() => setMenu(!menu)}>
              {menu ? <X size={22} /> : <List size={22} />}
            </button>
          </div>
        </div>
        {menu && (
          <div className="lp-mobile-menu" onClick={() => setMenu(false)}>
            {NAV.map(([h, l]) => <a key={h} href={h}>{l}</a>)}
            <DocsLink />
            {!me && <Link to="/login">Masuk</Link>}
          </div>
        )}
      </header>

      <main id="isi">
        <Hero loggedIn={!!me} />
        <UseCases />
        <HowItWorks />
        <Features />
        <Developer />
        <Pricing />
        <Faq />
        <FinalCta />
      </main>
      <Footer />
    </div>
  );
}

// ---------------------------------------------------------------- 1. hero
function Hero({ loggedIn }: { loggedIn: boolean }) {
  return (
    <section className="lp-hero" aria-labelledby="hero-title">
      <div className="lp-hero-bg" aria-hidden><span className="g1" /><span className="g2" /><span className="grid" /></div>
      <div className="lp-wrap lp-hero-in">
        <div className="lp-hero-copy">
          <p className="lp-eyebrow rise"><span className="dot" />SOS-as-a-Service untuk perusahaan di Indonesia</p>
          <h1 id="hero-title" className="rise" style={{ ['--d' as string]: '80ms' }}>
            Tombol darurat untuk aplikasi Anda, <span className="hl">aktif dalam hitungan menit.</span>
          </h1>
          <p className="lp-lead rise" style={{ ['--d' as string]: '160ms' }}>
            Pasang SDK, karyawan atau pengguna Anda menahan tombol SOS, dan tim keamanan menerima laporan lengkap dengan lokasi live di dashboard,
            tanpa membangun pusat komando sendiri.
          </p>
          <div className="lp-hero-cta rise" style={{ ['--d' as string]: '240ms' }}>
            <Link to={loggedIn ? '/dashboard' : '/register'} className="lp-btn lp-btn-sos lp-btn-lg">
              {loggedIn ? 'Buka dashboard' : 'Mulai gratis dengan kunci test'}<ArrowRight size={18} weight="bold" />
            </Link>
            <a href="#cara-kerja" className="lp-btn lp-btn-outline lp-btn-lg">Lihat cara kerja</a>
          </div>
          <ul className="lp-hero-points rise" style={{ ['--d' as string]: '320ms' }}>
            <li><CheckCircle size={18} weight="fill" />Tanpa kartu kredit</li>
            <li><CheckCircle size={18} weight="fill" />Kunci test langsung aktif</li>
            <li><CheckCircle size={18} weight="fill" />Data di server Indonesia</li>
          </ul>
        </div>
        <HeroScene />
      </div>
    </section>
  );
}

/** Animasi alur SOS: tahan tombol di HP → sinyal → laporan muncul di dashboard → diterima. Murni CSS, loop 9 detik. */
function HeroScene() {
  return (
    <div className="scene rise" style={{ ['--d' as string]: '200ms' }} role="img"
      aria-label="Ilustrasi: pengguna menahan tombol SOS di ponsel, laporan muncul di dashboard tim keamanan lengkap dengan lokasi, lalu statusnya berubah menjadi diterima.">
      <div className="phone">
        <div className="phone-notch" />
        <div className="phone-head"><span>Aplikasi Karyawan</span><span className="lp-test">TEST</span></div>
        <div className="sos-wrap">
          <svg className="sos-ring" viewBox="0 0 120 120" aria-hidden>
            <circle cx="60" cy="60" r="54" className="track" />
            <circle cx="60" cy="60" r="54" className="prog" />
          </svg>
          <div className="sos-btn"><span>SOS</span><small>tahan 3 dtk</small></div>
          <span className="ripple r1" /><span className="ripple r2" />
        </div>
        <div className="phone-status">
          <span className="ps ps-1">Tahan untuk mengirim…</span>
          <span className="ps ps-2"><CheckCircle size={14} weight="fill" />Terkirim ke tim keamanan</span>
          <span className="ps ps-3"><CheckCircle size={14} weight="fill" />Petugas menuju lokasi</span>
        </div>
      </div>

      <svg className="beam" viewBox="0 0 120 40" preserveAspectRatio="none" aria-hidden>
        <path d="M2 30 C 40 30, 60 8, 118 10" className="beam-path" />
        <circle r="3.5" className="beam-dot"><animateMotion dur="9s" repeatCount="indefinite" keyPoints="0;0;1;1" keyTimes="0;0.3;0.42;1" calcMode="linear" path="M2 30 C 40 30, 60 8, 118 10" /></circle>
      </svg>

      <div className="sc-dash">
        <div className="sc-dash-top"><span className="sc-live"><i />Realtime</span><span className="sc-dash-title">Dashboard laporan</span><Bell size={14} className="bell" /></div>
        <div className="sc-dash-body">
          <div className="sc-dash-map">
            <span className="road r-a" /><span className="road r-b" /><span className="road r-c" />
            <span className="pin p-old" /><span className="pin p-old2" />
            <span className="pin p-new"><i /></span>
          </div>
          <div className="sc-dash-list">
            <div className="ditem new">
              <b>Kriminal</b><span className="st st-open">Baru</span><span className="st st-ack">Diterima</span>
              <small>Gudang Cakung · baru saja</small>
            </div>
            <div className="ditem"><b>Medis</b><span className="st st-prog">Ditangani</span><small>Kantor Sudirman · 14 mnt</small></div>
            <div className="ditem"><b>Kecelakaan</b><span className="st st-done">Selesai</span><small>Armada kurir · 2 jam</small></div>
          </div>
        </div>
        <div className="sc-dash-alarm"><Siren size={14} weight="fill" />1 laporan baru belum diterima</div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- 2. untuk siapa
const CASES = [
  { icon: Package, title: 'Logistik & gudang', text: 'Pekerja shift malam dan area loading dock terhubung langsung ke pos keamanan.' },
  { icon: Truck, title: 'Kurir & armada', text: 'Pengemudi di jalan mengirim SOS dengan lokasi yang terus diperbarui sampai aman.' },
  { icon: Buildings, title: 'Properti & apartemen', text: 'Penghuni menghubungi building management dari aplikasi penghuni yang sudah ada.' },
  { icon: GraduationCap, title: 'Kampus & sekolah', text: 'Mahasiswa dan staf punya jalur darurat ke satpam kampus, 24 jam.' },
  { icon: Storefront, title: 'Ritel & jaringan toko', text: 'Kasir dan staf toko memanggil bantuan tanpa harus menelepon.' },
  { icon: UsersThree, title: 'HR & keselamatan kerja', text: 'Program K3 dan karyawan lapangan dengan riwayat insiden yang tercatat rapi.' },
];

function UseCases() {
  return (
    <section className="lp-sec" aria-labelledby="uc-title">
      <div className="lp-wrap">
        <div className="lp-problem reveal">
          <div>
            <p className="lp-kicker">Masalahnya</p>
            <h2 id="uc-title">Dalam keadaan darurat, setiap detik untuk mencari nomor telepon itu terbuang.</h2>
          </div>
          <ul className="lp-problem-list">
            <li><X size={18} weight="bold" />Grup WhatsApp darurat tenggelam di antara pesan lain dan tanpa lokasi yang tepat.</li>
            <li><X size={18} weight="bold" />Membangun sistem SOS sendiri butuh berbulan-bulan: aplikasi, server, notifikasi, peta.</li>
            <li><X size={18} weight="bold" />Tidak ada catatan siapa menangani apa, kapan, dan bagaimana hasilnya.</li>
          </ul>
        </div>
        <div className="lp-sec-head reveal">
          <p className="lp-kicker">Untuk siapa</p>
          <h2>Satu infrastruktur SOS, banyak jenis organisasi</h2>
        </div>
        <div className="lp-cases">
          {CASES.map(({ icon: Icon, title, text }, i) => (
            <article key={title} className="lp-case reveal" style={{ ['--d' as string]: `${i * 60}ms` }}>
              <span className="lp-ico"><Icon size={22} weight="duotone" /></span>
              <h3>{title}</h3>
              <p>{text}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------- 3. cara kerja
function HowItWorks() {
  const steps = [
    { icon: Code, title: 'Pasang SDK', text: 'Daftar, buat app, dan tempel publishable key ke SDK web atau Android. Tiga baris kode.' },
    { icon: Siren, title: 'Pengguna menahan tombol', text: 'Tahan 3 detik untuk mencegah salah tekan. Lokasi dan data pelapor ikut terkirim, bahkan saat sinyal putus.' },
    { icon: Bell, title: 'Tim Anda merespons', text: 'Laporan muncul realtime di dashboard dengan bunyi alarm, peta, dan status yang dilihat pelapor.' },
  ];
  return (
    <section id="cara-kerja" className="lp-sec lp-sec-alt" aria-labelledby="how-title">
      <div className="lp-wrap">
        <div className="lp-sec-head reveal">
          <p className="lp-kicker">Cara kerja</p>
          <h2 id="how-title">Dari tombol ke petugas dalam tiga langkah</h2>
        </div>
        <ol className="lp-steps">
          {steps.map(({ icon: Icon, title, text }, i) => (
            <li key={title} className="lp-step reveal" style={{ ['--d' as string]: `${i * 120}ms` }}>
              <span className="lp-step-n">{i + 1}</span>
              <span className="lp-step-ico"><Icon size={26} weight="duotone" /></span>
              <h3>{title}</h3>
              <p>{text}</p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------- 4. fitur (bento)
function Features() {
  return (
    <section id="fitur" className="lp-sec" aria-labelledby="feat-title">
      <div className="lp-wrap">
        <div className="lp-sec-head reveal">
          <p className="lp-kicker">Fitur</p>
          <h2 id="feat-title">Semua yang dibutuhkan jalur darurat, sudah jadi</h2>
        </div>
        <div className="bento">
          <Bento cls="b-dash" icon={<Bell size={22} weight="duotone" />} title="Dashboard responder realtime"
            text="Daftar dan peta laporan yang langsung diperbarui, bunyi alarm berulang sampai laporan diterima, notifikasi browser, dan timeline penanganan.">
            <div className="mini-feed" aria-hidden>
              <div className="mf"><i className="r" />Kriminal<span>Baru</span></div>
              <div className="mf"><i className="a" />Medis<span>Diterima</span></div>
              <div className="mf"><i className="g" />Kebakaran<span>Selesai</span></div>
            </div>
          </Bento>
          <Bento cls="b-loc" icon={<MapPinLine size={22} weight="duotone" />} title="Lokasi live"
            text="Posisi pelapor dikirim berkala dan digambar sebagai jejak di peta, berhenti otomatis saat kasus selesai." />
          <Bento cls="b-off" icon={<WifiSlash size={22} weight="duotone" />} title="Tetap terkirim saat sinyal putus"
            text="SDK menyimpan laporan di antrian offline dan mengirim ulang otomatis, tanpa laporan ganda (idempotency)." />
          <Bento cls="b-hook" icon={<PlugsConnected size={22} weight="duotone" />} title="Webhook & API server"
            text="Teruskan setiap laporan ke sistem Anda. Ditandatangani HMAC-SHA256, retry otomatis hingga 24 jam, lengkap dengan log." />
          <Bento cls="b-sec" icon={<ShieldCheck size={22} weight="duotone" />} title="Keamanan & UU PDP"
            text="Data tiap perusahaan diisolasi di level database, dokumen dienkripsi AES-256, dan setiap akses detail laporan tercatat di audit log." />
          <Bento cls="b-key" icon={<Key size={22} weight="duotone" />} title="Kunci yang bisa dikendalikan"
            text="Batasi ke domain atau bundle id, rotasi dengan masa tenggang, cabut seketika. Mode test terpisah dari data live." />
        </div>
      </div>
    </section>
  );
}

function Bento({ cls, icon, title, text, children }: { cls: string; icon: ReactNode; title: string; text: string; children?: ReactNode }) {
  return (
    <article className={`bento-card ${cls} reveal`}>
      <span className="lp-ico">{icon}</span>
      <h3>{title}</h3>
      <p>{text}</p>
      {children}
    </article>
  );
}

// ---------------------------------------------------------------- 5. developer
const SNIPPETS: Record<string, string> = {
  React: `import { SOSProvider, SOSButton } from '@siagasos/react';

<SOSProvider apiKey="pk_test_..." sourceKey="gudang-cakung">
  <SOSButton category="kriminal" holdToConfirm={3} />
</SOSProvider>`,
  JavaScript: `import { SiagaSOS } from '@siagasos/js';

const sos = SiagaSOS.init({ apiKey: 'pk_test_...' });
await sos.trigger({ category: 'medis', message: 'Rekan pingsan' });
sos.on('status', (r) => console.log(r.status)); // open → acknowledged → resolved`,
  Webhook: `// Verifikasi X-SOS-Signature: t=<unix>,v1=<hex>
const [t, v1] = header.split(',').map((p) => p.split('=')[1]);
const expected = hmacSha256(WEBHOOK_SECRET, \`\${t}.\${rawBody}\`);
if (!timingSafeEqual(expected, v1)) return res.status(401).end();
// event: report.created | report.status_changed | report.cancelled`,
};

function Developer() {
  const [tab, setTab] = useState('React');
  const [copied, setCopied] = useState(false);
  return (
    <section id="developer" className="lp-sec lp-dark" aria-labelledby="dev-title">
      <div className="lp-wrap lp-dev">
        <div className="lp-dev-copy reveal">
          <p className="lp-kicker">Untuk developer</p>
          <h2 id="dev-title">Integrasi tiga baris. Ganti <code>pk_test_</code> ke <code>pk_live_</code> saat siap.</h2>
          <p>SDK tanpa dependency, bekerja di React, JavaScript biasa, dan segera Android. Mode test memakai data terpisah, jadi tim Anda bisa mencoba alur lengkap sebelum dokumen perusahaan selesai diverifikasi.</p>
          <Link to="/docs" className="lp-btn lp-btn-outline" style={{ justifySelf: 'start' }}>Baca dokumentasi<ArrowRight size={16} weight="bold" /></Link>
          <dl className="lp-stats">
            <div><dt><CountUp to={3.2} decimals={1} suffix=" KB" /></dt><dd>ukuran SDK (gzip)</dd></div>
            <div><dt>≤ <CountUp to={5} suffix=" dtk" /></dt><dd>status sampai ke pelapor</dd></div>
            <div><dt><CountUp to={24} suffix=" jam" /></dt><dd>retry webhook otomatis</dd></div>
          </dl>
        </div>
        <div className="code-card reveal" style={{ ['--d' as string]: '120ms' }}>
          <div className="code-tabs">
            <div role="tablist" aria-label="Contoh kode" style={{ display: 'flex', gap: 4 }}>
              {Object.keys(SNIPPETS).map((k) => (
                <button key={k} role="tab" aria-selected={tab === k} onClick={() => setTab(k)}>{k}</button>
              ))}
            </div>
            <button className="code-copy" aria-label="Salin kode" onClick={async () => {
              await navigator.clipboard?.writeText(SNIPPETS[tab]!).catch(() => {});
              setCopied(true);
              setTimeout(() => setCopied(false), 1500);
            }}>{copied ? <CheckCircle size={16} weight="fill" /> : <Copy size={16} />}{copied ? 'Tersalin' : 'Salin'}</button>
          </div>
          <pre key={tab} className="code-body" role="tabpanel"><code>{SNIPPETS[tab]}</code></pre>
        </div>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------- 6. verifikasi & harga
function Pricing() {
  const flow = [
    { icon: CloudArrowUp, t: 'Daftar 3 langkah', d: 'Data perusahaan & penanggung jawab' },
    { icon: Key, t: 'Kunci test aktif', d: 'Langsung setelah verifikasi email' },
    { icon: FileLock, t: 'Unggah dokumen', d: 'NIB, NPWP, akta, KTP PIC' },
    { icon: ShieldCheck, t: 'Review ±2 hari kerja', d: 'Kunci live aktif setelah disetujui' },
  ];
  return (
    <section id="harga" className="lp-sec" aria-labelledby="price-title">
      <div className="lp-wrap">
        <div className="lp-sec-head reveal">
          <p className="lp-kicker">Verifikasi & paket</p>
          <h2 id="price-title">Mulai gratis hari ini, go-live setelah verifikasi</h2>
          <p>Setiap perusahaan diverifikasi untuk mencegah penyalahgunaan jalur darurat.</p>
        </div>
        <ol className="lp-flow">
          {flow.map(({ icon: Icon, t, d }, i) => (
            <li key={t} className="reveal" style={{ ['--d' as string]: `${i * 90}ms` }}>
              <span className="lp-flow-ico"><Icon size={20} weight="duotone" /></span>
              <b>{t}</b><span>{d}</span>
            </li>
          ))}
        </ol>
        <div className="lp-plans">
          <Plan name="Test" price="Gratis" note="selamanya" items={['Kunci pk_test_ & sk_test_', '50 laporan test per hari', 'Dashboard & webhook penuh', 'Tanpa verifikasi dokumen']}
            cta={<Link to="/register" className="lp-btn lp-btn-outline-dark lp-btn-block">Daftar gratis</Link>} />
          <Plan featured name="Live" price="Hubungi kami" note="per jumlah pengguna aktif" items={['Kunci pk_live_ untuk produksi', 'Notifikasi email ke responder', 'Tim responder tanpa batas kursi', 'Ekspor CSV & audit log']}
            cta={<Link to="/register" className="lp-btn lp-btn-sos lp-btn-block">Mulai dari mode test</Link>} />
          <Plan name="Enterprise" price="Custom" note="kontrak tahunan" items={['SLA & dukungan prioritas', 'Integrasi sistem internal', 'Opsi data residency khusus', 'Pendampingan go-live']}
            cta={<a href="mailto:halo@siagasos.id" className="lp-btn lp-btn-outline-dark lp-btn-block">Hubungi sales</a>} />
        </div>
      </div>
    </section>
  );
}

function Plan({ name, price, note, items, cta, featured }: { name: string; price: string; note: string; items: string[]; cta: ReactNode; featured?: boolean }) {
  return (
    <article className={`lp-plan reveal ${featured ? 'featured' : ''}`}>
      {featured && <span className="lp-plan-tag">Paling banyak dipilih</span>}
      <h3>{name}</h3>
      <p className="lp-plan-price">{price}</p>
      <p className="lp-plan-note">{note}</p>
      <ul>{items.map((i) => <li key={i}><CheckCircle size={18} weight="fill" />{i}</li>)}</ul>
      {cta}
    </article>
  );
}

// ---------------------------------------------------------------- 7. FAQ + CTA
const FAQ = [
  ['Apakah SiagaSOS menggantikan 110 / 112?', 'Tidak. SiagaSOS menghubungkan pengguna ke tim keamanan atau responder milik organisasi Anda. Tombol SDK juga menampilkan nomor darurat nasional sebagai cadangan.'],
  ['Berapa lama verifikasi perusahaan?', 'Target keputusan maksimal 2 hari kerja setelah dokumen lengkap diajukan. Selama menunggu, Anda sudah bisa memakai kunci test untuk integrasi.'],
  ['Dokumen apa saja yang dibutuhkan?', 'NIB, NPWP badan, dan KTP penanggung jawab. PT dan yayasan menambahkan akta serta SK Kemenkumham. Bila PIC bukan direksi, lampirkan surat kuasa.'],
  ['Bagaimana jika pengguna tidak ada sinyal?', 'SDK menyimpan laporan di perangkat dan mengirim ulang otomatis begitu koneksi kembali. Setiap laporan punya kunci unik sehingga tidak tercatat dua kali.'],
  ['Bagaimana data pelapor dilindungi?', 'Data setiap perusahaan dipisahkan di level database, dokumen legal dienkripsi, dan setiap kali petugas membuka detail laporan tercatat di audit log, sesuai prinsip UU PDP.'],
  ['Platform apa saja yang didukung?', 'Saat ini web (React dan JavaScript). SDK Android sedang dikembangkan, disusul iOS, Flutter, dan React Native. Backend Anda bisa memakai REST API dan webhook.'],
];

function Faq() {
  return (
    <section id="faq" className="lp-sec lp-sec-alt" aria-labelledby="faq-title">
      <div className="lp-wrap lp-faq">
        <div className="lp-sec-head reveal" style={{ textAlign: 'left', margin: 0 }}>
          <p className="lp-kicker">FAQ</p>
          <h2 id="faq-title">Pertanyaan yang sering diajukan</h2>
          <p>Belum terjawab? Email kami di <a href="mailto:halo@siagasos.id">halo@siagasos.id</a>.</p>
        </div>
        <div className="lp-faq-list">
          {FAQ.map(([q, a], i) => (
            <details key={q} className="reveal" style={{ ['--d' as string]: `${i * 50}ms` }}>
              <summary>{q}</summary>
              <p>{a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}

function FinalCta() {
  return (
    <section className="lp-sec" aria-labelledby="cta-title">
      <div className="lp-wrap">
        <div className="lp-cta reveal">
          <span className="lp-cta-glow" aria-hidden />
          <h2 id="cta-title">Siapkan jalur darurat untuk tim Anda hari ini.</h2>
          <p>Daftar dalam 5 menit, coba alur SOS lengkap dengan kunci test, dan go-live setelah verifikasi.</p>
          <div className="lp-hero-cta" style={{ justifyContent: 'center' }}>
            <Link to="/register" className="lp-btn lp-btn-sos lp-btn-lg">Daftar gratis<ArrowRight size={18} weight="bold" /></Link>
            <Link to="/login" className="lp-btn lp-btn-outline lp-btn-lg">Saya sudah punya akun</Link>
          </div>
        </div>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="lp-footer">
      <div className="lp-wrap lp-footer-in">
        <div>
          <span className="lp-brand"><BrandMark size={26} /><span>SiagaSOS</span></span>
          <p>Infrastruktur tombol darurat untuk aplikasi perusahaan di Indonesia.</p>
        </div>
        <nav aria-label="Tautan footer">
          {NAV.map(([h, l]) => <a key={h} href={h}>{l}</a>)}
          <DocsLink />
          <Link to="/login">Masuk</Link>
        </nav>
        <p className="lp-emergency"><Siren size={16} weight="fill" /><span>Dalam bahaya sekarang? Hubungi <a href="tel:110">110</a> (polisi) atau <a href="tel:112">112</a>.</span></p>
      </div>
      <div className="lp-wrap lp-copy">© {new Date().getFullYear()} SiagaSOS</div>
    </footer>
  );
}
