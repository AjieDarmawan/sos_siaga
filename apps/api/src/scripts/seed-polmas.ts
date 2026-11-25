import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { pool, withPlatform, withTenant, type Db } from '../db.js';
import { hashPassword } from '../lib/auth.js';
import { deleteReports, removeObjects } from '../lib/maintenance.js';
import { mediaEnabled, presignPut } from '../lib/objectStorage.js';
import { syncContactRoles } from '../lib/polmas.js';

/**
 * Data demo Polmas Keamanan (fase 1): pnpm seed:pk   (butuh akun demo dari pnpm seed:demo)
 *
 * - 5 app sumber "(Demo)" di akun demo, masing-masing apps.polmas_source = warga/kantor/umkm/sekolah/komunitas
 * - 5 akun Polmas Keamanan (password sama: demo1234), nomor uji 0800 (tidak pernah dikirimi WA):
 *     0800 111 0001 Budi Santoso      warga
 *     0800 111 0002 Aiptu Rahmat H.   bhabinkamtibmas Bogor Tengah (+ warga: contoh multi-peran)
 *     0800 111 0003 Dewi Anggraini    kantor      0800 111 0004 Hendra Wijaya  umkm
 *     0800 111 0005 Sri Wahyuni       sekolah
 * - ±150 SOS & laporan fiktif 35 hari terakhir di Kec. Bogor Tengah (Kota Bogor) + tanggapan, berita, video/foto demo.
 * Dijalankan ulang: laporan demo lama dihapus lalu dibuat ulang; akun & app dipakai ulang.
 */

const KEC = '32.71.03'; // Bogor Tengah, Kota Bogor
const CENTER = { lat: -6.5971, lng: 106.7973 };
const PASSWORD = 'demo1234';

const SOURCES = [
  { source: 'warga', app: 'Polmas Warga (Demo)', place: 'RW 05 Paledang', alamat: 'Kel. Paledang, Kec. Bogor Tengah, Kota Bogor' },
  { source: 'kantor', app: 'Polmas Kantor (Demo)', place: 'Gedung Graha Pajajaran', alamat: 'Jl. Pajajaran, Kec. Bogor Tengah, Kota Bogor' },
  { source: 'umkm', app: 'Polmas UMKM (Demo)', place: 'Toko Roti Sinar Jaya', alamat: 'Jl. Suryakencana, Kec. Bogor Tengah, Kota Bogor' },
  { source: 'sekolah', app: 'Polmas Sekolah (Demo)', place: 'SDN Pengadilan 1', alamat: 'Jl. Pengadilan, Kec. Bogor Tengah, Kota Bogor' },
  { source: 'komunitas', app: 'Polmas Komunitas (Demo)', place: 'Komunitas Ojol Suryakencana', alamat: 'Jl. Suryakencana, Kec. Bogor Tengah, Kota Bogor' },
] as const;

const USERS = [
  { phone: '628001110001', name: 'Budi Santoso', roles: [{ role: 'warga', unit: 'RW 05 Paledang' }] },
  { phone: '628001110002', name: 'Aiptu Rahmat Hidayat', roles: [{ role: 'bhabinkamtibmas', unit: 'Polsek Bogor Tengah', kec: KEC }, { role: 'warga', unit: null }] },
  { phone: '628001110003', name: 'Dewi Anggraini', roles: [{ role: 'kantor', unit: 'Gedung Graha Pajajaran' }] },
  { phone: '628001110004', name: 'Hendra Wijaya', roles: [{ role: 'umkm', unit: 'Toko Roti Sinar Jaya' }] },
  { phone: '628001110005', name: 'Sri Wahyuni', roles: [{ role: 'sekolah', unit: 'SDN Pengadilan 1' }] },
] as const;

/**
 * Nomor Darurat demo per app sumber (seperti yang diisi kasir/warga di menu Nomor Darurat SDK). Pemilik nomor inilah
 * yang login di Polmas Keamanan. 0800 111 0006 (satpam) sengaja TIDAK punya akun: login pertama = buat password.
 */
