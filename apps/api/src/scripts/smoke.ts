/**
 * Smoke test end-to-end M1 terhadap API yang sedang berjalan (pnpm dev:api).
 * Membuat data baru setiap run (NIB acak). Jangan jalankan ke production.
 *   pnpm smoke            # default http://localhost:4000
 */
import { authenticator } from 'otplib';
import { pool, withPlatform } from '../db.js';
import { runMaintenance } from '../lib/maintenance.js';
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
  // Smoke memanggil /v1/sdk lebih dari 60×/menit dari satu IP: kena limit umum per menit → tunggu jendela berikutnya, ulang sekali.
  if (res.status === 429 && data?.error?.code === 'rate_limited' && data.error.details?.window_s <= 60 && !opts.form) {
    await new Promise((r) => setTimeout(r, 60_500 - (Date.now() % 60_000)));
    return call(method, path, opts);
  }
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
    // media pending yang tidak pernah di-complete dibersihkan job maintenance (setelah URL upload + 1 jam)
    await withPlatform((c) => c.query(`UPDATE report_media SET created_at = now() - interval '3 hours' WHERE id = $1`, [ghost.data.media.id]));
    let mt = await runMaintenance();
    for (let i = 0; mt.skipped && i < 5; i++) { await new Promise((r) => setTimeout(r, 500)); mt = await runMaintenance(); }
    const left = await withPlatform((c) => c.query(`SELECT status FROM report_media WHERE report_id = $1`, [r1.data.id]));
    ok(mt.mediaRemoved >= 1 && left.rows.length === 1 && left.rows[0].status === 'ready', 'media: pending basi dibersihkan, media ready tetap');
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
  // Catatan pelapor (keterangan rekaman TKP): masuk timeline sebagai note dari pelapor.
  const badNote = await call('POST', `/v1/sdk/reports/${r2.data.id}/notes`, { headers: sdkH(pkTest), body: { note: '  ' } });
  ok(badNote.status === 422 && badNote.data.error.code === 'invalid_note', 'catatan pelapor kosong ditolak');
  const note = await call('POST', `/v1/sdk/reports/${r2.data.id}/notes`, { headers: sdkH(pkTest), body: { note: 'Orang mencurigakan di depan toko' } });
  const noted = await call('GET', `/portal/reports/${r2.data.id}`, { token: A.token });
  const ev = noted.data.timeline.find((e: any) => e.type === 'note');
  ok(note.status === 201 && note.data.status === 'open' && ev?.actor_kind === 'reporter' && ev.note === 'Orang mencurigakan di depan toko',
    'catatan pelapor masuk timeline (actor reporter, status tetap)');
  const noteClosed = await call('POST', `/v1/sdk/reports/${r1.data.id}/notes`, { headers: sdkH(pkTest), body: { note: 'telat' } });
  ok(noteClosed.status === 409, 'catatan ke laporan yang sudah ditutup ditolak');
  const cancel = await call('POST', `/v1/sdk/reports/${r2.data.id}/cancel`, { headers: sdkH(pkTest), body: { reason: 'salah pencet' } });
  ok(cancel.data.status === 'cancelled', 'pengguna batalkan laporan open');

  // Laporan pengaduan (menu tombol melayang): uraian wajib, tanpa lokasi live, terlihat sebagai kind=pengaduan
  const pgNoMsg = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkTest, { 'Idempotency-Key': uuid() }), body: { kind: 'pengaduan', category: 'kebisingan' } });
  ok(pgNoMsg.status === 422, 'pengaduan tanpa uraian → 422');
  const pg = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkTest, { 'Idempotency-Key': uuid() }),
    body: { kind: 'pengaduan', category: 'kebisingan', message: 'Hajatan sampai jam 2 pagi', location: { lat: -6.2, lng: 106.8 }, reporter: { ref: 'user_123' } } });
  ok(pg.status === 201 && pg.data.kind === 'pengaduan', 'POST pengaduan → 201, kind=pengaduan (kuota terpisah dari SOS)');
  const pgLoc = await call('POST', `/v1/sdk/reports/${pg.data.id}/locations`, { headers: sdkH(pkTest), body: { lat: -6.21, lng: 106.81 } });
  ok(pgLoc.data.accepted === false, 'pengaduan tidak menerima lokasi live');
  const cfgPg = await call('GET', '/v1/sdk/config', { headers: sdkH(pkTest) });
  ok(Array.isArray(cfgPg.data.complaint_categories) && cfgPg.data.complaint_categories.length > 0, '/v1/sdk/config berisi complaint_categories');

  // secret key API
  const srv = await call('GET', '/v1/reports', { token: skTest });
  ok(srv.status === 200 && srv.data.data.length === 3, 'GET /v1/reports dengan secret key');
  const srvSos = await call('GET', '/v1/reports?kind=sos', { token: skTest });
  ok(srvSos.data.data.length === 2 && srvSos.data.data.every((r: any) => r.kind === 'sos'), 'GET /v1/reports?kind=sos memisahkan SOS dari pengaduan');

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
  // Penerima SOS (WhatsApp) diatur di portal; nomor dinormalisasi ke 62xx.
  const badRcpt = await call('POST', `/portal/apps/${appId}/recipients`, { token: A.token, body: { name: 'Pos Satpam', phone: '12345' } });
  ok(badRcpt.status === 422, 'penerima SOS: nomor tidak valid ditolak');
  const rcpt = await call('POST', `/portal/apps/${appId}/recipients`, { token: A.token, body: { name: 'Pos Satpam', phone: '0800-1111-2222' } });
  ok(rcpt.status === 201 && rcpt.data.phone === '6280011112222' && rcpt.data.source_id === null, 'penerima SOS dibuat (nomor jadi 62xx, semua source)');
  const dupRcpt = await call('POST', `/portal/apps/${appId}/recipients`, { token: A.token, body: { name: 'Sama', phone: '+6280011112222' } });
  ok(dupRcpt.status === 409, 'penerima SOS: nomor ganda di cakupan sama ditolak');
  const tmp = await call('POST', `/portal/apps/${appId}/recipients`, { token: A.token, body: { name: 'Sementara', phone: '080099990000' } });
  ok((await call('DELETE', `/portal/apps/${appId}/recipients/${tmp.data.id}`, { token: A.token })).status === 204, 'penerima SOS dihapus');
  const badContacts = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }),
    body: { ...payload, emergency_contacts: Array.from({ length: 6 }, (_, i) => ({ phone: `0800000000${i}` })) } });
  ok(badContacts.status === 422, 'kontak darurat: >5 nomor ditolak');
  const badPhone = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }), body: { ...payload, emergency_contacts: [{ phone: '123' }] } });
  ok(badPhone.status === 422, 'kontak darurat: nomor tidak valid ditolak');

  const liveRep = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }), body: { ...payload, reporter: { ref: 'user_999' },
    emergency_contacts: [{ name: 'Istri', phone: '0800 3333 4444' }, { name: 'Dobel', phone: '6280011112222' }] } });
  ok(liveRep.status === 201 && liveRep.data.mode === 'live', 'laporan live 201');
  // Sejak Polmas Keamanan (docs/POLMAS_KEAMANAN.md §9) Emergency tidak lagi mengirim WA (kecuali SOS_WHATSAPP=true).
  await new Promise((r) => setTimeout(r, 800));
  const noWa = await call('GET', `/portal/reports/${liveRep.data.id}`, { token: A.token });
  ok(!noWa.data.timeline.some((e: any) => e.type === 'whatsapp'), 'SOS live tidak lagi mengirim WhatsApp (diganti push Polmas Keamanan)');
  // Detail untuk "Riwayat laporan" di perangkat: timeline + ringkasan WA, tanpa nomor HP pelapor / penerima.
  const det = await call('GET', `/v1/sdk/reports/${liveRep.data.id}/detail`, { headers: sdkH(pkLive) });
  const detText = JSON.stringify(det.data);
  ok(det.status === 200 && det.data.location && Array.isArray(det.data.timeline) && det.data.timeline[0]?.type === 'created' && Array.isArray(det.data.media),
    'detail laporan untuk riwayat di perangkat (lokasi, timeline, media)');
  ok(!detText.includes('6280011112222') && !detText.includes('6280033334444') && !('reporter' in det.data),
    'detail perangkat tidak membuka nomor penerima SOS / kontak / data pelapor');
  // ---------------------------------------------------------------- responder (satpam login dari Nomor Darurat)
  const guardPhone = '6280055556666';
  const otpNo = await call('POST', '/v1/sdk/responder/otp', { headers: sdkH(pkLive), body: { phone: '0800 5555 6666' } });
  ok(otpNo.status === 404 && otpNo.data.error.code === 'responder_not_registered', 'login satpam: nomor di luar Nomor Darurat ditolak');
  const putC = await call('PUT', '/v1/sdk/contacts', { headers: sdkH(pkLive), body: { reporter: { ref: 'kasir_rsp', name: 'Kasir Satu' },
    contacts: [{ name: 'Pak Satpam', role: 'Satpam', phone: '0800-5555-6666', active: true }, { name: 'Adik', phone: '080077778888', active: false }] } });
  ok(putC.status === 200 && putC.data.count === 2, 'Nomor Darurat disinkronkan ke server');
  const getC = await call('GET', '/v1/sdk/contacts?reporter_ref=kasir_rsp', { headers: sdkH(pkLive) });
  ok(getC.data.contacts.length === 2 && getC.data.contacts[0].phone === guardPhone, 'Nomor Darurat dibaca ulang (62xx, aktif dulu)');
  // ---------------------------------------------------------------- wilayah (isian Bhabinkamtibmas)
  const prov = await call('GET', '/v1/sdk/regions', { headers: sdkH(pkLive) });
  ok(prov.status === 200 && prov.data.regions.length >= 38 && prov.data.regions.some((r: { code: string; name: string }) => r.code === '32' && r.name === 'Jawa Barat'), 'daftar provinsi');
  const kec = await call('GET', '/v1/sdk/regions?parent=32.73', { headers: sdkH(pkLive) });
  ok(kec.status === 200 && kec.data.regions.some((r: { code: string }) => r.code === '32.73.02') && kec.data.regions.every((r: { code: string }) => /^32\.73\.\d{2}$/.test(r.code)), 'kecamatan Kota Bandung (anak langsung saja)');
  const badParent = await call('GET', '/v1/sdk/regions?parent=x;1', { headers: sdkH(pkLive) });
  ok(badParent.status === 422, 'kode induk tidak valid ditolak');
  const badRev = await call('GET', '/v1/sdk/regions/reverse?lat=200&lng=0', { headers: sdkH(pkLive) });
  ok(badRev.status === 422, 'reverse geocode: koordinat tidak valid ditolak');
  const area = { province: { code: '32', name: 'Jawa Barat' }, regency: { code: '32.73', name: 'Kota Bandung' }, district: { code: '32.73.02', name: 'Coblong' }, village: null };
  const putArea = await call('PUT', '/v1/sdk/contacts', { headers: sdkH(pkLive), body: { reporter: { ref: 'kasir_area' },
    contacts: [{ name: 'Aiptu Budi', role: 'Bhabinkamtibmas', phone: '0800 1212 3434', active: true, area }] } });
  const getArea = await call('GET', '/v1/sdk/contacts?reporter_ref=kasir_area', { headers: sdkH(pkLive) });
  ok(putArea.status === 200 && getArea.data.contacts[0].area?.district?.code === '32.73.02', 'wilayah tugas kontak disimpan & dibaca ulang');
  const badArea = await call('PUT', '/v1/sdk/contacts', { headers: sdkH(pkLive), body: { reporter: { ref: 'kasir_area' },
    contacts: [{ name: 'X', phone: '0800 1212 3434', area: { province: { code: 'abc', name: 'X' } } }] } });
  ok(badArea.status === 422, 'kode wilayah kontak tidak valid ditolak');
  await call('PUT', '/v1/sdk/contacts', { headers: sdkH(pkLive), body: { reporter: { ref: 'kasir_area' }, contacts: [] } });
  const otp = await call('POST', '/v1/sdk/responder/otp', { headers: sdkH(pkLive), body: { phone: guardPhone } });
  ok(otp.status === 200 && /^\d{6}$/.test(otp.data.dev_code) && otp.data.sent === false, 'OTP satpam dibuat (nomor uji 0800: tidak dikirim WA, kode dev)');
  const badOtp = await call('POST', '/v1/sdk/responder/verify', { headers: sdkH(pkLive), body: { phone: guardPhone, code: otp.data.dev_code === '000000' ? '111111' : '000000' } });
  ok(badOtp.status === 422 && badOtp.data.error.code === 'otp_invalid', 'OTP salah ditolak');
  const ver = await call('POST', '/v1/sdk/responder/verify', { headers: sdkH(pkLive),
    body: { phone: guardPhone, code: otp.data.dev_code, device: { platform: 'android', fcm_token: 'smoke-fcm-token-123456' } } });
  ok(ver.status === 201 && String(ver.data.token).startsWith('rsp_') && ver.data.responder.name === 'Pak Satpam (Satpam)', 'satpam login → token sesi');
  const reuse = await call('POST', '/v1/sdk/responder/verify', { headers: sdkH(pkLive), body: { phone: guardPhone, code: otp.data.dev_code } });
  ok(reuse.status === 422, 'OTP sekali pakai');
  const direct = await call('POST', '/v1/sdk/responder/login', { headers: sdkH(pkLive), body: { phone: '0800-5555-6666', device: { platform: 'android' } } });
  ok(direct.status === 201 && String(direct.data.token).startsWith('rsp_'), 'satpam login langsung tanpa OTP');
  const directNo = await call('POST', '/v1/sdk/responder/login', { headers: sdkH(pkLive), body: { phone: '080011110000' } });
  ok(directNo.status === 404 && directNo.data.error.code === 'responder_not_registered', 'login langsung: nomor di luar Nomor Darurat ditolak');
  const rH = sdkH(pkLive, { 'X-SOS-Responder': ver.data.token });
  const noTok = await call('GET', '/v1/sdk/responder/reports', { headers: sdkH(pkLive) });
  ok(noTok.status === 401, 'endpoint satpam tanpa token ditolak');
  const guardSos = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }),
    body: { ...payload, reporter: { ref: 'kasir_rsp', name: 'Kasir Satu' }, emergency_contacts: [{ name: 'Pak Satpam (Satpam)', phone: guardPhone }] } });
  ok(guardSos.status === 201, 'SOS kasir yang mencantumkan nomor satpam');
  let push: string[] = [];
  for (let i = 0; i < 20 && !push.length; i++) {
    await new Promise((r) => setTimeout(r, 100));
    const d = await call('GET', `/portal/reports/${guardSos.data.id}`, { token: A.token });
    push = d.data.timeline.filter((e: any) => e.type === 'push').map((e: any) => e.note as string);
  }
  ok(push.length === 1 && /1 HP satpam/.test(push[0]!), 'SOS → push alarm ke HP satpam tercatat di timeline');
  const rList = await call('GET', '/v1/sdk/responder/reports', { headers: rH });
  ok(rList.data.data.length === 1 && rList.data.data[0].id === guardSos.data.id && rList.data.data[0].reporter_name === 'Kasir Satu',
    'satpam hanya melihat SOS yang mencantumkan nomornya');
  const other = await call('GET', `/v1/sdk/responder/reports/${liveRep.data.id}`, { headers: rH });
  ok(other.status === 404, 'SOS yang tidak mencantumkan nomornya → 404');
  const gAck = await call('POST', `/v1/sdk/responder/reports/${guardSos.data.id}/status`, { headers: rH, body: { status: 'acknowledged' } });
  ok(gAck.status === 200 && gAck.data.status === 'acknowledged', 'satpam menanggapi SOS');
  const ackTl = await call('GET', `/portal/reports/${guardSos.data.id}`, { token: A.token });
  ok(ackTl.data.timeline.some((e: any) => e.actor_kind === 'responder' && e.to_status === 'acknowledged'), 'tanggapan satpam tercatat (actor responder)');
  await call('PUT', '/v1/sdk/contacts', { headers: sdkH(pkLive), body: { reporter: { ref: 'kasir_rsp' }, contacts: [] } });
  const gone = await call('GET', '/v1/sdk/responder/me', { headers: rH });
  ok(gone.status === 401 && gone.data.error.code === 'responder_not_registered', 'nomor dihapus dari Nomor Darurat → sesi satpam berakhir');

  // ---------------------------------------------------------------- Polmas Keamanan: app penerima Nomor Darurat
  const pkPhone = `62800${String(Math.floor(Math.random() * 1e7)).padStart(7, '0')}`;
  const pkNo = await call('POST', '/v1/pk/auth/check', { body: { phone: pkPhone } });
  ok(pkNo.status === 404 && pkNo.data.error.code === 'phone_not_registered', 'PK: nomor di luar Nomor Darurat ditolak');
  await call('PUT', '/v1/sdk/contacts', { headers: sdkH(pkLive), body: { reporter: { ref: 'kasir_pk', name: 'Kasir PK' },
    contacts: [{ name: 'Pak Joko', role: 'Satpam', phone: pkPhone, active: true }] } });
  const pkChk = await call('POST', '/v1/pk/auth/check', { body: { phone: '0' + pkPhone.slice(2) } });
  ok(pkChk.status === 200 && pkChk.data.has_password === false && pkChk.data.contacts[0]?.role === 'Satpam',
    'PK: nomor dari Nomor Darurat dikenali (format 08…), login pertama = buat password');
  const pkShort = await call('POST', '/v1/pk/auth/setup', { body: { phone: pkPhone, password: 'pendek' } });
  ok(pkShort.status === 422, 'PK: password < 8 ditolak');
  const pkSetup = await call('POST', '/v1/pk/auth/setup', { body: { phone: pkPhone, password: 'satpam-rahasia-1', device: { platform: 'android' } } });
  ok(pkSetup.status === 201 && /^pks_/.test(pkSetup.data.token) && pkSetup.data.me.role.role === 'penerima' && pkSetup.data.me.can_respond === true,
    'PK: buat password → sesi, peran penerima (turunan Nomor Darurat)');
  const pkAgain = await call('POST', '/v1/pk/auth/setup', { body: { phone: pkPhone, password: 'orang-lain-123' } });
  ok(pkAgain.status === 409, 'PK: nomor yang sudah punya password tidak bisa diklaim ulang');
  const pkBad = await call('POST', '/v1/pk/auth/login', { body: { phone: pkPhone, password: 'salah-password' } });
  ok(pkBad.status === 401 && pkBad.data.error.code === 'invalid_password', 'PK: password salah ditolak');
  const pkLogin = await call('POST', '/v1/pk/auth/login', { body: { phone: pkPhone, password: 'satpam-rahasia-1' } });
  ok(pkLogin.status === 201, 'PK: login nomor + password');
  const pkT = pkLogin.data.token as string;
  ok(typeof pkLogin.data.me.server_push === 'boolean', 'PK: /me memberi tahu apakah server bisa mengirim push SOS');
  const pkStatus = await call('GET', '/v1/pk/status');
  ok(pkStatus.status === 200 && pkStatus.data.fcm_channel === 'polmas_sos_v2' && !JSON.stringify(pkStatus.data).includes('private_key'),
    'PK: /status publik (push siap, project Firebase) tanpa rahasia');
  const pkAnon = await call('GET', '/v1/pk/me');
  ok(pkAnon.status === 401, 'PK: tanpa token ditolak');
  const pkDev = await call('POST', '/v1/pk/me/device', { token: pkT, body: { fcm_token: `smoke-pk-fcm-${pkPhone}`, platform: 'android' } });
  ok(pkDev.status === 204, 'PK: token FCM perangkat terdaftar');
  const pkSos = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }),
    body: { ...payload, reporter: { ref: 'kasir_pk', name: 'Kasir PK', phone: '0800 7777 8888' }, emergency_contacts: [{ name: 'Pak Joko (Satpam)', phone: pkPhone }] } });
  ok(pkSos.status === 201, 'PK: kios mengirim SOS yang memanggil nomor satpam');
  let pkPush: string[] = [];
  for (let i = 0; i < 20 && !pkPush.length; i++) {
    await new Promise((r) => setTimeout(r, 100));
    const d = await call('GET', `/portal/reports/${pkSos.data.id}`, { token: A.token });
    pkPush = d.data.timeline.filter((e: any) => e.type === 'push' && /Polmas Keamanan/.test(e.note ?? '')).map((e: any) => e.note as string);
  }
  // Token smoke palsu: tanpa PK_FCM_SERVICE_ACCOUNT tercatat stub (1 terkirim), dengan kredensial asli FCM menolaknya (0).
  ok(pkPush.length === 1 && /push SOS ke [01] dari 1 penerima/.test(pkPush[0]!), 'PK: SOS → push FCM ke HP penerima Polmas Keamanan, tercatat di timeline');
  const inbox = await call('GET', '/v1/pk/inbox', { token: pkT });
  ok(inbox.status === 200 && inbox.data.calls.some((c: any) => c.id === pkSos.data.id), 'PK: SOS muncul sebagai panggilan masuk (app sumber tanpa polmas_source)');
  ok(typeof inbox.data.open_reports === 'number', 'PK: inbox membawa jumlah laporan belum ditanggapi (badge Laporan)');
  const pkOther = await call('GET', `/v1/pk/reports/${liveRep.data.id}`, { token: pkT });
  ok(pkOther.status === 404, 'PK: SOS yang tidak memanggil nomornya → 404');
  const pkDet = await call('GET', `/v1/pk/reports/${pkSos.data.id}`, { token: pkT });
  ok(pkDet.status === 200 && pkDet.data.actions.includes('terima') && pkDet.data.reporter.phone === '0800 7777 8888' && pkDet.data.is_contact === true,
    'PK: detail lengkap (nomor pelapor terlihat oleh penerima) + aksi tersedia');
  const pkAck = await call('POST', `/v1/pk/reports/${pkSos.data.id}/responses`, { token: pkT, body: { action: 'terima' } });
  ok(pkAck.status === 201 && pkAck.data.status === 'diterima', 'PK: satpam menerima SOS');
  const sdkSt = await call('GET', `/v1/sdk/reports/${pkSos.data.id}`, { headers: sdkH(pkLive) });
  ok(sdkSt.data.status === 'acknowledged' && /Pak Joko/.test(sdkSt.data.status_message ?? ''), 'PK: status & pesan kembali ke SDK pelapor');
  const pkCall = await call('POST', `/v1/pk/reports/${pkSos.data.id}/call`, { token: pkT, body: { action: 'accepted' } });
  const inbox2 = await call('GET', '/v1/pk/inbox', { token: pkT });
  ok(pkCall.status === 204 && !inbox2.data.calls.some((c: any) => c.id === pkSos.data.id), 'PK: panggilan yang dijawab tidak berdering lagi');
  await call('POST', `/v1/pk/reports/${pkSos.data.id}/responses`, { token: pkT, body: { action: 'tangani', note: 'Menuju kios' } });
  const pkDone = await call('POST', `/v1/pk/reports/${pkSos.data.id}/responses`, { token: pkT, body: { action: 'selesai' } });
  const pkLate = await call('POST', `/v1/pk/reports/${pkSos.data.id}/responses`, { token: pkT, body: { action: 'catatan', note: 'x' } });
  ok(pkDone.data.status === 'selesai' && pkLate.status === 409, 'PK: tangani → selesai, laporan tertutup tidak bisa ditanggapi lagi');
  const pkTl = await call('GET', `/portal/reports/${pkSos.data.id}`, { token: A.token });
  ok(pkTl.data.timeline.filter((e: any) => e.actor_kind === 'responder').length >= 3, 'PK: tanggapan tercatat di timeline dashboard tenant');
  const pkHist = await call('GET', '/v1/pk/history?scope=me', { token: pkT });
  ok(pkHist.data.items.some((r: any) => r.id === pkSos.data.id && r.last_response?.action === 'selesai'), 'PK: riwayat Saya memuat SOS + tanggapan terakhir');
  const pkCnt = await call('GET', '/v1/pk/reports?scope=me&status=selesai', { token: pkT });
  ok(pkCnt.data.counts?.selesai >= 1 && pkCnt.data.counts.semua >= pkCnt.data.counts.selesai && pkCnt.data.items.every((r: any) => r.status === 'selesai'),
    'PK: daftar membawa jumlah per status (chip) yang mengabaikan filter status');
  const pkAn = await call('GET', '/v1/pk/analytics/summary?period=7d', { token: pkT });
  const pkEv = await call('GET', '/v1/pk/analytics/evaluation?period=7d', { token: pkT });
  ok(pkAn.status === 200 && pkAn.data.trend.length === 7 && pkAn.data.totals.sos >= 1 && pkEv.status === 200 && pkEv.data.current.selesai >= 1,
    'PK: analisa (tren 7 hari) & evaluasi menghitung SOS penerima');
  ok(/^SOS-\d{4}-[0-9A-F]{4}$/.test(pkDet.data.code ?? ''), 'PK: nomor tiket pendek di detail laporan');
  ok(pkAn.data.funnel?.selesai >= 1 && pkAn.data.officers?.some((o: any) => o.is_me && o.selesai >= 1)
    && typeof pkAn.data.totals.median_response_s === 'number' && Array.isArray(pkAn.data.by_ecosystem) && 'patrol_hint' in pkAn.data,
    'PK: analitik mockup (alur status, per petugas, median respons, ekosistem, saran patroli)');
  ok(pkAn.data.by_ecosystem.every((e: any) => typeof e.label === 'string'), 'PK: ekosistem selalu berlabel (app tanpa pilar → nama app)');
  const pkAnSrc = await call('GET', '/v1/pk/analytics/summary?period=7d&source=umkm', { token: pkT });
  const pkAnBad = await call('GET', '/v1/pk/analytics/summary?period=7d&source=xx', { token: pkT });
  ok(pkAnSrc.status === 200 && pkAnSrc.data.source === 'umkm' && pkAnBad.status === 422, 'PK: filter ekosistem di analitik (nilai asing ditolak)');
  const pkStats = await call('GET', '/v1/pk/me/stats', { token: pkT });
  ok(pkStats.status === 200 && pkStats.data.handled >= 1 && pkStats.data.resolved >= 1, 'PK: kinerja saya (Profil) menghitung SOS yang saya selesaikan');
  await call('POST', '/v1/pk/me/device', { token: pkT, body: { fcm_token: `smoke-pk-fcm-${pkPhone}`, platform: 'android', device_name: 'Samsung SM-A546E' } });
  const pkDevs = await call('GET', '/v1/pk/me/devices', { token: pkT });
  const myDev = pkDevs.data.items?.find((d: any) => d.token_tail === pkPhone.slice(-6));
  ok(myDev?.device_name === 'Samsung SM-A546E' && !('fcm_token' in myDev), 'PK: daftar perangkat (nama HP, token tidak dibocorkan)');
  const pkPwBad = await call('POST', '/v1/pk/me/password', { token: pkT, body: { current_password: 'salah', new_password: 'satpam-baru-123' } });
  const pkPw = await call('POST', '/v1/pk/me/password', { token: pkT, body: { current_password: 'satpam-rahasia-1', new_password: 'satpam-baru-123' } });
  const pkOldSess = await call('GET', '/v1/pk/me', { token: pkSetup.data.token });
  const pkStill = await call('GET', '/v1/pk/me', { token: pkT });
  ok(pkPwBad.status === 401 && pkPw.status === 204 && pkOldSess.status === 401 && pkStill.status === 200,
    'PK: ubah kata sandi (lama wajib benar, sesi lain dicabut, sesi ini tetap)');
  const pkRmDev = await call('POST', `/v1/pk/me/devices/${myDev?.id}/remove`, { token: pkT });
  ok(pkRmDev.status === 204, 'PK: lupakan perangkat dari Profil');
  await call('PUT', '/v1/sdk/contacts', { headers: sdkH(pkLive), body: { reporter: { ref: 'kasir_pk' }, contacts: [] } });
  await call('POST', '/v1/pk/auth/logout', { token: pkT });
  await call('POST', '/v1/pk/auth/logout', { token: pkSetup.data.token });
  const pkGone = await call('POST', '/v1/pk/auth/login', { body: { phone: pkPhone, password: 'satpam-baru-123' } });
  ok(pkGone.status === 403 && pkGone.data.error.code === 'no_role', 'PK: nomor dihapus dari Nomor Darurat → tidak bisa login lagi');

  for (let i = 0; i < 2; i++) await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }), body: { reporter: { ref: 'user_999' } } });
  const spam = await call('POST', '/v1/sdk/reports', { headers: sdkH(pkLive, { 'Idempotency-Key': uuid() }), body: { reporter: { ref: 'user_999' } } });
  ok(spam.status === 429 && spam.data.error.code === 'reporter_rate_limited', 'rate limit 3 laporan / 10 menit per reporter_ref');

  // ---------------------------------------------------------------- retensi & hapus data pengguna (UU PDP)
  const skLive = live.data.secret.key as string;
  const badRet = await call('PATCH', `/portal/apps/${appId}`, { token: A.token, body: { retention_days: 7 } });
  ok(badRet.status === 422, 'retensi < 30 hari ditolak');
  const setRet = await call('PATCH', `/portal/apps/${appId}`, { token: A.token, body: { retention_days: 30 } });
  ok(setRet.status === 200 && setRet.data.retention_days === 30, 'retensi laporan per app disimpan');
  const mk = async (key: string, ref: string, close: boolean) => {
    const r = await call('POST', '/v1/sdk/reports', { headers: sdkH(key, { 'Idempotency-Key': uuid() }), body: { reporter: { ref } } });
    if (close) await call('POST', `/v1/sdk/reports/${r.data.id}/cancel`, { headers: sdkH(key), body: {} });
    return r.data.id as string;
  };
  const oldLive = await mk(pkLive, 'ret_user', true);
  const recentLive = await mk(pkLive, 'ret_user', true);
  const openLive = await mk(pkLive, 'ret_user', false);
  const oldTest = await mk(pkTest, 'ret_user', true);
  await withPlatform(async (c) => {
    await c.query(`UPDATE reports SET resolved_at = now() - interval '31 days' WHERE id = ANY($1::uuid[])`, [[oldLive, oldTest]]);
    await c.query(`UPDATE reports SET resolved_at = now() - interval '10 days' WHERE id = $1`, [recentLive]);
    await c.query(`UPDATE reports SET created_at = now() - interval '90 days' WHERE id = $1`, [openLive]);
  });
  let rt = await runMaintenance();
  for (let i = 0; rt.skipped && i < 5; i++) { await new Promise((r) => setTimeout(r, 500)); rt = await runMaintenance(); }
  const kept = await withPlatform((c) => c.query(`SELECT id FROM reports WHERE id = ANY($1::uuid[])`, [[oldLive, recentLive, openLive, oldTest]]));
  const keptIds = kept.rows.map((r: any) => r.id).sort();
  ok(JSON.stringify(keptIds) === JSON.stringify([recentLive, openLive].sort()),
    'retensi: laporan tertutup > 30 hari (live & test) dihapus, yang baru ditutup & yang masih aktif tetap');

  const eraseTest = await call('DELETE', '/v1/reporters/user_999', { token: skTest });
  ok(eraseTest.status === 200 && eraseTest.data.deleted.reports === 0, 'hapus data pengguna dengan kunci test tidak menyentuh laporan live');
  await call('PUT', '/v1/sdk/contacts', { headers: sdkH(pkLive), body: { reporter: { ref: 'user_999' }, contacts: [{ name: 'Adik', phone: '0800 7777 8888' }] } });
  const erase = await call('DELETE', '/v1/reporters/user_999', { token: skLive });
  ok(erase.status === 200 && erase.data.deleted.reports === 3 && erase.data.deleted.emergency_contacts === 1, 'DELETE /v1/reporters/:ref menghapus semua laporan pengguna (3 live + Nomor Darurat)');
  const left999 = await withPlatform((c) => c.query(
    `SELECT (SELECT count(*) FROM reports WHERE reporter_ref = 'user_999' AND app_id = $1)::int AS r,
            (SELECT count(*) FROM emergency_contacts WHERE reporter_ref = 'user_999' AND app_id = $1)::int AS c`, [appId]));
  ok(left999.rows[0].r === 0 && left999.rows[0].c === 0, 'data pengguna terhapus: laporan + Nomor Darurat');

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
