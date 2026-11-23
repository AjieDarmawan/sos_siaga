import { useEffect, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, CheckCircle, Copy, Info, List, Warning, X } from '@phosphor-icons/react';
import { API_URL } from '../lib/api';
import { useAuth } from '../lib/auth';
import { BrandMark } from '../components/Layout';
import { ThemeMenu } from '../components/ThemeMenu';
import '../docs.css';

const TOC: [string, string, [string, string][]?][] = [
  ['mulai', 'Mulai cepat'],
  ['cara-kerja', 'Cara kerja', [['alur', 'Alur laporan'], ['status', 'Siklus status'], ['test-live', 'Mode test & live']]],
  ['sdk-react', 'SDK React', [['sos-provider', 'SOSProvider'], ['sos-button', 'SOSButton'], ['use-sos', 'useSOS()']]],
  ['sdk-js', 'SDK JavaScript', [['init', 'init()'], ['trigger', 'trigger()'], ['events', 'Event'], ['offline', 'Offline & retry']]],
  ['sdk-mobile', 'SDK Mobile', [['flutter', 'Flutter'], ['floating', 'Tombol melayang'], ['android', 'Android (Kotlin)'], ['ios', 'iOS (Swift)']]],
  ['pengaduan', 'Laporan pengaduan'],
  ['lokasi', 'Lokasi & privasi'],
  ['lampiran', 'Foto, video & suara'],
  ['whatsapp', 'Penerima SOS & WhatsApp', [['wa-penerima', 'Penerima SOS'], ['wa-kontak', 'Nomor darurat (CRUD di app)'], ['wa-pesan', 'Isi pesan & hasil'], ['wa-server', 'Konfigurasi server']]],
  ['source', 'Source'],
  ['webhook', 'Webhook', [['webhook-event', 'Event & payload'], ['webhook-verify', 'Verifikasi tanda tangan'], ['webhook-retry', 'Retry']]],
  ['api-server', 'REST API server'],
  ['error', 'Kode error & batas'],
  ['checklist', 'Checklist go-live'],
];

function Code({ children, lang }: { children: string; lang?: string }) {
  const [done, setDone] = useState(false);
  return (
    <div className="doc-code">
      {lang && <span className="doc-code-lang">{lang}</span>}
      <button className="doc-code-copy" aria-label="Salin kode" onClick={async () => {
        await navigator.clipboard?.writeText(children).catch(() => {});
        setDone(true);
        setTimeout(() => setDone(false), 1400);
      }}>{done ? <CheckCircle size={14} weight="fill" /> : <Copy size={14} />}{done ? 'Tersalin' : 'Salin'}</button>
      <pre><code>{children}</code></pre>
    </div>
  );
}

function Note({ tone = 'info', children }: { tone?: 'info' | 'warn'; children: ReactNode }) {
  return <div className={`doc-note ${tone}`}>{tone === 'warn' ? <Warning size={18} weight="fill" /> : <Info size={18} weight="fill" />}<div>{children}</div></div>;
}