const BHABIN_AREA = {
  province: { code: '32', name: 'Jawa Barat' }, regency: { code: '32.71', name: 'Kota Bogor' },
  district: { code: KEC, name: 'Bogor Tengah' }, village: null,
};
const CONTACTS: Record<string, { ref: string; reporter: string; list: { name: string; role: string; phone: string; area?: unknown }[] }> = {
  umkm: { ref: 'demo:kios-sinar-jaya', reporter: 'Kasir Toko Roti Sinar Jaya', list: [
    { name: 'Hendra Wijaya', role: 'Pemilik toko', phone: '628001110004' },
    { name: 'Agus Setiawan', role: 'Satpam', phone: '628001110006' },
    { name: 'Aiptu Rahmat Hidayat', role: 'Bhabinkamtibmas', phone: '628001110002', area: BHABIN_AREA },
  ] },
  warga: { ref: 'demo:warga-paledang', reporter: 'Keluarga Siti Rahmawati', list: [
    { name: 'Budi Santoso', role: 'Ketua RT 03', phone: '628001110001' },
    { name: 'Agus Setiawan', role: 'Satpam', phone: '628001110006' },
    { name: 'Aiptu Rahmat Hidayat', role: 'Bhabinkamtibmas', phone: '628001110002', area: BHABIN_AREA },
  ] },
  kantor: { ref: 'demo:graha-pajajaran', reporter: 'Resepsionis Graha Pajajaran', list: [
    { name: 'Dewi Anggraini', role: 'Koordinator keamanan', phone: '628001110003' },
  ] },
  sekolah: { ref: 'demo:sdn-pengadilan', reporter: 'Tata Usaha SDN Pengadilan 1', list: [
    { name: 'Sri Wahyuni', role: 'Guru piket', phone: '628001110005' },
  ] },
  komunitas: { ref: 'demo:ojol-suryakencana', reporter: 'Korlap Ojol Suryakencana', list: [
    { name: 'Budi Santoso', role: 'Ketua RT 03', phone: '628001110001' },
  ] },
};
/** Snapshot `reports.emergency_contacts` seperti yang dikirim SDK: "Nama (Jabatan)" + nomor. */
const snapshot = (source: string) => CONTACTS[source]?.list.map((c) => ({ name: `${c.name} (${c.role})`, phone: c.phone }));

async function seedContacts(accountId: string, apps: Record<string, { id: string; sourceId: string }>) {
  await withTenant(accountId, async (c) => {
    for (const [source, def] of Object.entries(CONTACTS)) {
      const app = apps[source]!;
      await c.query(`DELETE FROM emergency_contacts WHERE app_id = $1 AND reporter_ref = $2`, [app.id, def.ref]);
      for (const ct of def.list) {
        await c.query(
          `INSERT INTO emergency_contacts (account_id, app_id, reporter_ref, reporter_name, source_id, name, role, phone, active, area)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,true,$9)`,
          [accountId, app.id, def.ref, def.reporter, app.sourceId, ct.name, ct.role, ct.phone, ct.area ? JSON.stringify(ct.area) : null]);
      }
    }
  });
}

const REPORTERS = ['Siti Rahmawati', 'Dedi Kurniawan', 'Rina Marlina', 'Andi Saputra', 'Yuni Lestari', 'Agus Salim', 'Maya Puspita',
  'Joko Prasetyo', 'Lina Marlina', 'Fajar Nugroho', 'Wulan Sari', 'Rudi Hartono', 'Nina Kartika', 'Bayu Aji'];

