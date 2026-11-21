/**
 * Smoke test end-to-end M1 terhadap API yang sedang berjalan (pnpm dev:api).
 * Membuat data baru setiap run (NIB acak). Jangan jalankan ke production.
 *   pnpm smoke            # default http://localhost:4000
 */
import { authenticator } from 'otplib';
import { pool } from '../db.js';
import { hashPassword } from '../lib/auth.js';

const BASE = process.env.SMOKE_URL ?? 'http://localhost:4000';
const ORIGIN = 'https://app.contoh-klien.co.id';
let passed = 0;

function ok(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(`✘ ${msg}`);
  passed++;
  console.log(`✔ ${msg}`);
}

async function call(method: string, path: string, opts: { token?: string; body?: unknown; headers?: Record<string, string>; form?: FormData } = {}) {
  const headers: Record<string, string> = { ...opts.headers };
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  if (opts.body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(BASE + path, { method, headers, body: opts.form ?? (opts.body === undefined ? undefined : JSON.stringify(opts.body)) });
  const text = await res.text();
  let data: any = text;
  try { data = JSON.parse(text); } catch { /* bukan JSON */ }
  return { status: res.status, data, headers: res.headers };
}

const rand = (n: number) => Array.from({ length: n }, () => Math.floor(Math.random() * 10)).join('');
const uuid = () => crypto.randomUUID();

async function registerCompany(label: string) {
  const email = `pic.${label}.${rand(6)}@ptcontoh.co.id`;
  const reg = await call('POST', '/portal/auth/register', {
    body: {
      company: { legal_name: `PT ${label} Sejahtera`, entity_type: 'pt', nib: rand(13), npwp: '01.234.567.8-901.000', address: 'Jl. Sudirman No. 1, Jakarta Pusat',
        phone: '+62215551234', website: 'https://ptcontoh.co.id', industry: 'gedung perkantoran', est_users: 800, usage_plan: 'Tombol darurat untuk penghuni gedung kantor 20 lantai' },
      pic: { full_name: `Budi ${label}`, email, phone: '+6281234567890', position: 'Direktur', is_director: true, password: 'rahasia-sekali-123' },
      accept_terms: true,
    },
  });
  ok(reg.status === 201 && reg.data.status === 'pending_email', `[${label}] registrasi → pending_email`);
  const login0 = await call('POST', '/portal/auth/login', { body: { email, password: 'rahasia-sekali-123' } });
  ok(login0.status === 403 && login0.data.error.code === 'email_not_verified', `[${label}] login sebelum verifikasi ditolak`);
  const ver = await call('POST', '/portal/auth/verify-email', { body: { token: reg.data.dev_verification_token } });
  ok(ver.status === 200 && ver.data.account_status === 'pending_review', `[${label}] verifikasi email → pending_review`);
  return { email, accountId: reg.data.account_id as string, token: ver.data.token as string };
}

const PDF = new Blob([Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF')], { type: 'application/pdf' });

async function main() {
  console.log(`SiagaSOS smoke → ${BASE}\n`);
  const health = await call('GET', '/healthz');
  ok(health.status === 200, 'healthz 200');

  // ---------------------------------------------------------------- onboarding + mode test (F-21, F-29)
  const A = await registerCompany('Alfa');
  const me = await call('GET', '/portal/me', { token: A.token });
  ok(me.data.account.limited === true, 'sesi terbatas selama pending_review');

  const app = await call('POST', '/portal/apps', { token: A.token, body: { name: 'Gedung Alfa Web', allowed_origins: [ORIGIN] } });
  ok(app.status === 201 && app.data.keys.test && !app.data.keys.live, 'buat app saat review → hanya kunci test');
  const appId = app.data.app.id as string;
  const pkTest = app.data.keys.test.publishable.key as string;
  const skTest = app.data.keys.test.secret.key as string;
  ok(pkTest.startsWith('pk_test_') && skTest.startsWith('sk_test_'), 'format kunci pk_test_/sk_test_');

  const liveDenied = await call('POST', `/portal/apps/${appId}/keys`, { token: A.token, body: { mode: 'live' } });
  ok(liveDenied.status === 403 && liveDenied.data.error.code === 'account_not_approved', 'kunci live ditolak sebelum approved');

  const keysList = await call('GET', `/portal/apps/${appId}/keys`, { token: A.token });
  ok(keysList.data.data.every((k: any) => k.kind === 'publishable' ? k.key : k.key === undefined), 'secret key tidak pernah ditampilkan ulang');

  // ---------------------------------------------------------------- SDK
  const sdkH = (key: string, extra: Record<string, string> = {}) => ({ 'X-SOS-Key': key, Origin: ORIGIN, ...extra });
  const cfg = await call('GET', '/v1/sdk/config', { headers: sdkH(pkTest) });
  ok(cfg.status === 200 && cfg.data.mode === 'test' && cfg.data.hold_seconds === 3, 'GET /v1/sdk/config');

  const noIdem = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkTest), body: { category: 'medis' } });
  ok(noIdem.status === 400 && noIdem.data.error.code === 'idempotency_key_required', 'Idempotency-Key wajib');

  const idem = uuid();
  const payload = {
    source_key: 'gedung-a-web', category: 'kriminal', message: 'Ada orang mencurigakan di parkiran',
    location: { lat: -6.2088, lng: 106.8456, accuracy_m: 12 }, reporter: { ref: 'user_123', name: 'Budi', phone: '+62812000' },
    device: { platform: 'web', sdk_version: '0.1.0' }, metadata: { lantai: 3 },
  };
  const t0 = Date.now();
  const r1 = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkTest, { 'Idempotency-Key': idem }), body: payload });
  ok(r1.status === 201 && r1.data.status === 'open' && r1.data.mode === 'test', `POST /v1/sdk/reports → 201 (${Date.now() - t0} ms)`);
  const r1b = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkTest, { 'Idempotency-Key': idem }), body: payload });
  ok(r1b.status === 200 && r1b.data.id === r1.data.id, 'retry dengan Idempotency-Key sama → laporan yang sama, tanpa duplikat');

  const badOrigin = await call('POST', '/v1/sdk/reports', { headers: { 'X-SOS-Key': pkTest, Origin: 'https://jahat.example', 'Idempotency-Key': uuid() }, body: payload });
  ok(badOrigin.status === 403 && badOrigin.data.error.code === 'origin_not_allowed', 'origin di luar allowed_origins → 403 (F-04)');

  const skOnSdk = await call('GET', '/v1/sdk/config', { headers: sdkH(skTest) });
  ok(skOnSdk.status === 401 && skOnSdk.data.error.code === 'wrong_key_type', 'secret key ditolak di endpoint SDK');

  const loc = await call('POST', `/v1/sdk/reports/${r1.data.id}/locations`, { headers: sdkH(pkTest), body: { lat: -6.209, lng: 106.846, accuracy_m: 8 } });
  ok(loc.status === 200 && loc.data.accepted === true, 'update live location');

  // ---------------------------------------------------------------- media (foto/video/suara → object storage)
  if (process.env.S3_ENDPOINT) {
    const png = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63f8cfc0f01f0005000201a5f6d5e70000000049454e44ae426082', 'hex');
    const mUp = await call('POST', `/v1/sdk/reports/${r1.data.id}/media`, { headers: sdkH(pkTest), body: { content_type: 'image/png', size_bytes: png.length } });
    ok(mUp.status === 201 && mUp.data.media.status === 'pending' && mUp.data.upload.url, 'media: presigned PUT diberikan');
    const put = await fetch(mUp.data.upload.url, { method: 'PUT', headers: mUp.data.upload.headers, body: png });
    ok(put.status === 200, 'media: unggah langsung ke object storage');
    const mDone = await call('POST', `/v1/sdk/reports/${r1.data.id}/media/${mUp.data.media.id}/complete`, { headers: sdkH(pkTest) });
    ok(mDone.status === 200 && mDone.data.status === 'ready', 'media: complete → ready (HEAD diverifikasi)');
    const exe = await call('POST', `/v1/sdk/reports/${r1.data.id}/media`, { headers: sdkH(pkTest), body: { content_type: 'application/x-msdownload', size_bytes: 10 } });
    ok(exe.status === 415, 'media: tipe file tidak didukung ditolak');
    const huge = await call('POST', `/v1/sdk/reports/${r1.data.id}/media`, { headers: sdkH(pkTest), body: { content_type: 'video/mp4', size_bytes: 10 ** 9 } });
    ok(huge.status === 413, 'media: file terlalu besar ditolak');
    const ghost = await call('POST', `/v1/sdk/reports/${r1.data.id}/media`, { headers: sdkH(pkTest), body: { content_type: 'image/jpeg', size_bytes: 100 } });
    const ghostDone = await call('POST', `/v1/sdk/reports/${r1.data.id}/media/${ghost.data.media.id}/complete`, { headers: sdkH(pkTest) });
    ok(ghostDone.status === 409 && ghostDone.data.error.code === 'upload_missing', 'media: complete tanpa file ditolak');
    const md = await call('GET', `/portal/reports/${r1.data.id}`, { token: A.token });
    const shown = md.data.media?.[0];
    ok(md.data.media?.length === 1 && shown.kind === 'image' && (await fetch(shown.url)).status === 200, 'media: tampil di detail portal + URL baca berfungsi');
    ok((await fetch(shown.url.split('?')[0])).status === 403, 'media: bucket privat (tanpa tanda tangan 403)');
  } else {
    console.log('… media dilewati (S3_ENDPOINT kosong)');
  }

  // ---------------------------------------------------------------- dashboard
  const list = await call('GET', '/portal/reports?mode=test', { token: A.token });
  ok(list.data.data.length === 1 && list.data.data[0].source_key === 'gedung-a-web', 'laporan muncul di dashboard + source otomatis dibuat');
  const ack = await call('PATCH', `/portal/reports/${r1.data.id}`, { token: A.token, body: { status: 'acknowledged', note: 'Satpam pos 2 menuju lokasi' } });
  ok(ack.status === 200 && ack.data.status === 'acknowledged', 'responder ubah status → acknowledged');
  const st = await call('GET', `/v1/sdk/reports/${r1.data.id}`, { headers: sdkH(pkTest) });
  ok(st.data.status === 'acknowledged' && st.data.acknowledged_at, 'status kembali ke SDK (F-11)');
  const cancelLate = await call('POST', `/v1/sdk/reports/${r1.data.id}/cancel`, { headers: sdkH(pkTest), body: {} });
  ok(cancelLate.status === 409, 'pengguna tidak bisa batal setelah petugas merespons');
  const detail = await call('GET', `/portal/reports/${r1.data.id}`, { token: A.token });
  const tl = detail.data.timeline.filter((e: any) => e.type !== 'media').map((e: any) => e.type).join(',');
  ok(tl === 'created,status_changed' && detail.data.locations.length === 2, 'timeline (created, status_changed) + riwayat lokasi');
  const resolved = await call('PATCH', `/portal/reports/${r1.data.id}`, { token: A.token, body: { status: 'resolved' } });
  ok(resolved.data.resolved_at, 'resolved_at terisi');
  const locAfter = await call('POST', `/v1/sdk/reports/${r1.data.id}/locations`, { headers: sdkH(pkTest), body: { lat: -6.2, lng: 106.8 } });
  ok(locAfter.data.accepted === false, 'live location berhenti setelah resolved');

  const r2 = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkTest, { 'Idempotency-Key': uuid() }), body: { category: 'medis' } });
  const cancel = await call('POST', `/v1/sdk/reports/${r2.data.id}/cancel`, { headers: sdkH(pkTest), body: { reason: 'salah pencet' } });
  ok(cancel.data.status === 'cancelled', 'pengguna batalkan laporan open');

  // secret key API
  const srv = await call('GET', '/v1/reports', { token: skTest });
  ok(srv.status === 200 && srv.data.data.length === 2, 'GET /v1/reports dengan secret key');

  // ---------------------------------------------------------------- dokumen + review admin
  const docs = ['nib', 'npwp', 'ktp_pic', 'akta'];
  const submitEarly = await call('POST', '/portal/onboarding/submit', { token: A.token });
  ok(submitEarly.status === 422 && submitEarly.data.error.details.missing.length === 5, 'submit ditolak bila dokumen belum lengkap');
  for (const d of docs) {
    const fd = new FormData();
    fd.set('doc_type', d);
    fd.set('file', PDF, `${d}.pdf`);
    const up = await call('POST', '/portal/onboarding/documents', { token: A.token, form: fd });
    ok(up.status === 201, `unggah dokumen ${d}`);
  }
  const fake = new FormData();
  fake.set('doc_type', 'sk_kemenkumham');
  fake.set('file', new Blob(['MZ bukan pdf']), 'sk.pdf');
  const bad = await call('POST', '/portal/onboarding/documents', { token: A.token, form: fake });
  ok(bad.status === 415, 'file .pdf palsu ditolak (cek magic bytes)');
  const fd = new FormData();
  fd.set('doc_type', 'sk_kemenkumham');
  fd.set('file', PDF, 'sk.pdf');
  await call('POST', '/portal/onboarding/documents', { token: A.token, form: fd });
  const sub = await call('POST', '/portal/onboarding/submit', { token: A.token });
  ok(sub.status === 200, 'ajukan ke review');
  const status = await call('GET', '/portal/onboarding/status', { token: A.token });
  ok(status.data.in_review && status.data.estimated_decision_by, 'halaman status: in_review + perkiraan waktu (F-22)');

  // admin (dibuat langsung di DB dengan TOTP diketahui)
  const secret = authenticator.generateSecret();
  const adminEmail = `reviewer.${rand(6)}@siagasos.local`;
  await pool.query(`INSERT INTO platform_admins (email, password_hash, totp_secret, role) VALUES ($1,$2,$3,'reviewer')`, [adminEmail, await hashPassword('admin-password-123'), secret]);
  const badTotp = await call('POST', '/admin/auth/login', { body: { email: adminEmail, password: 'admin-password-123', totp: '000000' } });
  ok(badTotp.status === 401, 'login admin tanpa TOTP valid ditolak');
  const adm = await call('POST', '/admin/auth/login', { body: { email: adminEmail, password: 'admin-password-123', totp: authenticator.generate(secret) } });
  ok(adm.status === 200, 'login admin + 2FA');
  const AT = adm.data.token as string;
  const queue = await call('GET', '/admin/accounts?status=pending_review', { token: AT });
  ok(queue.data.data.some((a: any) => a.id === A.accountId), 'akun muncul di antrean review (F-23)');
  const accDetail = await call('GET', `/admin/accounts/${A.accountId}`, { token: AT });
  const doc0 = accDetail.data.documents[0];
  const url = await call('GET', `/admin/documents/${doc0.id}/url`, { token: AT });
  const file = await fetch(url.data.url);
  ok(file.status === 200 && (await file.text()).startsWith('%PDF'), 'signed URL dokumen (didekripsi) bisa dibuka');
  const noReason = await call('POST', `/admin/accounts/${A.accountId}/decision`, { token: AT, body: { decision: 'rejected' } });
  ok(noReason.status === 422, 'alasan wajib untuk tolak');
  await call('PATCH', `/admin/documents/${doc0.id}`, { token: AT, body: { review_state: 'rejected', review_note: 'Scan buram' } });
  const rev = await call('POST', `/admin/accounts/${A.accountId}/decision`, { token: AT, body: { decision: 'needs_revision', reason: 'NIB buram, mohon unggah ulang' } });
  ok(rev.data.status === 'needs_revision', 'minta revisi');
  const st2 = await call('GET', '/portal/onboarding/status', { token: A.token });
  ok(st2.data.needs_reupload.includes(doc0.doc_type) && st2.data.note.includes('NIB'), 'PIC melihat catatan + dokumen yang perlu diunggah ulang (F-26)');
  const re = new FormData();
  re.set('doc_type', doc0.doc_type);
  re.set('file', PDF, 're.pdf');
  await call('POST', '/portal/onboarding/documents', { token: A.token, form: re });
  ok((await call('POST', '/portal/onboarding/submit', { token: A.token })).status === 200, 'ajukan ulang setelah revisi');
  const appr = await call('POST', `/admin/accounts/${A.accountId}/decision`, { token: AT, body: { decision: 'approved', checklist: { nib_oss: true, akta_ahu: true } } });
  ok(appr.data.status === 'approved', 'admin menyetujui');

  // ---------------------------------------------------------------- live
  const me2 = await call('GET', '/portal/me', { token: A.token });
  ok(me2.data.account.limited === false, 'akses penuh setelah approved');
  const live = await call('POST', `/portal/apps/${appId}/keys`, { token: A.token, body: { mode: 'live' } });
  ok(live.status === 201, 'kunci live dibuat');
  const pkLive = live.data.publishable.key as string;
  const noOrigin = await call('POST', '/v1/sdk/reports', { headers: { 'X-SOS-Key': pkLive, 'Idempotency-Key': uuid() }, body: payload });
  ok(noOrigin.status === 403 && noOrigin.data.error.code === 'origin_required', 'live tanpa Origin/Bundle ditolak');
  const liveRep = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }), body: { ...payload, reporter: { ref: 'user_999' } } });
  ok(liveRep.status === 201 && liveRep.data.mode === 'live', 'laporan live 201');
  for (let i = 0; i < 2; i++) await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }), body: { reporter: { ref: 'user_999' } } });
  const spam = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }), body: { reporter: { ref: 'user_999' } } });
  ok(spam.status === 429 && spam.data.error.code === 'reporter_rate_limited', 'rate limit 3 laporan / 10 menit per reporter_ref');

  // ---------------------------------------------------------------- isolasi tenant (RLS)
  const B = await registerCompany('Bravo');
  const bList = await call('GET', '/portal/reports', { token: B.token });
  ok(bList.data.data.length === 0, 'akun lain tidak melihat laporan akun pertama');
  const bGet = await call('GET', `/portal/reports/${r1.data.id}`, { token: B.token });
  ok(bGet.status === 404, 'akses laporan akun lain → 404');
  const bApp = await call('GET', `/portal/apps/${appId}`, { token: B.token });
  ok(bApp.status === 404, 'akses app akun lain → 404');
  const rlsRaw = await pool.query(`SELECT count(*)::int AS n FROM reports`);
  ok(rlsRaw.rows[0].n === 0, 'RLS: query tanpa konteks tenant melihat 0 baris');

  // ---------------------------------------------------------------- revoke + suspend
  const rot = await call('POST', `/portal/apps/${appId}/keys/${live.data.publishable.id}/revoke`, { token: A.token });
  ok(rot.status === 200, 'revoke kunci live');
  const afterRevoke = await call('GET', '/v1/sdk/config', { headers: sdkH(pkLive) });
  ok(afterRevoke.status === 401, 'kunci yang di-revoke ditolak (F-05)');
  const susp = await call('POST', `/admin/accounts/${A.accountId}/decision`, { token: AT, body: { decision: 'suspended', reason: 'Laporan palsu massal' } });
  ok(susp.data.status === 'suspended', 'admin membekukan akun');
  const afterSusp = await call('GET', '/v1/sdk/config', { headers: sdkH(pkTest) });
  ok(afterSusp.status === 401 || afterSusp.status === 403, 'semua kunci akun dibekukan ditolak (F-28)');
  const loginSusp = await call('POST', '/portal/auth/login', { body: { email: A.email, password: 'rahasia-sekali-123' } });
  ok(loginSusp.status === 403 && loginSusp.data.error.code === 'account_suspended', 'login akun dibekukan ditolak');

  console.log(`\n${passed} cek lolos`);
  await pool.end();
}

main().catch(async (e) => {
  console.error(e.message ?? e);
  await pool.end();
  process.exit(1);
});