function Props({ rows }: { rows: [string, string, string, string?][] }) {
  return (
    <div className="doc-table">
      <table>
        <thead><tr><th>Nama</th><th>Tipe</th><th>Keterangan</th></tr></thead>
        <tbody>
          {rows.map(([n, t, d, def]) => (
            <tr key={n}><td><code>{n}</code></td><td><code className="t">{t}</code></td><td>{d}{def && <span className="def"> Default: <code>{def}</code></span>}</td></tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Sorot item daftar isi sesuai bagian yang sedang dibaca. */
function useScrollSpy(ids: string[]) {
  const [active, setActive] = useState(ids[0]);
  useEffect(() => {
    const els = ids.map((i) => document.getElementById(i)).filter(Boolean) as HTMLElement[];
    const on = () => {
      let cur = ids[0];
      for (const e of els) if (e.getBoundingClientRect().top < 120) cur = e.id;
      setActive(cur);
    };
    on();
    window.addEventListener('scroll', on, { passive: true });
    return () => window.removeEventListener('scroll', on);
  }, [ids]);
  return active;
}

const ALL_IDS = TOC.flatMap(([id, , sub]) => [id, ...(sub ?? []).map(([s]) => s)]);

export function DocsPage() {
  const { me } = useAuth();
  const active = useScrollSpy(ALL_IDS);
  const [toc, setToc] = useState(false);
  useEffect(() => { document.title = 'Dokumentasi · SiagaSOS'; }, []);
  const api = API_URL;

  return (
    <div className="docs">
      <header className="docs-top">
        <div className="docs-top-in">
          <Link to="/" className="docs-brand"><BrandMark size={26} /><span>SiagaSOS</span><span className="docs-tag">Docs</span></Link>
          <nav className="docs-top-links" aria-label="Utama">
            <Link to="/">Beranda</Link>
            <a href="#mulai">Mulai cepat</a>
            <a href="#webhook">Webhook</a>
            <a href="#api-server">API</a>
          </nav>
          <div style={{ marginLeft: 'auto', display: 'flex', gap: 8, alignItems: 'center' }}>
            <ThemeMenu />
            <Link to={me ? '/apps' : '/register'} className="btn btn-primary btn-sm" aria-label={me ? 'Kunci API saya' : 'Dapatkan kunci test'}>
              <span className="docs-cta-text">{me ? 'Kunci API saya' : 'Dapatkan kunci test'}</span><span className="docs-cta-short" aria-hidden>{me ? 'Kunci' : 'Daftar'}</span><ArrowRight size={14} />
            </Link>
            <button className="btn btn-ghost btn-icon docs-toc-btn" aria-label="Daftar isi" aria-expanded={toc} onClick={() => setToc(!toc)}>{toc ? <X size={20} /> : <List size={20} />}</button>
          </div>
        </div>
      </header>

      <div className="docs-body">
        <aside className={`docs-toc ${toc ? 'open' : ''}`} aria-label="Daftar isi" onClick={() => setToc(false)}>
          <p className="docs-toc-title">Dokumentasi</p>
          <ul>
            {TOC.map(([id, label, sub]) => (
              <li key={id}>
                <a href={`#${id}`} aria-current={active === id ? 'true' : undefined}>{label}</a>
                {sub && <ul>{sub.map(([s, l]) => <li key={s}><a href={`#${s}`} aria-current={active === s ? 'true' : undefined}>{l}</a></li>)}</ul>}
              </li>
            ))}
          </ul>
        </aside>

        <article className="docs-content">
          <section id="mulai">
            <p className="docs-kicker">Panduan integrasi · SDK 0.1</p>
            <h1>Mulai cepat</h1>
            <p className="docs-lead">Pasang tombol SOS di aplikasi web Anda dalam 5 menit. Laporan langsung masuk ke dashboard tim responder, lengkap dengan lokasi.</p>
            <ol className="docs-steps">
              <li>
                <h3>Daftar & buat app</h3>
                <p><Link to="/register">Daftarkan perusahaan</Link>, verifikasi email, lalu buka <b>App & kunci API → App baru</b>. Isi origin web Anda (mis. <code>https://app.perusahaan.co.id</code>; untuk lokal <code>http://localhost:3000</code>). Anda langsung mendapat kunci <code>pk_test_</code> tanpa menunggu verifikasi dokumen.</p>
              </li>
              <li>
                <h3>Pasang SDK</h3>
                <Code lang="bash">{`npm install @siagasos/react @siagasos/js`}</Code>
              </li>
              <li>
                <h3>Tempel tombolnya</h3>
                <Code lang="tsx">{`import { SOSProvider, SOSButton } from '@siagasos/react';

export function App() {
  return (
    <SOSProvider apiKey="pk_test_..." sourceKey="kantor-pusat-web" user={{ ref: currentUser.id, name: currentUser.name }}>
      <SOSButton category="kriminal" holdToConfirm={3} />
    </SOSProvider>
  );
}`}</Code>
              </li>
              <li>
                <h3>Uji alurnya</h3>
                <p>Tahan tombol 3 detik, lalu buka <Link to="/dashboard">Dashboard laporan</Link>. Laporan bertanda <b>TEST</b> muncul realtime. Ubah statusnya menjadi <i>Diterima</i>, dan tombol di aplikasi Anda akan menampilkan status itu dalam ≤ 5 detik.</p>
              </li>
            </ol>
            <Note>Setelah perusahaan disetujui, ganti <code>pk_test_</code> dengan <code>pk_live_</code>. Kode lain tidak perlu diubah.</Note>
            <Note>Aplikasi mobile? Lihat <a href="#sdk-mobile">SDK Mobile</a> (Flutter, Android, iOS). Daftarkan <b>package name / bundle id</b> di pengaturan app, bukan origin.</Note>
          </section>

          <section id="cara-kerja">
            <h2>Cara kerja</h2>
            <h3 id="alur">Alur laporan</h3>
            <div className="docs-flow" role="img" aria-label="Alur: aplikasi klien dengan SDK mengirim laporan ke API SiagaSOS, yang meneruskan ke dashboard responder secara realtime dan ke server klien lewat webhook. Responder mengubah status, dan SDK menampilkannya ke pelapor.">
              <div className="df-node"><b>Aplikasi Anda</b><span>SDK + publishable key</span></div>
              <div className="df-arrow"><span>POST laporan</span></div>
              <div className="df-node accent"><b>SiagaSOS API</b><span>validasi kunci, origin, rate limit</span></div>
              <div className="df-fork">
                <div className="df-arrow"><span>realtime ≤ 1 dtk</span></div>
                <div className="df-node"><b>Dashboard responder</b><span>bunyi alarm, peta, status</span></div>
                <div className="df-arrow"><span>webhook HMAC</span></div>
                <div className="df-node"><b>Server Anda</b><span>opsional</span></div>
              </div>
            </div>
            <ol className="docs-numbered">
              <li>Pengguna menahan tombol. SDK mengambil lokasi (maks. 8 detik), lalu mengirim laporan dengan <code>Idempotency-Key</code> unik.</li>
              <li>API memeriksa kunci, origin/bundle id, dan batas laporan, lalu menyimpan laporan. Bila sinyal putus, laporan disimpan di perangkat dan dikirim ulang otomatis.</li>
              <li>Dashboard tim Anda menerima laporan seketika (bunyi alarm berulang sampai ada yang menerima). Bila diatur, webhook juga dikirim ke server Anda.</li>
              <li>Responder mengubah status. SDK memeriksa status setiap 4 detik dan menampilkannya ke pelapor. Lokasi live terus dikirim sampai laporan selesai.</li>
            </ol>

            <h3 id="status">Siklus status</h3>
            <div className="docs-states">
              <span className="s open">open<small>Baru</small></span><i>→</i>
              <span className="s ack">acknowledged<small>Diterima</small></span><i>→</i>
              <span className="s prog">in_progress<small>Ditangani</small></span><i>→</i>
              <span className="s done">resolved<small>Selesai</small></span>
            </div>
            <p>Laporan <a href="#pengaduan">pengaduan</a> (<code>kind: "pengaduan"</code>) memakai siklus status yang sama, tetapi tanpa alarm, tanpa email darurat, dan tanpa lokasi live.</p>
            <p>Status akhir lain: <code>false_alarm</code> (ditandai responder) dan <code>cancelled</code> (dibatalkan pelapor, hanya saat masih <code>open</code>). Setelah status akhir, laporan tidak bisa diubah lagi dan lokasi live berhenti.</p>

            <h3 id="test-live">Mode test & live</h3>
            <div className="doc-table">
              <table>
                <thead><tr><th /><th>Test (<code>pk_test_</code>)</th><th>Live (<code>pk_live_</code>)</th></tr></thead>
                <tbody>
                  <tr><td>Tersedia</td><td>Langsung setelah verifikasi email</td><td>Setelah perusahaan disetujui (±2 hari kerja)</td></tr>
                  <tr><td>Batas</td><td>50 laporan per hari per akun</td><td>Rate limit normal</td></tr>
                  <tr><td>Notifikasi responder</td><td>Tidak (hanya dashboard)</td><td>Ya (dashboard + email)</td></tr>
                  <tr><td>Origin <code>*</code></td><td>Boleh</td><td>Tidak boleh</td></tr>
                  <tr><td>Data</td><td colSpan={2}>Terpisah. Kunci test hanya melihat laporan test, begitu juga sebaliknya.</td></tr>
                </tbody>
              </table>
            </div>
          </section>

          <section id="sdk-react">
            <h2>SDK React <code className="pkg">@siagasos/react</code></h2>
            <h3 id="sos-provider">SOSProvider</h3>
            <p>Bungkus bagian aplikasi yang membutuhkan tombol SOS. Menerima semua opsi <a href="#init"><code>init()</code></a>.</p>
            <Code lang="tsx">{`<SOSProvider
  apiKey="pk_live_..."
  sourceKey="gudang-cakung"
  user={{ ref: 'emp-1029', name: 'Budi Santoso', phone: '+62811...' }}
  liveLocation
>
  {children}
</SOSProvider>`}</Code>

            <h3 id="sos-button">SOSButton</h3>
            <p>Tombol siap pakai: tahan N detik dengan cincin progres, tombol batal, label TEST otomatis, teks penerima, dan tautan telepon cadangan.</p>
            <Props rows={[
              ['category', 'string', 'Kategori laporan, mis. kriminal, medis, kebakaran. Daftar kategori diatur di portal.', "'general'"],
              ['message', 'string', 'Pesan tambahan (maks. 2000 karakter).'],
              ['metadata', 'Record<string, unknown>', 'Data bebas yang ikut terkirim ke dashboard & webhook.'],
              ['holdToConfirm', 'number', 'Lama tahan dalam detik untuk mencegah salah tekan.', 'dari pengaturan app (3)'],
              ['label', 'string', 'Teks tombol.', "'SOS'"],
              ['theme', '{ color?, size? }', 'Warna dan ukuran tombol (px).'],
              ['showFallbackCall', 'boolean', 'Tampilkan tautan telepon cadangan (mis. 110) bila pengiriman gagal.', 'true'],
              ['onSent', '(r: ActiveReport) => void', 'Dipanggil saat laporan diterima server.'],
              ['onError', '(e: SiagaSOSError) => void', 'Dipanggil saat terjadi error yang tidak bisa diulang.'],
              ['className / style', '', 'Styling tambahan.'],
            ]} />

            <h3 id="use-sos">useSOS()</h3>
            <p>Untuk tombol dengan desain Anda sendiri.</p>
            <Code lang="tsx">{`const { trigger, cancel, status, activeReport, error, config } = useSOS();

<button onClick={() => trigger({ category: 'medis' })} disabled={status === 'sending'}>
  Minta bantuan
</button>
{activeReport && <p>Status: {activeReport.status} {activeReport.statusMessage}</p>}`}</Code>
            <p><code>status</code>: <code>idle</code> · <code>sending</code> · <code>queued</code> (menunggu sinyal) · <code>open</code> · <code>acknowledged</code> · <code>in_progress</code> · <code>resolved</code> · <code>cancelled</code> · <code>false_alarm</code>.</p>
          </section>

          <section id="sdk-js">
            <h2>SDK JavaScript <code className="pkg">@siagasos/js</code></h2>
            <p>Tanpa dependency, 3,2 KB gzip. Bisa dipakai di framework apa pun, atau lewat tag script:</p>
            <Code lang="html">{`<script src="https://unpkg.com/@siagasos/js/dist/index.global.js"></script>
<script>
  const sos = SiagaSOS.SiagaSOS.init({ apiKey: 'pk_test_...' });
</script>`}</Code>

            <h3 id="init">init(options)</h3>
            <Props rows={[
              ['apiKey', 'string', 'Wajib. Publishable key. Mode test/live dibaca dari prefix.'],
              ['sourceKey', 'string', 'Label asal laporan, mis. "kantor-jakarta-web". Lihat Source.'],
              ['user', '{ ref?, name?, phone? }', 'Identitas pelapor. ref = ID pengguna di sistem Anda (dipakai juga untuk rate limit per pengguna).'],
              ['liveLocation', 'boolean', 'Kirim lokasi berkala selama laporan aktif.', 'true'],
              ['pollIntervalMs', 'number', 'Interval cek status.', '4000'],
              ['locationTimeoutMs', 'number', 'Batas waktu mengambil GPS saat trigger.', '8000'],
              ['baseUrl', 'string', 'Override URL API (self-hosted / staging).'],
            ]} />

            <h3 id="trigger">Metode</h3>
            <Code lang="ts">{`import { SiagaSOS } from '@siagasos/js';

const sos = SiagaSOS.init({ apiKey: 'pk_test_...', sourceKey: 'armada-web' });

const report = await sos.trigger({ category: 'kecelakaan', message: 'Ditabrak motor', metadata: { plate: 'B 1234 XY' } });
await sos.cancel(report.localId, 'Salah tekan');   // hanya selama status open
const cfg = await sos.getConfig();                    // kategori, teks tombol, durasi tahan, dll.
sos.destroy();                                        // hentikan polling & GPS (mis. saat logout)`}</Code>
            <Props rows={[
              ['trigger(input)', 'Promise<ActiveReport>', 'Kirim laporan. Tetap resolve walau offline (status queued).'],
              ['cancel(id, reason?)', 'Promise<ActiveReport | null>', 'Batalkan laporan. Error cannot_cancel bila sudah diterima responder.'],
              ['getConfig()', 'Promise<SdkConfig>', 'Konfigurasi tombol dari portal (di-cache).'],
              ['getReport(id)', 'Promise<ReportPublic>', 'Ambil status terbaru satu laporan.'],
              ['flush()', 'Promise<void>', 'Kirim ulang antrian offline sekarang (otomatis saat online).'],
              ['on(event, fn)', '() => void', 'Pasang listener; kembalian dipanggil untuk melepas.'],
              ['destroy()', 'void', 'Bersihkan timer, watcher GPS, dan listener.'],
            ]} />

            <h3 id="events">Event</h3>
            <Code lang="ts">{`sos.on('queued', (r) => toast('Tidak ada sinyal. Laporan akan dikirim otomatis.'));
sos.on('sent',   (r) => toast('Laporan terkirim ke tim keamanan'));
sos.on('status', (r) => render(r.status, r.statusMessage));
sos.on('error',  (e) => console.error(e.code, e.message));`}</Code>

            <h3 id="offline">Offline & retry</h3>
            <p>Laporan disimpan di IndexedDB (fallback localStorage, lalu memori), lalu dikirim ulang dengan backoff eksponensial dan saat perangkat kembali online. Setiap laporan membawa <code>Idempotency-Key</code> yang sama di setiap percobaan, sehingga tidak pernah tercatat dua kali.</p>
          </section>

          <section id="sdk-mobile">
            <h2>SDK Mobile</h2>
            <p>Perilaku semua SDK sama dengan SDK web: antrian offline yang bertahan saat app ditutup, <code>Idempotency-Key</code> per laporan, polling status, lokasi live, dan lampiran langsung ke storage. Bedanya, aplikasi mobile dikenali lewat header <code>X-SOS-Bundle</code>, jadi daftarkan <b>package name</b> (Android) dan <b>bundle identifier</b> (iOS) di <b>App → Pengaturan → Bundle id</b>.</p>
            <div className="doc-table">
              <table>
                <thead><tr><th /><th>Flutter</th><th>Android</th><th>iOS</th></tr></thead>
                <tbody>
                  <tr><td>Paket</td><td><code>siagasos</code></td><td><code>id.siagasos:siagasos-android</code></td><td>Swift Package <code>SiagaSOS</code></td></tr>
                  <tr><td>Minimum</td><td>Flutter 3.22</td><td>minSdk 21</td><td>iOS 15</td></tr>
                  <tr><td>Tombol tahan N detik</td><td><code>SOSButton</code></td><td><code>SOSButtonView</code></td><td>SwiftUI <code>SOSButton</code></td></tr>
                  <tr><td>Tombol melayang + pengaduan</td><td>✔ <code>SOSFloatingButton</code></td><td>segera</td><td>segera</td></tr>
                  <tr><td>Antrian offline</td><td>SharedPreferences</td><td>SharedPreferences</td><td>UserDefaults</td></tr>
                </tbody>
              </table>
            </div>

            <h3 id="flutter">Flutter</h3>
            <Code lang="yaml · pubspec.yaml">{`dependencies:
  siagasos:
    git: { url: https://github.com/AjieDarmawan/sos_siaga.git, path: packages/sdk-flutter }`}</Code>
            <Code lang="dart">{`import 'package:siagasos/siagasos.dart';

final sos = SiagaSOS(
  apiKey: 'pk_test_...',                 // pk_live_ setelah perusahaan disetujui
  bundleId: 'com.perusahaan.app',        // harus terdaftar di app
  user: SosUser(ref: user.id, name: user.name, phone: user.phone),
  locationProvider: () async {           // mis. paket geolocator
    final p = await Geolocator.getCurrentPosition();
    return SosLocation(lat: p.latitude, lng: p.longitude, accuracyM: p.accuracy);
  },
);

// Tombol besar di satu halaman
SOSButton(client: sos, category: 'kriminal');

// Atau UI sendiri
final r = await sos.trigger(category: 'medis', message: 'Rekan pingsan');
sos.status.listen((r) => print('\${r.status} \${r.statusMessage}'));
await sos.attach(r.localId, bytes, contentType: 'image/jpeg');`}</Code>

            <h3 id="floating">Tombol melayang (Flutter)</h3>
            <p>Pasang sekali di root app: tombol SOS kecil tampil di semua halaman, bisa digeser, menempel ke tepi, dan posisinya diingat. Area di luar tombol tidak menangkap sentuhan.</p>
            <Code lang="dart">{`MaterialApp(
  navigatorKey: navigatorKey,                       // kamera TKP dibuka dari atas Navigator
  builder: (context, child) => SOSFloatingButton(
    client: sos,
    category: 'kriminal',
    holdSeconds: 0,                                 // sekali ketuk (gaya EWS); null = tahan N detik dari portal
    sosLabel: 'EWS Alert',
    siren: mySiren,                                 // opsional: SosSiren dari app (audioplayers)
    onCall: (phone) => launchUrl(Uri(scheme: 'tel', path: phone)),
    onOpenUrl: (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    onCapture: (context, kind) async {              // video TKP / foto pengaduan dari kamera app Anda
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
      return x == null ? null : CapturedMedia(bytes: await x.readAsBytes(), contentType: 'image/jpeg');
    },
    child: child!,
  ),
  home: const HomePage(),
)`}</Code>
            <p>Ketuk tombol → 4 aksi bertumpuk, lebarnya mengikuti label terpanjang:</p>
            <Props rows={[
              ['Kirim SOS / EWS Alert', 'ketuk atau tahan', 'Mengirim laporan darurat. Setelah terkirim: sirene (bila ada), lalu ajakan "Rekam kondisi TKP?" → video + catatan ke petugas.'],
              ['Telepon 110', 'onCall', 'Nomor dari "Nomor cadangan" di Pengaturan app.', '110'],
              ['Telepon 112', 'onCall', 'Nomor kedua, atur dengan secondaryPhone.', '112'],
              ['Laporan', 'kartu sub-menu', 'Pengaduan (form non-darurat), Riwayat laporan, dan Nomor darurat.'],
            ]} />
            <p><b>Riwayat laporan</b> menampilkan SOS & pengaduan yang pernah dikirim dari perangkat ini. Ketuk satu laporan untuk melihat <b>detail</b>: status & pesan petugas, waktu dikirim/diterima/selesai, uraian, lokasi (tombol <i>Buka peta</i>), lampiran foto/video, dan riwayat status lengkap dengan catatan petugas. SOS yang belum direspons bisa dibatalkan dari sini. Data diambil dari <code>GET /v1/sdk/reports/:id/detail</code>; nomor HP pelapor dan penerima tidak pernah dikirim ke perangkat.</p>
            <Props rows={[
              ['client', 'SiagaSOS', 'Instance klien.'],
              ['onCall', '(phone) → void', 'Menelepon nomor darurat. Kosong = tombol telepon disembunyikan.'],
              ['onCapture', '(context, kind) → CapturedMedia?', 'Kamera/mikrofon app Anda: video TKP setelah SOS, foto pengaduan. Kosong = tanpa lampiran.'],
              ['onOpenUrl', '(url) → void', 'Membuka peta lokasi dan lampiran dari detail riwayat (mis. url_launcher). Kosong = tombol Buka peta disembunyikan.'],
              ['holdSeconds', 'int?', '0 = sekali ketuk; null = ikut "tahan N detik" di Pengaturan app.'],
              ['sosLabel / sosColors / callLabel', 'String / List<Color> / String', 'Teks & warna tombol kirim SOS, awalan tombol telepon.', "'Kirim SOS' / merah / 'Telepon'"],
              ['siren', 'SosSiren?', 'Sirene di HP pelapor; tombol bulat berubah jadi SENYAP selama berbunyi.'],
              ['tkpPrompt / tkpSeconds', 'bool / int', 'Ajakan rekam TKP setelah SOS terkirim dan batas durasinya.', 'true / 5'],
              ['complaint / history / emergencyContacts', 'bool', 'Tampilkan Pengaduan / Riwayat laporan / Nomor darurat di sub-menu Laporan.', 'true'],
              ['onSent / onComplaintSent', '(ActiveReport) → void', 'Dipanggil setelah SOS / pengaduan diterima server.'],
              ['secondaryPhone', 'String?', 'Nomor kedua di menu.', "'112'"],
              ['visible', 'bool', 'false = sembunyikan (mis. di halaman login) tanpa melepas widget.', 'true'],
            ]} />
            <Note>SDK tidak membawa plugin kamera atau telepon, jadi ukuran app dan izin tetap di tangan Anda. Minta izin lokasi, kamera, dan mikrofon dengan penjelasan bahwa data dibagikan ke tim responder (UU PDP).</Note>

            <h3 id="android">Android (Kotlin)</h3>
            <p>Tanpa dependency runtime, AAR ±73 KB. Lokasi lewat <code>LocationManager</code> (tanpa Google Play Services).</p>
            <Code lang="kotlin">{`val sos = SiagaSOS.create(context, apiKey = "pk_test_...",
    user = SosUser(ref = user.id, name = user.name, phone = user.phone))

// XML: <id.siagasos.SOSButtonView android:layout_width="200dp" android:layout_height="200dp"/>
binding.sosButton.bind(sos, category = "kriminal") { it.onFailure { e -> showError(e.message) } }

sos.trigger("medis", "Rekan pingsan") { it.onSuccess { r -> current = r } }
sos.attach(current.localId, bytes, "image/jpeg") { }`}</Code>

            <h3 id="ios">iOS (Swift)</h3>
            <Code lang="swift">{`import SiagaSOS

let sos = try SiagaSOS(apiKey: "pk_test_...", user: SosUser(ref: user.id, name: user.name))

// SwiftUI
SOSButton(client: sos, category: "kriminal")

// Atau UI sendiri
let r = try await sos.trigger(category: "medis", message: "Rekan pingsan")
try await sos.attach(r.localId, data: jpeg, contentType: "image/jpeg")`}</Code>
            <p>Tambahkan <code>NSLocationWhenInUseUsageDescription</code> (dan <code>NSCameraUsageDescription</code>, <code>NSMicrophoneUsageDescription</code> bila memakai lampiran) di <code>Info.plist</code>.</p>
          </section>

          <section id="pengaduan">
            <h2>Laporan pengaduan</h2>
            <p>Selain SOS darurat, pengguna bisa mengirim <b>pengaduan</b> non-darurat (parkir liar, kebisingan, pungli, dan sebagainya) dari menu <b>Laporan pengaduan</b> di tombol melayang. Pengaduan masuk ke dashboard yang sama dengan label <b>Pengaduan</b>.</p>
            <div className="doc-table">
              <table>
                <thead><tr><th /><th>SOS</th><th>Pengaduan</th></tr></thead>
                <tbody>
                  <tr><td>Cara kirim</td><td>Tahan tombol N detik</td><td>Form: jenis + uraian (wajib, min. 5 karakter) + foto opsional</td></tr>
                  <tr><td>Bunyi alarm & notifikasi browser</td><td>Ya</td><td>Tidak</td></tr>
                  <tr><td>Email ke responder (live)</td><td>Ya</td><td>Tidak</td></tr>
                  <tr><td>WhatsApp ke Penerima SOS & nomor darurat (live)</td><td>Ya</td><td>Tidak</td></tr>
                  <tr><td>Lokasi</td><td>Saat dikirim + live</td><td>Saat dikirim saja</td></tr>
                  <tr><td>Batas per pengguna</td><td>3 laporan / 10 menit</td><td>5 pengaduan / jam (terpisah dari SOS)</td></tr>
                </tbody>
              </table>
            </div>
            <Code lang="dart">{`// Tanpa widget (antrian offline sama dengan SOS)
await sos.complain(category: 'parkir_liar', message: 'Parkir liar menutup gang setiap malam');`}</Code>
            <Code lang="http · API">{`POST /v1/sdk/reports
Idempotency-Key: 6f2c...
{ "kind": "pengaduan", "category": "kebisingan", "message": "Hajatan sampai jam 2 pagi",
  "location": { "lat": -6.59, "lng": 106.79 }, "reporter": { "ref": "user_123" } }`}</Code>
            <p>Jenis pengaduan bawaan: <code>ketertiban</code>, <code>kebisingan</code>, <code>parkir_liar</code>, <code>pungli</code>, <code>kehilangan</code>, <code>patroli</code>, <code>lainnya</code>. Ubah lewat <code>sdk_config.complaint_categories</code> di pengaturan app; SDK membacanya dari <code>GET /v1/sdk/config</code>.</p>
          </section>

          <section id="lokasi">
            <h2>Lokasi & privasi</h2>
            <p>Browser meminta izin lokasi saat tombol pertama kali ditekan. Bila ditolak atau GPS lambat (&gt; 8 detik), laporan tetap terkirim tanpa lokasi. Selama laporan aktif, lokasi dikirim berkala (default 15 detik, diatur di portal) dan berhenti otomatis saat laporan mencapai status akhir.</p>
            <Note tone="warn">Sesuai UU PDP, beri tahu pengguna sebelum mereka memakai tombol bahwa lokasi akan dibagikan ke tim responder Anda, dan cantumkan di kebijakan privasi aplikasi. Setiap kali petugas membuka detail laporan, aksesnya tercatat di audit log.</Note>
          </section>

          <section id="lampiran">
            <h2>Foto, video & suara</h2>
            <p>Setelah SOS terkirim, pelapor bisa menambahkan bukti: foto, video pendek, atau rekaman suara. File diunggah <b>langsung dari perangkat ke object storage</b> lewat URL bertanda tangan, jadi upload besar tidak membebani server Anda maupun jalur SOS. Lampiran muncul realtime di dashboard responder (galeri foto, pemutar video & suara).</p>
            <Code lang="tsx">{`import { SOSProvider, SOSButton, SOSAttach } from '@siagasos/react';

<SOSProvider apiKey="pk_test_...">
  <SOSButton category="kriminal" />
  <SOSAttach allow={['image', 'video', 'audio']} maxAudioSeconds={60} />  {/* tampil setelah SOS terkirim */}
</SOSProvider>`}</Code>
            <p><code>SOSAttach</code> menampilkan tombol <b>Foto</b> dan <b>Video</b> (membuka kamera belakang di HP) dan <b>Suara</b> (rekam langsung dari mikrofon), lengkap dengan progres upload. Untuk UI sendiri, pakai <code>attach()</code>:</p>
            <Code lang="ts">{`const report = await sos.trigger({ category: 'kriminal' });
await sos.attach(report.localId, file, {           // File/Blob dari <input type="file"> atau MediaRecorder
  durationS: 12,                                     // opsional, untuk video/suara
  onProgress: (r) => setProgress(Math.round(r * 100)),
});`}</Code>
            <Props rows={[
              ['Foto', 'JPG, PNG, WEBP, HEIC', 'Maks. 10 MB per file.'],
              ['Video', 'MP4, WEBM, MOV', 'Maks. 60 MB per file. Rekam pendek (≤ 30 dtk) atau kompres di perangkat.'],
              ['Suara', 'WEBM, OGG, MP3, M4A, AAC, WAV', 'Maks. 15 MB per file.'],
              ['Jumlah', '10 per laporan', 'Bisa ditambah selama laporan aktif dan sampai 30 menit setelah selesai.'],
            ]} />
            <p>Alur di balik <code>attach()</code> (untuk SDK native / backend):</p>
            <ol className="docs-numbered">
              <li><code>POST /v1/sdk/reports/:id/media</code> dengan <code>{`{ content_type, size_bytes, duration_s? }`}</code> → balasan berisi <code>upload.url</code> dan <code>upload.headers</code>.</li>
              <li><code>PUT</code> file ke <code>upload.url</code> dengan header persis seperti <code>upload.headers</code> (URL berlaku 15 menit; ukuran harus sama dengan <code>size_bytes</code>).</li>
              <li><code>POST /v1/sdk/reports/:id/media/:mediaId/complete</code> → server memeriksa file, lalu lampiran tampil di dashboard.</li>
            </ol>
            <Note>Penyimpanan bersifat privat. Dashboard dan <code>GET /v1/reports/:id</code> memberikan URL baca bertanda tangan yang berlaku 15 menit; jangan simpan URL tersebut, minta ulang saat dibutuhkan. Responder juga bisa melampirkan dokumentasi dari dashboard.</Note>
          </section>

          <section id="whatsapp">
            <h2>Penerima SOS & WhatsApp</h2>
            <p>Setiap <b>SOS live</b> dikabarkan lewat WhatsApp ke dua kelompok nomor: <b>Penerima SOS</b> yang Anda atur di portal (pos satpam, pengelola gedung, pemilik toko) dan <b>nomor darurat pribadi</b> yang diatur pelapor sendiri di aplikasi (keluarga, rekan). Pengiriman berjalan di latar belakang setelah laporan tersimpan, jadi WhatsApp yang lambat atau gagal tidak pernah menunda atau menggagalkan SOS.</p>

            <h3 id="wa-penerima">Penerima SOS</h3>
            <p>Buka <b>App & kunci → pilih app → tab Penerima SOS</b>, lalu tambahkan nama dan nomor WhatsApp (format <code>08xx</code>, <code>+62</code>, atau <code>62</code>; disimpan sebagai <code>62xx</code>).</p>
            <ul>
              <li><b>Cakupan</b>: <i>Semua source</i> menerima SOS dari seluruh app; pilih satu source (mis. satu outlet atau gedung) agar nomor itu hanya menerima SOS dari lokasi tersebut.</li>
              <li>Nonaktifkan sementara tanpa menghapus, mis. saat pergantian shift satpam.</li>
              <li>Hanya peran <b>Owner</b> dan <b>Admin</b> yang bisa mengubah; setiap penambahan & penghapusan tercatat di audit log.</li>
            </ul>
            <Code lang="http · portal API">{`GET    /portal/apps/:id/recipients
POST   /portal/apps/:id/recipients      { "name": "Pos satpam", "phone": "0812xxxxxxx", "source_id": null }
PATCH  /portal/apps/:id/recipients/:rid { "active": false }
DELETE /portal/apps/:id/recipients/:rid`}</Code>

            <h3 id="wa-kontak">Nomor darurat pelapor</h3>
            <p>Selain penerima yang diatur pengelola, setiap pengguna punya daftar <b>Nomor Darurat</b> pribadi di aplikasi (seperti menu Nomor Darurat di tata-warga dan POSTIP): keluarga, pemilik toko, atau satpam yang harus ikut dikabari saat <i>dia</i> menekan SOS.</p>
            <Props rows={[
              ['Nama kontak', 'wajib', 'Mis. Pak Joko.'],
              ['Jabatan / hubungan', 'opsional', 'Mis. Satpam, Pemilik toko, Keluarga. Ikut tertulis di nama penerima WhatsApp: "Pak Joko (Satpam)".'],
              ['Nomor WhatsApp', 'wajib', '08xx / +62 / 62, disimpan sebagai 62xx. Tidak boleh ganda.'],
              ['Aktif', 'default ya', 'Hanya kontak aktif yang menerima SOS. Maks. 5 aktif, maks. 10 tersimpan.'],
            ]} />
            <p>Data disimpan SDK di perangkat, terpisah per pengguna (<code>user.ref</code>), lalu kontak aktif ikut terkirim otomatis bersama setiap SOS. Ada dua tempat pengguna mengelolanya:</p>
            <ul>
              <li><b>Halaman Nomor Darurat di aplikasi Anda</b> (disarankan): daftar dengan filter Semua / Aktif / Nonaktif, tambah, ubah, aktif/nonaktif, dan hapus dengan konfirmasi. Contoh: POSTIP <b>Menu → Pengaturan → Nomor Darurat</b>.</li>
              <li><b>Tombol melayang → Laporan → Nomor darurat</b>: akses cepat untuk menambah atau menghapus, tanpa keluar dari layar yang sedang dibuka.</li>
            </ul>
            <p>Membangun halaman CRUD sendiri cukup dengan dua method; aturan (nomor valid, tidak ganda, maks. 5 aktif) diperiksa SDK dan dilempar sebagai <code>ArgumentError</code> dengan pesan berbahasa Indonesia yang siap ditampilkan:</p>
            <Code lang="dart">{`// Baca (aktif & nonaktif)
final contacts = await sos.emergencyContacts();

// Tambah / ubah / hapus / aktif-nonaktif = simpan ulang seluruh daftar
try {
  await sos.setEmergencyContacts([
    ...contacts,
    const EmergencyContact(name: 'Pak Joko', role: 'Satpam', phone: '0812 3456 7890'),
  ]);
  // nonaktifkan: contacts[i].copyWith(active: false)
  // hapus:       contacts.where((c) => c.phone != phone).toList()
} on ArgumentError catch (e) {
  showSnackBar(e.message);   // mis. "Maksimal 5 nomor darurat aktif"
}`}</Code>
            <p>SDK lain / backend mengirimnya di body laporan (hanya untuk SOS; pengaduan mengabaikannya):</p>
            <Code lang="http · API">{`POST /v1/sdk/reports
{ "category": "kriminal", "reporter": { "ref": "user_123", "name": "Budi" },
  "emergency_contacts": [ { "name": "Istri", "phone": "081333334444" } ] }`}</Code>

            <h3 id="wa-pesan">Isi pesan & hasil</h3>
            <p>Pesan memakai template WhatsApp resmi (sudah disetujui Meta) dengan tiga isian: <b>nama pelapor</b>, <b>lokasi</b> (nama app · source), dan <b>link Google Maps</b> titik SOS. Nomor yang sama di beberapa daftar hanya dikirimi sekali.</p>
            <Props rows={[
              ['Hasil per nomor', 'Timeline laporan', 'Terkirim, gagal (beserta alasannya), atau dilewati; terlihat di detail laporan di dashboard.'],
              ['Mode test', 'Tidak dikirim', 'Kunci pk_test_ hanya mencatat siapa yang akan dikabari.'],
              ['Nomor uji', '0800…', 'Nomor 0800 (bebas pulsa) dicatat tetapi tidak pernah dikirimi WhatsApp: pakai untuk QA.'],
              ['Batas', '5 WA / nomor / jam', 'Mencegah spam bila kunci publishable disalahgunakan. Nomor darurat pribadi maks. 5 per laporan.'],
            ]} />

            <h3 id="wa-server">Konfigurasi server</h3>
            <p>Provider dan nama variabel lingkungan sama dengan tata-warga, sehingga akun WhatsApp yang sama dapat dipakai. Tanpa konfigurasi, server berjalan dalam mode <code>stub</code>: tidak ada WhatsApp keluar, timeline mencatat "provider WA belum diatur".</p>
            <Code lang="env · MetaDev (bot.mkasir.id)">{`PANIC_BUTTON_USE_METADEV=true        # atau WA_PROVIDER=metadev
METADEV_BASE_URL=https://api-bot.mkasir.id
METADEV_API_KEY=mk_live_...
METADEV_ACCOUNT_ID=...
METADEV_EWSBUTTON_TEMPLATE_NAME=ewsbutton
METADEV_EWSBUTTON_LANGUAGE=id`}</Code>
            <Code lang="env · Qontak (Mekari)">{`WA_PROVIDER=qontak
PANIC_QONTAK_HMAC_USERNAME=...
PANIC_QONTAK_HMAC_SECRET=...
PANIC_QONTAK_TEMPLATE_ID=...
PANIC_QONTAK_CHANNEL_INTEGRATION_ID=...`}</Code>
            <Note tone="warn">Template harus berstatus <b>APPROVED</b> di provider dengan tiga parameter body berurutan: <code>{'{{1}}'}</code> nama, <code>{'{{2}}'}</code> lokasi, <code>{'{{3}}'}</code> link maps. Template yang belum disetujui ditolak Meta dan tercatat "gagal" di timeline.</Note>
          </section>

          <section id="source">
            <h2>Source</h2>
            <p>Source membedakan asal laporan dalam satu app, misalnya per gedung, cabang, atau kanal: <code>gedung-a-web</code>, <code>armada-android</code>. Dashboard bisa difilter per source.</p>
            <ul>
              <li>Format: huruf kecil, angka, <code>.</code> <code>-</code> <code>_</code>, maks. 64 karakter.</li>
              <li>Secara default source baru dibuat otomatis saat SDK pertama kali mengirimnya. Matikan di <b>Pengaturan app</b> bila ingin hanya source terdaftar yang diterima (selain itu error <code>unknown_source</code>).</li>
            </ul>
          </section>

          <section id="webhook">
            <h2>Webhook</h2>
            <p>Isi <b>Webhook URL</b> (wajib https) di pengaturan app. SiagaSOS mengirim <code>POST</code> JSON setiap ada laporan baru atau perubahan status.</p>
            <h3 id="webhook-event">Event & payload</h3>
            <Props rows={[
              ['report.created', 'event', 'Laporan baru masuk.'],
              ['report.status_changed', 'event', 'Responder (atau server Anda) mengubah status.'],
              ['report.cancelled', 'event', 'Pelapor membatalkan laporan.'],
            ]} />
            <Code lang="json">{`{
  "id": "evt_3f9a0c...",
  "type": "report.created",
  "livemode": true,
  "created": "2026-11-21T08:15:02.120Z",
  "data": {
    "report": {
      "id": "6f1c...", "kind": "sos", "app_id": "c716...", "mode": "live",
      "status": "open", "status_message": null,
      "category": "kriminal", "message": "Ada orang mencurigakan",
      "source_key": "gudang-cakung",
      "location": { "lat": -6.1867, "lng": 106.9411, "accuracy_m": 18 },
      "reporter": { "ref": "emp-1029", "name": "Budi Santoso", "phone": "+62811..." },
      "device": { "platform": "web", "sdk_version": "0.1.0" },
      "metadata": null,
      "created_at": "2026-11-21T08:15:01.882Z", "acknowledged_at": null, "resolved_at": null
    }
  }
}`}</Code>
            <p><code>kind</code> bernilai <code>"sos"</code> atau <code>"pengaduan"</code>; event untuk keduanya sama.</p>
            <p>Gunakan <code>id</code> event untuk deduplikasi: event yang sama bisa terkirim lebih dari sekali saat retry.</p>

            <h3 id="webhook-verify">Verifikasi tanda tangan</h3>
            <p>Header <code>X-SOS-Signature: t=&lt;unix&gt;,v1=&lt;hex&gt;</code> dengan <code>v1 = HMAC_SHA256(webhook_secret, "&lt;t&gt;.&lt;raw body&gt;")</code>. Ambil webhook secret di <b>Pengaturan app</b>. Tolak permintaan yang <code>t</code>-nya lebih dari 5 menit untuk mencegah replay.</p>
            <Code lang="ts · Node / Express">{`import crypto from 'node:crypto';

app.post('/siagasos', express.raw({ type: 'application/json' }), (req, res) => {
  const sig = Object.fromEntries(req.get('X-SOS-Signature')!.split(',').map((p) => p.split('=')));
  const expected = crypto.createHmac('sha256', process.env.SOS_WEBHOOK_SECRET!)
    .update(\`\${sig.t}.\${req.body}\`).digest('hex');
  const fresh = Math.abs(Date.now() / 1000 - Number(sig.t)) < 300;
  if (!fresh || !crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(sig.v1))) return res.status(401).end();

  const event = JSON.parse(req.body.toString());
  // ... proses event.type
  res.status(200).end();   // balas 2xx secepatnya; proses berat di background
});`}</Code>
            <Code lang="php · Laravel / PHP">{`$raw = file_get_contents('php://input');
parse_str(str_replace(',', '&', $_SERVER['HTTP_X_SOS_SIGNATURE']), $sig);
$expected = hash_hmac('sha256', $sig['t'] . '.' . $raw, env('SOS_WEBHOOK_SECRET'));
if (abs(time() - (int) $sig['t']) > 300 || !hash_equals($expected, $sig['v1'])) {
    http_response_code(401); exit;
}
$event = json_decode($raw, true);`}</Code>
            <h3 id="webhook-retry">Retry</h3>
            <p>Respons selain 2xx (atau timeout 10 detik) diulang dengan jeda eksponensial: 30 detik, lalu terus berlipat hingga maks. 6 jam per jeda, selama 24 jam. Semua percobaan terlihat di <b>App → Log webhook</b>. Uji endpoint Anda dengan <code>POST /v1/webhooks/test</code>.</p>
          </section>

          <section id="api-server">
            <h2>REST API server</h2>
            <p>Untuk backend Anda, memakai <b>secret key</b> (<code>sk_live_</code> / <code>sk_test_</code>). Jangan pernah menaruh secret key di aplikasi klien. Base URL: <code>{api}</code></p>
            <Props rows={[
              ['GET /v1/reports', 'list', 'Daftar laporan. Filter: kind (sos | pengaduan), status, category, source_key, from, to, limit (maks. 500), cursor.'],
              ['GET /v1/reports/:id', 'detail', 'Detail satu laporan beserta timeline.'],
              ['PATCH /v1/reports/:id', 'update', 'Ubah status dan/atau tambah catatan: { "status": "acknowledged", "note": "..." }'],
              ['POST /v1/webhooks/test', 'test', 'Kirim event uji ke webhook URL app.'],
            ]} />
            <Code lang="bash">{`curl ${api}/v1/reports?status=open,acknowledged \\
  -H "Authorization: Bearer sk_test_..."

curl -X PATCH ${api}/v1/reports/6f1c... \\
  -H "Authorization: Bearer sk_test_..." -H "Content-Type: application/json" \\
  -d '{"status":"acknowledged","note":"Satpam pos 2 menuju lokasi"}'`}</Code>
            <p>Paginasi memakai <code>next_cursor</code> dari respons sebelumnya. Kunci test hanya melihat laporan test.</p>
          </section>

          <section id="error">
            <h2>Kode error & batas</h2>
            <p>Semua error berbentuk <code>{`{ "error": { "code": "...", "message": "...", "details": ... } }`}</code>.</p>
            <Props rows={[
              ['401 invalid_api_key', '', 'Kunci salah, dicabut, atau kedaluwarsa (setelah masa tenggang rotasi).'],
              ['401 wrong_key_type', '', 'Memakai secret key di SDK atau publishable key di API server.'],
              ['403 origin_not_allowed', '', 'Origin web tidak terdaftar di app. Tambahkan di Pengaturan app.'],
              ['403 account_not_approved', '', 'pk_live_ dipakai sebelum perusahaan disetujui.'],
              ['400 idempotency_key_required', '', 'Header Idempotency-Key wajib saat membuat laporan (SDK mengisinya otomatis).'],
              ['409 cannot_cancel', '', 'Laporan sudah diterima responder; tidak bisa dibatalkan.'],
              ['422 unknown_source', '', 'sourceKey belum terdaftar dan pembuatan otomatis dimatikan.'],
              ['413 media_too_large', '', 'File melebihi batas ukuran jenisnya.'],
              ['415 unsupported_media_type', '', 'Tipe file lampiran tidak didukung.'],
              ['409 upload_missing', '', 'complete dipanggil sebelum file selesai diunggah ke storage.'],
              ['409 report_closed', '', 'Laporan sudah ditutup lebih dari 30 menit; lampiran tidak diterima.'],
              ['422 validation_failed', '', 'Isi permintaan tidak valid, mis. pengaduan tanpa uraian (min. 5 karakter).'],
              ['429 rate_limited', '', '120 permintaan/menit per kunci, 60/menit per IP, 3 SOS/10 menit dan 5 pengaduan/jam per pengguna (user.ref).'],
              ['429 test_quota_exceeded', '', 'Melewati 50 laporan test per hari.'],
            ]} />
          </section>

          <section id="checklist">
            <h2>Checklist go-live</h2>
            <ul className="docs-check">
              <li><CheckCircle size={18} weight="fill" />Perusahaan berstatus <b>Disetujui</b> dan kunci <code>pk_live_</code> sudah dibuat.</li>
              <li><CheckCircle size={18} weight="fill" />Origin produksi (https) atau bundle id terdaftar; hapus <code>*</code> dan localhost.</li>
              <li><CheckCircle size={18} weight="fill" />Responder sudah diundang dan bisa login ke dashboard, bunyi alert diaktifkan.</li>
              <li><CheckCircle size={18} weight="fill" />Kategori SOS & pengaduan, teks penerima, dan nomor cadangan diatur di Pengaturan app.</li>
              <li><CheckCircle size={18} weight="fill" />Aplikasi mobile: package name / bundle id produksi terdaftar, izin lokasi/kamera/mikrofon dijelaskan ke pengguna.</li>
              <li><CheckCircle size={18} weight="fill" />Penerima SOS (WhatsApp) diisi di tab <b>Penerima SOS</b>, dan satu SOS live uji menunjukkan "terkirim" di timeline.</li>
              <li><CheckCircle size={18} weight="fill" />Webhook (bila dipakai) lolos verifikasi tanda tangan dan membalas 2xx.</li>
              <li><CheckCircle size={18} weight="fill" />Pengguna sudah diberi tahu tentang pembagian lokasi (UU PDP).</li>
              <li><CheckCircle size={18} weight="fill" />Uji satu laporan live end-to-end bersama tim responder.</li>
            </ul>
            <div className="docs-cta">
              <div><h3>Siap mencoba?</h3><p>Kunci test aktif segera setelah verifikasi email.</p></div>
              <Link to={me ? '/apps' : '/register'} className="btn btn-primary">{me ? 'Buka App & kunci' : 'Daftar gratis'}<ArrowRight size={16} /></Link>
            </div>
          </section>
        </article>
      </div>
    </div>
  );
}