const COMPLAINTS: { cat: string; title: string; desc: string }[] = [
  { cat: 'pencurian', title: 'Motor hilang di parkiran', desc: 'Motor Honda Beat hitam hilang saat diparkir depan warung sekitar pukul 21.00.' },
  { cat: 'pencurian', title: 'Pencurian kotak amal', desc: 'Kotak amal musala dibongkar orang tak dikenal tadi malam.' },
  { cat: 'mencurigakan', title: 'Orang asing mondar-mandir', desc: 'Dua orang tak dikenal memotret rumah-rumah warga dan mencatat nomor rumah.' },
  { cat: 'tawuran', title: 'Pelajar berkumpul bawa senjata tajam', desc: 'Sekelompok pelajar berkumpul di dekat rel, sebagian membawa celurit.' },
  { cat: 'kecelakaan', title: 'Tabrakan motor di simpang', desc: 'Dua motor bertabrakan, satu pengendara luka di kaki, butuh bantuan.' },
  { cat: 'gangguan', title: 'Balap liar setiap malam', desc: 'Balap liar mulai pukul 23.00 sangat mengganggu dan membahayakan warga.' },
  { cat: 'penipuan', title: 'Penipuan mengaku petugas PLN', desc: 'Ada orang mengaku petugas PLN meminta uang ganti meteran ke warga lansia.' },
  { cat: 'kebakaran', title: 'Asap dari gudang kosong', desc: 'Terlihat asap tebal keluar dari gudang kosong di belakang pasar.' },
  { cat: 'gangguan', title: 'Pengamen memaksa di lampu merah', desc: 'Pengamen memaksa dan mengetuk kaca mobil, pengendara merasa terancam.' },
  { cat: 'narkoba', title: 'Dugaan transaksi narkoba', desc: 'Sering ada transaksi mencurigakan di gang belakang kos-kosan pada malam hari.' },
];
const SOS_MSG = ['Tolong! Ada maling masuk rumah.', 'Darurat, ada orang pingsan di jalan.', 'Tolong, saya diikuti orang tak dikenal.',
  'Ada perkelahian di depan toko.', 'Kebakaran kecil di dapur warung, butuh bantuan.', 'Siswa dipalak di depan sekolah.', null];
const NOTES: Record<string, string[]> = {
  terima: ['Laporan diterima, segera dicek.', 'Diterima, menghubungi pelapor.'],
  verifikasi: ['Sudah dikonfirmasi dengan pelapor via telepon.', 'Dicek ke lokasi bersama Ketua RT, laporan benar.'],
  tangani: ['Menuju lokasi bersama Babinsa.', 'Koordinasi dengan piket Polsek.', 'Patroli diarahkan ke lokasi.'],
  selesai: ['Situasi kondusif, pelaku diamankan ke Polsek.', 'Sudah dimediasi, kedua pihak berdamai.', 'Patroli rutin ditambah di titik ini.'],
};

const rnd = (n: number) => Math.floor(Math.random() * n);
const pick = <T>(a: readonly T[]) => a[rnd(a.length)]!;
const minutes = (n: number) => n * 60_000;

/** Jam kejadian lebih sering malam (18.00–02.00) supaya peta panas jam rawan terlihat. */
function randomTime(daysAgoMax: number): Date {
  const day = rnd(daysAgoMax);
  const hourPool = [0, 1, 2, 7, 8, 12, 13, 16, 17, 18, 19, 19, 20, 20, 21, 21, 21, 22, 22, 22, 23, 23, 0, 1];
  const d = new Date(Date.now() - day * 86400_000);
  // jam WIB → UTC
  d.setUTCHours((pick(hourPool) - 7 + 24) % 24, rnd(60), rnd(60), 0);
  if (d.getTime() > Date.now()) d.setTime(d.getTime() - 86400_000);
  return d;
}

