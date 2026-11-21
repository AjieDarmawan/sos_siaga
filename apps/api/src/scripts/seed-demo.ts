import { randomUUID } from 'node:crypto';
import { authenticator } from 'otplib';
import { pool, withTenant } from '../db.js';
import { hashPassword } from '../lib/auth.js';

/**
 * Data demo untuk melihat portal & dashboard: pnpm seed:demo  (API harus sedang jalan, NODE_ENV != production)
 *
 * Membuat (lewat API sungguhan, jadi timeline/realtime/webhook ikut terisi):
 *  - PT Demo Siaga Nusantara (approved) — owner  demo@siagasos.test / demo12345
 *  - responder                                     satpam@siagasos.test / demo12345
 *  - 2 app (web + Android), source per gedung, ±16 laporan live/test di Jakarta dengan status beragam
 * Aman dijalankan ulang: akun dipakai ulang, laporan baru ditambahkan.
 */
const API = process.env.PUBLIC_API_URL ?? 'http://localhost:4000';
const PORTAL = process.env.SEED_PORTAL_ORIGIN ?? 'http://localhost:5174';
const OWNER = { email: 'demo@siagasos.test', password: 'demo12345' };
const RESPONDER = { email: 'satpam@siagasos.test', password: 'demo12345', name: 'Agus Satpam' };
const ADMIN = { email: 'seed-admin@siagasos.test', password: 'seed-admin-password-123' };
/** Superadmin dev untuk apps/admin. Secret TOTP tetap supaya bisa dipakai lintas seed; kode: `pnpm admin:otp`. JANGAN dipakai di produksi. */
const SUPERADMIN = { email: 'admin@siagasos.test', password: 'admin-demo-12345', totp: 'KVKFKRCPNZQUYMLXOVYDSQKJKZDTSRLD' };