async function ensureApps(accountId: string) {
  const out: Record<string, { id: string; sourceId: string; name: string }> = {};
  await withTenant(accountId, async (c) => {
    for (const s of SOURCES) {
      let app = (await c.query(`SELECT id FROM apps WHERE account_id = $1 AND name = $2`, [accountId, s.app])).rows[0];
      if (!app) {
        app = (await c.query(
          `INSERT INTO apps (account_id, name, allowed_bundle_ids, polmas_source) VALUES ($1,$2,$3,$4) RETURNING id`,
          [accountId, s.app, [`id.polmas.demo.${s.source}`], s.source])).rows[0];
      } else {
        await c.query(`UPDATE apps SET polmas_source = $2 WHERE id = $1`, [app.id, s.source]);
      }
      let src = (await c.query(`SELECT id FROM sources WHERE app_id = $1 AND source_key = 'demo'`, [app.id])).rows[0];
      if (!src) {
        src = (await c.query(
          `INSERT INTO sources (app_id, account_id, source_key, label, platform, alamat) VALUES ($1,$2,'demo',$3,'android',$4) RETURNING id`,
          [app.id, accountId, s.place, s.alamat])).rows[0];
      }
      out[s.source] = { id: app.id, sourceId: src.id, name: s.app };
    }
  });
  return out;
}

async function ensureUsers() {
  const hash = await hashPassword(PASSWORD);
  const ids: Record<string, string> = {};
  await withPlatform(async (c) => {
    for (const u of USERS) {
      const row = (await c.query(
        `INSERT INTO pk_users (phone, name, password_hash, is_demo, created_via) VALUES ($1,$2,$3,true,'seed')
         ON CONFLICT (phone) DO UPDATE SET name = EXCLUDED.name, password_hash = EXCLUDED.password_hash, is_demo = true,
           failed_logins = 0, locked_until = NULL, disabled_at = NULL
         RETURNING id`, [u.phone, u.name, hash])).rows[0];
      ids[u.phone] = row.id;
      for (const r of u.roles) {
        const kec = 'kec' in r ? r.kec : null;
        const exists = await c.query(`SELECT 1 FROM pk_user_roles WHERE user_id = $1 AND role = $2 AND kecamatan_code IS NOT DISTINCT FROM $3`, [row.id, r.role, kec]);
        if (!exists.rowCount) {
          await c.query(`INSERT INTO pk_user_roles (user_id, role, kecamatan_code, unit) VALUES ($1,$2,$3,$4)`, [row.id, r.role, kec, r.unit]);
        }
      }
    }
  });
  return ids;
}

async function clearOldDemo(appIds: string[]) {
  const keys = await withPlatform(async (c) => {
    const ids = (await c.query(`SELECT id FROM reports WHERE app_id = ANY($1::uuid[]) AND metadata->>'demo' = 'true'`, [appIds])).rows.map((r) => r.id);
    await c.query(`DELETE FROM pk_news WHERE is_demo`);
    return (await deleteReports(c, ids)).storageKeys;
  });
  await removeObjects(keys);
}

interface Seeded { id: string; accountId: string; kind: string; created: Date }