async function call<T = any>(method: string, path: string, o: { token?: string; body?: unknown; headers?: Record<string, string>; form?: FormData } = {}): Promise<T> {
  const headers: Record<string, string> = { ...o.headers };
  if (o.token) headers.Authorization = `Bearer ${o.token}`;
  if (o.body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(API + path, { method, headers, body: o.form ?? (o.body !== undefined ? JSON.stringify(o.body) : undefined) });
  const data = res.status === 204 ? null : await res.json().catch(() => null);
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${JSON.stringify(data)}`);
  return data as T;
}

const login = (email: string, password: string) =>
  call<{ token: string }>('POST', '/portal/auth/login', { body: { email, password } }).then((r) => r.token).catch(() => null);

const pdf = () => new Blob([Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n')], { type: 'application/pdf' });

async function ensureAccount() {
  let token = await login(OWNER.email, OWNER.password);
  if (token) {
    console.log('• akun demo sudah ada, dipakai ulang');
    return token;
  }
  const nib = '9' + String(Date.now()).slice(-12);
  const reg = await call('POST', '/portal/auth/register', {
    body: {
      company: {
        legal_name: 'PT Demo Siaga Nusantara', entity_type: 'pt', nib, npwp: '01.234.567.8-901.000',
        address: 'Jl. Jenderal Sudirman Kav. 52-53, Jakarta Selatan', phone: '021-5150000', website: 'https://demo-siaga.co.id',
        industry: 'Logistik & pergudangan', est_users: 1200, usage_plan: 'Karyawan gudang & kurir menekan SOS dari aplikasi; tim keamanan merespons dari dashboard.',
      },
      pic: { full_name: 'Rina Pratama', email: OWNER.email, phone: '+628121234567', position: 'Head of Security', is_director: true, password: OWNER.password },
      accept_terms: true,
    },
  });
  if (!reg.dev_verification_token) throw new Error('dev_verification_token tidak ada: jalankan API dengan NODE_ENV=development');
  token = (await call('POST', '/portal/auth/verify-email', { body: { token: reg.dev_verification_token } })).token as string;

  for (const doc_type of ['nib', 'npwp', 'ktp_pic', 'akta', 'sk_kemenkumham']) {
    const form = new FormData();
    form.append('doc_type', doc_type);
    form.append('file', pdf(), `${doc_type}.pdf`);
    await call('POST', '/portal/onboarding/documents', { token, form });
  }
  await call('POST', '/portal/onboarding/submit', { token });

  // Setujui lewat API admin (password + TOTP), sama seperti reviewer sungguhan.
  const secret = authenticator.generateSecret();
  await pool.query(
    `INSERT INTO platform_admins (email, password_hash, totp_secret, role) VALUES ($1,$2,$3,'reviewer')
     ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash, totp_secret = EXCLUDED.totp_secret`,
    [ADMIN.email, await hashPassword(ADMIN.password), secret],
  );
  const adm = await call('POST', '/admin/auth/login', { body: { email: ADMIN.email, password: ADMIN.password, totp: authenticator.generate(secret) } });
  await call('POST', `/admin/accounts/${reg.account_id}/decision`, { token: adm.token, body: { decision: 'approved', checklist: { nib_oss: true, akta_ahu: true, npwp: true, ktp: true } } });
  console.log('• akun demo dibuat & disetujui');
  return (await login(OWNER.email, OWNER.password))!;
}

async function ensureResponder(owner: string) {
  if (await login(RESPONDER.email, RESPONDER.password)) return;
  const inv = await call('POST', '/portal/team/invites', { token: owner, body: { email: RESPONDER.email, role: 'responder' } });
  await call('POST', '/portal/auth/accept-invite', { body: { token: inv.dev_invite_token, full_name: RESPONDER.name, password: RESPONDER.password, phone: '+628139876543' } });
  console.log('• responder dibuat');
}

async function ensureApps(owner: string) {
  const { data } = await call('GET', '/portal/apps', { token: owner });
  const pk = (a: any, mode: string) => a.keys.find((k: any) => k.kind === 'publishable' && k.mode === mode && k.active)?.key as string;
  let web = data.find((a: any) => a.name === 'Aplikasi Karyawan (Web)');
  let android = data.find((a: any) => a.name === 'Aplikasi Kurir (Android)');
  if (!web) {
    web = (await call('POST', '/portal/apps', {
      token: owner,
      body: {
        name: 'Aplikasi Karyawan (Web)', allowed_origins: [PORTAL, 'https://karyawan.demo-siaga.co.id'], webhook_url: 'https://httpbin.org/status/200',
        sdk_config: { categories: ['kriminal', 'medis', 'kebakaran', 'kecelakaan', 'general'], hold_seconds: 3, recipient_text: 'Laporan dikirim ke tim keamanan PT Demo Siaga', fallback_phone: '110' },
      },
    })).app;
    for (const [source_key, label] of [['gudang-cakung', 'Gudang Cakung'], ['kantor-sudirman', 'Kantor Pusat Sudirman'], ['hub-tanjung-priok', 'Hub Tanjung Priok']]) {
      await call('POST', `/portal/apps/${web.id}/sources`, { token: owner, body: { source_key, label, platform: 'web' } });
    }
    web = await call('GET', `/portal/apps/${web.id}`, { token: owner });
  }
  if (!android) {
    android = (await call('POST', '/portal/apps', {
      token: owner, body: { name: 'Aplikasi Kurir (Android)', allowed_bundle_ids: ['id.demosiaga.kurir'] },
    })).app;
    android = await call('GET', `/portal/apps/${android.id}`, { token: owner });
  }
  return {
    web: { live: pk(web, 'live'), test: pk(web, 'test'), headers: { Origin: PORTAL } },
    android: { live: pk(android, 'live'), test: pk(android, 'test'), headers: { 'X-SOS-Bundle': 'id.demosiaga.kurir' } },
  };
}

type Final = 'open' | 'acknowledged' | 'in_progress' | 'resolved' | 'false_alarm' | 'cancelled';
interface Seed {
  app: 'web' | 'android'; mode: 'live' | 'test'; category: string; message: string; source?: string;
  at: [number, number]; reporter: string; phone?: string; minutesAgo: number; final: Final; notes?: string[]; trail?: number;
}

// Lokasi nyata di sekitar Jakarta. Beberapa laporan "Baru" sengaja dibiarkan supaya alarm dashboard terlihat.
const SEEDS: Seed[] = [
  { app: 'web', mode: 'live', category: 'kriminal', message: 'Ada orang tidak dikenal mencoba masuk area loading dock', source: 'gudang-cakung', at: [-6.1867, 106.9411], reporter: 'Budi Santoso', phone: '+62811110001', minutesAgo: 2, final: 'open', trail: 3 },
  { app: 'android', mode: 'live', category: 'kecelakaan', message: 'Motor kurir terserempet truk, kaki luka', at: [-6.2246, 106.8090], reporter: 'Dedi Kurniawan', phone: '+62811110002', minutesAgo: 6, final: 'open', trail: 4 },
  { app: 'web', mode: 'live', category: 'medis', message: 'Rekan kerja pingsan di lantai 12', source: 'kantor-sudirman', at: [-6.2253, 106.8020], reporter: 'Sari Wulandari', phone: '+62811110003', minutesAgo: 14, final: 'in_progress', notes: ['Tim P3K lantai 12 menuju lokasi', 'Ambulans RS terdekat sudah dihubungi'] },
  { app: 'web', mode: 'live', category: 'kebakaran', message: 'Asap dari panel listrik di rak C', source: 'hub-tanjung-priok', at: [-6.1050, 106.8830], reporter: 'Joko Prasetyo', minutesAgo: 25, final: 'acknowledged', notes: ['Damkar internal dikerahkan'] },
  { app: 'android', mode: 'live', category: 'kriminal', message: 'Dibuntuti dua orang bermotor sejak Jl. Gatot Subroto', at: [-6.2360, 106.8240], reporter: 'Rudi Hartono', phone: '+62811110005', minutesAgo: 48, final: 'resolved', notes: ['Kurir diarahkan ke pos polisi terdekat', 'Kurir aman di Polsek Mampang'], trail: 5 },
  { app: 'web', mode: 'live', category: 'medis', message: 'Tangan terjepit forklift', source: 'gudang-cakung', at: [-6.1880, 106.9390], reporter: 'Ahmad Fauzi', minutesAgo: 95, final: 'resolved', notes: ['Dibawa ke klinik gudang', 'Sudah ditangani dokter, luka ringan'] },
  { app: 'web', mode: 'live', category: 'general', message: 'Tombol tertekan tidak sengaja', source: 'kantor-sudirman', at: [-6.2249, 106.8025], reporter: 'Lina Marlina', minutesAgo: 130, final: 'false_alarm', notes: ['Dikonfirmasi via telepon: tidak ada kejadian'] },
  { app: 'android', mode: 'live', category: 'kecelakaan', message: 'Mobil box mogok di tol, hampir ditabrak', at: [-6.2600, 106.8700], reporter: 'Hendra Wijaya', minutesAgo: 240, final: 'resolved', notes: ['Derek tol dihubungi'] },
  { app: 'web', mode: 'live', category: 'kriminal', message: 'Pencurian paket di area sortir', source: 'hub-tanjung-priok', at: [-6.1040, 106.8850], reporter: 'Yanti Susanti', minutesAgo: 60 * 20, final: 'resolved', notes: ['CCTV diperiksa', 'Laporan diteruskan ke Polsek Tanjung Priok'] },
  { app: 'android', mode: 'live', category: 'medis', message: 'Sesak napas saat antar paket', at: [-6.1750, 106.8270], reporter: 'Fajar Nugroho', minutesAgo: 60 * 30, final: 'resolved', notes: ['Diantar ke RSUD Tanah Abang'] },
  { app: 'web', mode: 'live', category: 'kebakaran', message: 'Alarm asap berbunyi di pantry', source: 'kantor-sudirman', at: [-6.2255, 106.8018], reporter: 'Maya Sari', minutesAgo: 60 * 50, final: 'false_alarm', notes: ['Asap dari microwave, aman'] },
  { app: 'android', mode: 'live', category: 'kriminal', message: 'Penodongan di lampu merah', at: [-6.2010, 106.7820], reporter: 'Bayu Saputra', minutesAgo: 60 * 75, final: 'cancelled' },
  { app: 'web', mode: 'live', category: 'kecelakaan', message: 'Tumpahan oli, karyawan terpeleset', source: 'gudang-cakung', at: [-6.1872, 106.9402], reporter: 'Eko Purnomo', minutesAgo: 60 * 100, final: 'resolved', notes: ['Area dibersihkan dan diberi tanda'] },
  { app: 'web', mode: 'test', category: 'medis', message: 'Uji coba integrasi SDK web', source: 'kantor-sudirman', at: [-6.2240, 106.8030], reporter: 'QA Tester', minutesAgo: 9, final: 'open' },
  { app: 'android', mode: 'test', category: 'general', message: 'Uji coba SDK Android', at: [-6.2000, 106.8450], reporter: 'QA Android', minutesAgo: 60 * 26, final: 'resolved', notes: ['Integrasi OK'] },
  { app: 'web', mode: 'test', category: 'kriminal', message: 'Tes alur penanganan', source: 'gudang-cakung', at: [-6.1890, 106.9420], reporter: 'QA Tester', minutesAgo: 60 * 3, final: 'in_progress' },
];

const PATH: Final[] = ['acknowledged', 'in_progress', 'resolved'];

async function main() {
  if (process.env.NODE_ENV === 'production') throw new Error('seed:demo tidak boleh dijalankan di produksi');
  console.log(`API ${API}`);
  await pool.query(
    `INSERT INTO platform_admins (email, password_hash, totp_secret, role) VALUES ($1,$2,$3,'superadmin')
     ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash, totp_secret = EXCLUDED.totp_secret, role = 'superadmin'`,
    [SUPERADMIN.email, await hashPassword(SUPERADMIN.password), SUPERADMIN.totp],
  );
  const owner = await ensureAccount();
  await ensureResponder(owner);
  const responder = (await login(RESPONDER.email, RESPONDER.password))!;
  const keys = await ensureApps(owner);
  const me = await call('GET', '/portal/me', { token: owner });

  const created: { id: string; s: Seed }[] = [];
  for (const s of SEEDS) {
    const k = keys[s.app];
    const pk = k[s.mode];
    const jitter = () => (Math.random() - 0.5) * 0.002;
    const r = await call('POST', '/v1/sdk/reports', {
      headers: { ...k.headers, 'X-SOS-Key': pk, 'Idempotency-Key': randomUUID() },
      body: {
        category: s.category, message: s.message, ...(s.source ? { source_key: s.source } : {}),
        location: { lat: s.at[0] + jitter(), lng: s.at[1] + jitter(), accuracy_m: 10 + Math.round(Math.random() * 40) },
        reporter: { ref: `emp-${randomUUID().slice(0, 8)}`, name: s.reporter, ...(s.phone ? { phone: s.phone } : {}) },
        device: { platform: s.app === 'web' ? 'web' : 'android', sdk_version: '0.1.0' },
      },
    });
    for (let i = 1; i <= (s.trail ?? 0); i++) {
      await call('POST', `/v1/sdk/reports/${r.id}/locations`, {
        headers: { ...k.headers, 'X-SOS-Key': pk },
        body: { lat: s.at[0] + i * 0.0008, lng: s.at[1] + i * 0.0006, accuracy_m: 12 },
      });
    }
    if (s.final === 'cancelled') {
      await call('POST', `/v1/sdk/reports/${r.id}/cancel`, { headers: { ...k.headers, 'X-SOS-Key': pk } });
    } else if (s.final !== 'open') {
      const steps = s.final === 'false_alarm' ? ['acknowledged', 'false_alarm'] : PATH.slice(0, PATH.indexOf(s.final) + 1);
      const notes = [...(s.notes ?? [])];
      for (const [i, status] of steps.entries()) {
        const who = i % 2 ? owner : responder;
        await call('PATCH', `/portal/reports/${r.id}`, { token: who, body: { status, ...(notes.length ? { note: notes.shift() } : {}) } });
      }
    }
    created.push({ id: r.id, s });
    process.stdout.write('.');
  }
  console.log(`\n• ${created.length} laporan dibuat`);

  // Mundurkan waktu supaya riwayat terlihat wajar (API selalu memakai now()).
  await withTenant(me.account.id, async (c) => {
    for (const { id, s } of created) {
      const shift = `${s.minutesAgo} minutes`;
      await c.query(
        `UPDATE reports SET created_at = created_at - $2::interval, updated_at = updated_at - $2::interval + interval '1 minute' * least($3, 30),
           acknowledged_at = acknowledged_at - $2::interval + interval '1 minute' * least($3, 2),
           resolved_at = resolved_at - $2::interval + interval '1 minute' * least($3, 30)
         WHERE id = $1`,
        [id, shift, s.minutesAgo],
      );
      await c.query(
        `UPDATE report_events SET created_at = created_at - $2::interval
           + (row_number_shift * interval '1 minute' * least($3, 10))
         FROM (SELECT id AS eid, (row_number() OVER (ORDER BY created_at, id) - 1) AS row_number_shift FROM report_events WHERE report_id = $1) x
         WHERE report_events.id = x.eid`,
        [id, shift, s.minutesAgo],
      );
      await c.query(`UPDATE report_locations SET recorded_at = recorded_at - $2::interval WHERE report_id = $1`, [id, shift]);
    }
  });

  console.log(`
Selesai. Buka ${PORTAL}
  Owner     : ${OWNER.email} / ${OWNER.password}
  Responder : ${RESPONDER.email} / ${RESPONDER.password}
Panel admin ${process.env.SEED_ADMIN_ORIGIN ?? 'http://localhost:5175'}
  Superadmin: ${SUPERADMIN.email} / ${SUPERADMIN.password}  (kode 2FA: pnpm admin:otp, atau scan ${authenticator.keyuri(SUPERADMIN.email, 'SiagaSOS Admin (dev)', SUPERADMIN.totp)})
Kirim SOS baru (muncul realtime + bunyi):
  curl -X POST ${API}/v1/sdk/reports -H 'Content-Type: application/json' -H 'Origin: ${PORTAL}' \\
    -H 'X-SOS-Key: ${keys.web.live}' -H "Idempotency-Key: $(uuidgen)" \\
    -d '{"category":"kriminal","message":"Tes SOS","location":{"lat":-6.2,"lng":106.85},"reporter":{"name":"Demo"}}'`);
  await pool.end();
}

main().catch(async (e) => {
  console.error(e);
  await pool.end().catch(() => {});
  process.exit(1);
});