async function insertReport(c: Db, app: { id: string; sourceId: string }, accountId: string, kels: string[], i: number,
  opts: { kind: 'sos' | 'pengaduan'; at: Date; status?: string; reporter?: { name: string; phone: string }; contacts?: { name: string; phone: string }[] },
  officer: { id: string; name: string }): Promise<Seeded> {
  const c0 = opts.kind === 'pengaduan' ? pick(COMPLAINTS) : null;
  const reporter = opts.reporter ?? { name: pick(REPORTERS), phone: '62800' + String(2000000 + rnd(999999)) };
  const ageMin = (Date.now() - opts.at.getTime()) / 60000;
  // Status realistis menurut umur laporan.
  const status = opts.status ?? (ageMin < 90 ? pick(['open', 'acknowledged', 'in_progress']) : ageMin < 60 * 24 * 2
    ? pick(['acknowledged', 'in_progress', 'resolved', 'resolved']) : pick(['resolved', 'resolved', 'resolved', 'resolved', 'false_alarm', 'in_progress', 'open']));
  const respMin = opts.kind === 'sos' ? 1 + rnd(14) : 20 + rnd(300);
  const ack = status === 'open' ? null : new Date(opts.at.getTime() + minutes(respMin));
  const verified = ack && status !== 'false_alarm' ? new Date(ack.getTime() + minutes(3 + rnd(20))) : null;
  const resolved = ['resolved', 'false_alarm'].includes(status) && ack ? new Date(ack.getTime() + minutes(30 + rnd(600))) : null;
  const jit = () => (Math.random() - 0.5) * 0.022;
  const r = (await c.query(
    `INSERT INTO reports (app_id, account_id, source_id, mode, kind, category, status, reporter_ref, reporter_name, reporter_phone, message, lat, lng,
       accuracy_m, idempotency_key, emergency_contacts, complaint_details, metadata, created_at, acknowledged_at, resolved_at, updated_at,
       kecamatan_code, kelurahan_code, area_source, area_checked_at, verified_at)
     VALUES ($1,$2,$3,'live',$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,'{"demo":true}',$17,$18,$19,$17,$20,$21,'seed',now(),$22)
     RETURNING id`,
    [app.id, accountId, app.sourceId, opts.kind, c0?.cat ?? 'darurat', status, `demo:${i}`, reporter.name, reporter.phone,
      c0 ? c0.desc : pick(SOS_MSG), CENTER.lat + jit(), CENTER.lng + jit(), 8 + rnd(30), `pkseed:${randomUUID()}`,
      opts.contacts ? JSON.stringify(opts.contacts) : null,
      c0 ? JSON.stringify({ title: c0.title, description: c0.desc, location_text: `${pick(['Jl. Suryakencana', 'Jl. Pengadilan', 'Jl. Juanda', 'Gg. Aut', 'Jl. Paledang', 'Jl. Kapten Muslihat'])} No. ${1 + rnd(120)}`, occurred_at: new Date(opts.at.getTime() - minutes(30 + rnd(300))).toISOString() }) : null,
      opts.at, ack, resolved, KEC, pick(kels), verified && ['in_progress', 'resolved'].includes(status) ? verified : null])).rows[0];

  // Timeline & tanggapan petugas sesuai status.
  const steps: [string, Date, string | null][] = [];
  if (ack) steps.push(['terima', ack, 'acknowledged']);
  if (verified && ['in_progress', 'resolved'].includes(status)) steps.push(['verifikasi', verified, null]);
  if (['in_progress', 'resolved'].includes(status) && verified) steps.push(['tangani', new Date(verified.getTime() + minutes(2)), 'in_progress']);
  if (status === 'resolved' && resolved) steps.push(['selesai', resolved, 'resolved']);
  if (status === 'false_alarm' && resolved) steps.push(['tidak_valid', resolved, 'false_alarm']);
  let from = 'open';
  for (const [action, at, to] of steps) {
    const note = action === 'tidak_valid' ? 'Dicek ke lokasi, tidak ditemukan kejadian.' : pick(NOTES[action] ?? ['']);
    await c.query(`INSERT INTO pk_responses (report_id, account_id, user_id, officer, action, note, created_at) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [r.id, accountId, officer.id, officer.name, action, note, at]);
    await c.query(
      `INSERT INTO report_events (report_id, account_id, actor_kind, type, from_status, to_status, note, created_at) VALUES ($1,$2,'responder',$3,$4,$5,$6,$7)`,
      [r.id, accountId, to ? 'status_changed' : 'note', to ? from : null, to, `Polmas Keamanan · ${officer.name}: ${action}`, at]);
    if (to) from = to;
  }
  return { id: r.id, accountId, kind: opts.kind, created: opts.at };
}

/** Video & foto demo dibuat ffmpeg (pola uji berwarna), diunggah lewat presigned PUT seperti perangkat sungguhan. */
async function seedMedia(targets: Seeded[]) {
  if (!mediaEnabled()) return console.log('• media dilewati: S3_* belum diisi');
  let ffmpeg = true;
  try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' }); } catch { ffmpeg = false; }
  if (!ffmpeg) return console.log('• media dilewati: ffmpeg tidak ada');
  const dir = mkdtempSync(path.join(tmpdir(), 'pkseed-'));
  try {
    let n = 0;
    for (const [i, t] of targets.entries()) {
      const isVideo = i % 3 !== 2;
      const file = path.join(dir, `${i}.${isVideo ? 'mp4' : 'jpg'}`);
      const hue = (i * 47) % 360;
      execFileSync('ffmpeg', isVideo
        ? ['-y', '-loglevel', 'error', '-f', 'lavfi', '-i', `testsrc2=size=360x640:rate=24`, '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=22050',
          '-t', String(4 + (i % 4)), '-vf', `hue=h=${hue}`, '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '34',
          '-c:a', 'aac', '-b:a', '48k', '-shortest', '-movflags', '+faststart', file]
        : ['-y', '-loglevel', 'error', '-f', 'lavfi', '-i', `testsrc2=size=720x960`, '-vf', `hue=h=${hue}`, '-frames:v', '1', '-q:v', '6', file]);
      const bytes = readFileSync(file);
      const id = randomUUID();
      const ct = isVideo ? 'video/mp4' : 'image/jpeg';
      const key = `accounts/${t.accountId}/reports/${t.id}/${id}.${isVideo ? 'mp4' : 'jpg'}`;
      const url = await presignPut(key, ct, bytes.length);
      const put = await fetch(url, { method: 'PUT', body: bytes, headers: { 'Content-Type': ct } });
      if (!put.ok) { console.log(`  ! upload gagal ${put.status}`); continue; }
      await withTenant(t.accountId, (c) => c.query(
        `INSERT INTO report_media (id, report_id, account_id, kind, content_type, size_bytes, duration_s, storage_key, status, uploaded_by, created_at, uploaded_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'ready','reporter',$9,$9)`,
        [id, t.id, t.accountId, isVideo ? 'video' : 'image', ct, bytes.length, isVideo ? 4 + (i % 4) : null, key, new Date(t.created.getTime() + minutes(1))]));
      n++;
    }
    console.log(`• ${n} media demo diunggah ke bucket`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const NEWS = [
  { cat: 'imbauan', title: 'Waspada pencurian motor di area parkir pasar', summary: 'Selalu kunci ganda kendaraan dan parkir di tempat yang diawasi juru parkir resmi.', days: 0 },
  { cat: 'pengumuman', title: 'Patroli malam gabungan setiap Jumat & Sabtu', summary: 'Polsek Bogor Tengah bersama Babinsa dan Linmas berpatroli mulai pukul 22.00 di titik rawan.', days: 1 },
  { cat: 'kabar', title: 'Pelaku pencurian kotak amal berhasil diamankan', summary: 'Berkat laporan warga lewat Polmas, pelaku diamankan kurang dari 24 jam.', days: 2 },
  { cat: 'imbauan', title: 'Modus penipuan mengaku petugas PLN', summary: 'Petugas resmi tidak pernah meminta uang tunai di rumah. Laporkan bila menemui.', days: 4 },
  { cat: 'pengumuman', title: 'Sosialisasi Polmas Digital di Kelurahan Paledang', summary: 'Pelatihan penggunaan tombol SOS untuk pengurus RT/RW, Sabtu pukul 09.00.', days: 6 },
  { cat: 'kabar', title: 'Siskamling aktif kembali di 12 RW', summary: 'Jumlah laporan gangguan malam turun dibanding bulan lalu.', days: 9 },
];

async function main() {
  const account = (await pool.query(`SELECT account_id FROM users WHERE email = 'demo@siagasos.test'`)).rows[0];
  if (!account) throw new Error('Akun demo belum ada. Jalankan pnpm seed:demo dulu.');
  const accountId = account.account_id as string;
  const apps = await ensureApps(accountId);
  console.log('• 5 app sumber demo siap');
  const users = await ensureUsers();
  console.log(`• ${USERS.length} akun Polmas Keamanan (password ${PASSWORD})`);
  await seedContacts(accountId, apps);
  // Peran "penerima" turunan Nomor Darurat, sama seperti saat login. Satpam 0800 111 0006 dibiarkan tanpa akun.
  await withPlatform(async (c) => {
    for (const u of USERS) await syncContactRoles(c, users[u.phone]!, u.phone);
    await c.query(`DELETE FROM pk_users WHERE phone = '628001110006' AND created_via = 'contact'`);
  });
  console.log('• Nomor Darurat demo di 5 app sumber (pemilik toko, satpam, ketua RT, guru, Bhabinkamtibmas)');
  await clearOldDemo(Object.values(apps).map((a) => a.id));

  const kels = (await pool.query(`SELECT kode FROM wilayah WHERE parent = $1`, [KEC])).rows.map((r) => r.kode);
  const officer = { id: users['628001110002']!, name: 'Aiptu Rahmat Hidayat (Polsek Bogor Tengah)' };
  const budi = { name: 'Budi Santoso', phone: '628001110001' };
  const bhabin = { name: 'Aiptu Rahmat Hidayat', phone: '628001110002' };
  const seeded: Seeded[] = [];
  const weights = ['warga', 'warga', 'warga', 'kantor', 'umkm', 'umkm', 'sekolah', 'komunitas'];
  for (let i = 0; i < 150; i++) {
    const src = pick(weights);
    const app = apps[src]!;
    const kind = Math.random() < 0.35 ? 'sos' : 'pengaduan';
    const mine = i % 17 === 0;
    const s = await withTenant(accountId, (c) => insertReport(c, app, accountId, kels, i, {
      kind, at: randomTime(35),
      reporter: mine ? budi : undefined,
      contacts: kind === 'sos' ? snapshot(src) : undefined,
    }, officer));
    seeded.push(s);
  }
  // Skenario lengkap: SOS terbuka dari warga (memanggil Ketua RT, satpam, Bhabinkamtibmas) dan dari kios (pemilik +
  // satpam + Bhabinkamtibmas), plus laporan sekolah yang belum ditanggapi.
  const live = await withTenant(accountId, (c) => insertReport(c, apps.warga!, accountId, kels, 900, {
    kind: 'sos', at: new Date(Date.now() - minutes(2)), status: 'open', contacts: snapshot('warga'),
  }, officer));
  seeded.push(await withTenant(accountId, (c) => insertReport(c, apps.umkm!, accountId, kels, 902, {
    kind: 'sos', at: new Date(Date.now() - minutes(1)), status: 'open', contacts: snapshot('umkm'),
  }, officer)));
  await withTenant(accountId, (c) => insertReport(c, apps.sekolah!, accountId, kels, 901, { kind: 'pengaduan', at: new Date(Date.now() - minutes(25)), status: 'open' }, officer));
  seeded.push(live);
  console.log(`• ${seeded.length + 1} laporan demo di Kec. Bogor Tengah (1 SOS aktif)`);

  await withPlatform(async (c) => {
    for (const n of NEWS) {
      await c.query(`INSERT INTO pk_news (kecamatan_code, category, title, summary, body, author, is_demo, published_at) VALUES ($1,$2,$3,$4,$5,$6,true,$7)`,
        [n.days % 2 ? KEC : null, n.cat, n.title, n.summary, `${n.summary}\n\nInformasi lebih lanjut hubungi Bhabinkamtibmas kelurahan Anda atau gunakan tombol SOS di aplikasi Polmas Digital. (Konten demo)`,
          'Humas Polsek Bogor Tengah (Demo)', new Date(Date.now() - n.days * 86400_000 - minutes(rnd(600)))]);
    }
  });
  console.log(`• ${NEWS.length} berita demo`);

  const recent = seeded.filter((s) => Date.now() - s.created.getTime() < 20 * 86400_000).slice(0, 12);
  await seedMedia(recent);
  console.log('\nLogin Polmas Keamanan (password demo1234):');
  console.log('  0800 111 0002 Bhabinkamtibmas · 0800 111 0004 pemilik toko · 0800 111 0001 Ketua RT');
  console.log('  0800 111 0006 satpam: belum punya akun → login pertama membuat password');
  await pool.end();
}

main().catch(async (e) => {
  console.error(e);
  await pool.end();
  process.exit(1);
});
