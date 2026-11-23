import { useState, type FormEvent, type KeyboardEvent } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, ArrowsClockwise, Key, Plus, Prohibit, Trash, WhatsappLogo, X } from '@phosphor-icons/react';
import { DEFAULT_CATEGORIES, DEFAULT_COMPLAINT_CATEGORIES } from '@siagasos/shared';
import { api, ApiError } from '../lib/api';
import { useAuth } from '../lib/auth';
import { catLabel, fmtAgo, fmtDate } from '../lib/format';
import type { ApiKey, App, SdkConfig } from '../lib/types';
import { TestModeNotice } from '../components/Layout';
import { Alert, Badge, Button, CopyButton, Empty, Field, KeyBox, Modal, Spinner, TextField, useLoad, useToast } from '../components/ui';
import { NewKeysModal, type NewKeys } from './Apps';

type Tab = 'keys' | 'settings' | 'recipients' | 'sources' | 'webhooks';
const TABS: [Tab, string][] = [['keys', 'Kunci API'], ['settings', 'Pengaturan'], ['recipients', 'Penerima SOS'], ['sources', 'Source'], ['webhooks', 'Log webhook']];

export function AppDetailPage() {
  const id = useParams().id!;
  const { data: app, setData, loading, error, reload } = useLoad(() => api<App>(`/portal/apps/${id}`), [id]);
  const [tab, setTab] = useState<Tab>('keys');

  if (loading && !app) return <div className="page"><Spinner /></div>;
  if (error || !app) return <div className="page"><Alert tone="error">{error}</Alert></div>;

  return (
    <div className="page">
      <div className="stack-sm">
        <Link to="/apps" className="small row" style={{ gap: 4 }}><ArrowLeft size={14} />Semua app</Link>
        <div className="page-head">
          <div>
            <h1>{app.name}</h1>
            <p className="mono small">{app.id}</p>
          </div>
          {app.disabled && <Badge tone="sos">Dinonaktifkan admin{app.disabled_reason ? `: ${app.disabled_reason}` : ''}</Badge>}
        </div>
      </div>
      <TestModeNotice />
      <div className="tabs" role="tablist">
        {TABS.map(([k, label]) => (
          <button key={k} role="tab" id={`tab-${k}`} aria-controls={`panel-${k}`} aria-selected={tab === k} className="tab" onClick={() => setTab(k)}>{label}</button>
        ))}
      </div>
      <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`}>
        {tab === 'keys' && <KeysTab app={app} reload={reload} />}
        {tab === 'settings' && <SettingsTab app={app} onSaved={(a) => setData({ ...a, keys: app.keys })} />}
        {tab === 'recipients' && <RecipientsTab app={app} />}
        {tab === 'sources' && <SourcesTab app={app} />}
        {tab === 'webhooks' && <WebhooksTab app={app} />}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- kunci
function KeysTab({ app, reload }: { app: App; reload: () => Promise<void> }) {
  const { me, can } = useAuth();
  const toast = useToast();
  const [newKeys, setNewKeys] = useState<Record<string, NewKeys> | null>(null);
  const [rotating, setRotating] = useState<ApiKey | null>(null);
  const [revoking, setRevoking] = useState<ApiKey | null>(null);
  const [rotated, setRotated] = useState<ApiKey | null>(null);
  const manage = can('owner', 'admin');
  const limited = !!me?.account.limited;
  const hasLive = app.keys.some((k) => k.mode === 'live' && k.active);

  async function createPair(mode: 'live' | 'test') {
    try {
      const r = await api<NewKeys>(`/portal/apps/${app.id}/keys`, { body: { mode } });
      setNewKeys({ [mode]: r });
      void reload();
    } catch (e) { toast((e as Error).message, 'error'); }
  }

  const groups = (['live', 'test'] as const).map((mode) => ({ mode, keys: app.keys.filter((k) => k.mode === mode) }));

  return (
    <div className="stack">
      {groups.map(({ mode, keys }) => (
        <div className="card" key={mode}>
          <div className="card-head">
            <div>
              <h2 className="row"><Badge tone={mode === 'live' ? 'ok' : 'test'}>{mode.toUpperCase()}</Badge>{mode === 'live' ? 'Kunci produksi' : 'Kunci test'}</h2>
              <p>{mode === 'live' ? 'Laporan live memicu notifikasi ke responder.' : 'Laporan test tidak memicu notifikasi; maks. 50/hari.'}</p>
            </div>
            {manage && (
              <Button size="sm" onClick={() => createPair(mode)} disabled={mode === 'live' && limited}
                title={mode === 'live' && limited ? 'Tersedia setelah perusahaan disetujui' : undefined}>
                <Plus size={14} />Pasangan kunci baru
              </Button>
            )}
          </div>
          {mode === 'live' && limited && !hasLive ? (
            <div className="card-body"><p className="small muted">Kunci live aktif setelah perusahaan disetujui. <Link to="/onboarding">Lihat status verifikasi</Link>.</p></div>
          ) : !keys.length ? (
            <Empty icon={<Key size={32} />} title="Belum ada kunci" />
          ) : (
            <div className="table-wrap">
              <table className="table">
                <thead><tr><th>Jenis</th><th>Kunci</th><th>Terakhir dipakai</th><th>Status</th><th /></tr></thead>
                <tbody>
                  {keys.map((k) => (
                    <tr key={k.id} style={{ opacity: k.active ? 1 : 0.55 }}>
                      <td><strong>{k.kind === 'publishable' ? 'Publishable' : 'Secret'}</strong></td>
                      <td style={{ maxWidth: 340 }}>
                        {k.kind === 'publishable' && k.key ? <KeyBox value={k.key} /> : <code className="muted">{k.prefix}…</code>}
                      </td>
                      <td className="small muted">{k.last_used_at ? fmtAgo(k.last_used_at) : 'Belum pernah'}</td>
                      <td>
                        {k.revoked_at ? <Badge tone="muted">Dicabut</Badge>
                          : !k.active ? <Badge tone="muted">Kedaluwarsa</Badge>
                          : k.expires_at ? <Badge tone="warn">Berakhir {fmtDate(k.expires_at)}</Badge>
                          : <Badge tone="ok">Aktif</Badge>}
                      </td>
                      <td>
                        {manage && k.active && (
                          <div className="row" style={{ flexWrap: 'nowrap', justifyContent: 'flex-end' }}>
                            <Button size="sm" variant="ghost" onClick={() => setRotating(k)} disabled={k.mode === 'live' && limited}><ArrowsClockwise size={14} />Rotasi</Button>
                            <Button size="sm" variant="ghost" onClick={() => setRevoking(k)} style={{ color: 'var(--sos)' }}><Prohibit size={14} />Cabut</Button>
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      ))}

      <div className="card card-pad stack-sm">
        <h2>Pasang SDK</h2>
        <p className="small muted">Ganti <code>pk_test_</code> ke <code>pk_live_</code> setelah disetujui. Kode lain tidak perlu diubah.</p>
        <Snippet code={`npm i @siagasos/react @siagasos/js

import { SOSProvider, SOSButton } from '@siagasos/react';

<SOSProvider apiKey="${app.keys.find((k) => k.kind === 'publishable' && k.active)?.key ?? 'pk_test_...'}" sourceKey="kantor-pusat-web">
  <SOSButton category="kriminal" holdToConfirm={3} />
</SOSProvider>`} />
      </div>

      {newKeys && <NewKeysModal title="Pasangan kunci baru" keys={newKeys} onClose={() => setNewKeys(null)} />}
      {rotating && <RotateModal app={app} k={rotating} onClose={() => setRotating(null)} onDone={(fresh) => { setRotating(null); void reload(); if (fresh.kind === 'secret') setRotated(fresh); else toast('Kunci dirotasi'); }} />}
      {revoking && (
        <Modal title="Cabut kunci?" onClose={() => setRevoking(null)} footer={<>
          <Button onClick={() => setRevoking(null)}>Batal</Button>
          <Button variant="danger" onClick={async () => {
            try { await api(`/portal/apps/${app.id}/keys/${revoking.id}/revoke`, { method: 'POST' }); toast('Kunci dicabut'); void reload(); }
            catch (e) { toast((e as Error).message, 'error'); }
            setRevoking(null);
          }}>Cabut sekarang</Button>
        </>}>
          <p>Kunci <code>{revoking.prefix}…</code> langsung berhenti bekerja (maks. 60 detik di semua server). Aplikasi yang masih memakainya tidak bisa mengirim laporan SOS.</p>
        </Modal>
      )}
      {rotated && (
        <Modal title="Secret key baru" onClose={() => setRotated(null)} footer={<Button variant="primary" onClick={() => setRotated(null)}>Selesai</Button>}>
          <Alert tone="warn">Simpan sekarang. Secret key hanya ditampilkan sekali.</Alert>
          <KeyBox value={rotated.key!} />
        </Modal>
      )}
    </div>
  );
}

function RotateModal({ app, k, onClose, onDone }: { app: App; k: ApiKey; onClose: () => void; onDone: (fresh: ApiKey) => void }) {
  const [grace, setGrace] = useState(24);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  return (
    <Modal title="Rotasi kunci" onClose={onClose} footer={<>
      <Button onClick={onClose}>Batal</Button>
      <Button variant="primary" loading={busy} onClick={async () => {
        setBusy(true);
        try {
          const r = await api<{ key: ApiKey }>(`/portal/apps/${app.id}/keys/${k.id}/rotate`, { body: { grace_hours: grace } });
          onDone(r.key);
        } catch (e) { setErr((e as Error).message); setBusy(false); }
      }}>Rotasi</Button>
    </>}>
      {err && <Alert tone="error">{err}</Alert>}
      <p>Kunci baru dibuat untuk <code>{k.prefix}…</code>. Kunci lama tetap berlaku selama masa tenggang supaya Anda sempat men-deploy kunci baru.</p>
      <Field label={`Masa tenggang: ${grace === 0 ? 'langsung dicabut' : `${grace} jam`}`} htmlFor="grace" hint="0–72 jam">
        <input id="grace" type="range" min={0} max={72} step={1} value={grace} onChange={(e) => setGrace(Number(e.target.value))} style={{ width: '100%' }} />
      </Field>
    </Modal>
  );
}

function Snippet({ code }: { code: string }) {
  return (
    <div style={{ position: 'relative' }}>
      <pre className="mono" style={{ margin: 0, padding: 16, background: 'var(--surface-2)', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', overflowX: 'auto', fontSize: 13 }}>{code}</pre>
      <div style={{ position: 'absolute', top: 6, right: 6 }}><CopyButton value={code} /></div>
    </div>
  );
}

// ---------------------------------------------------------------- pengaturan
function ChipList({ id, value, onChange, placeholder, validate }: { id: string; value: string[]; onChange: (v: string[]) => void; placeholder: string; validate: (s: string) => string | null }) {
  const [draft, setDraft] = useState('');
  const [err, setErr] = useState<string | null>(null);
  function add() {
    const v = draft.trim().replace(/\/+$/, '');
    if (!v) return;
    const e = validate(v);
    if (e) return setErr(e);
    if (!value.includes(v)) onChange([...value, v]);
    setDraft('');
    setErr(null);
  }
  return (
    <>
      <div className="chip-input">
        {value.map((v) => (
          <span key={v} className="chip">{v}<button type="button" aria-label={`Hapus ${v}`} onClick={() => onChange(value.filter((x) => x !== v))}><X size={12} /></button></span>
        ))}
        <input id={id} value={draft} placeholder={placeholder} onChange={(e) => setDraft(e.target.value)} onBlur={add}
          onKeyDown={(e: KeyboardEvent) => { if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); add(); } }} />
      </div>
      {err && <span className="error small" role="alert" style={{ color: 'var(--sos)' }}>{err}</span>}
    </>
  );
}

function SettingsTab({ app, onSaved }: { app: App; onSaved: (a: App) => void }) {
  const { can } = useAuth();
  const toast = useToast();
  const manage = can('owner', 'admin');
  const [f, setF] = useState({
    name: app.name, allowed_origins: app.allowed_origins, allowed_bundle_ids: app.allowed_bundle_ids,
    webhook_url: app.webhook_url ?? '', auto_create_sources: app.auto_create_sources,
  });
  const cfg0: SdkConfig = app.sdk_config ?? {};
  const [cfg, setCfg] = useState({
    categories: cfg0.categories ?? [...DEFAULT_CATEGORIES],
    complaint_categories: cfg0.complaint_categories ?? [...DEFAULT_COMPLAINT_CATEGORIES], button_text: cfg0.button_text ?? '', hold_seconds: cfg0.hold_seconds ?? 3,
    recipient_text: cfg0.recipient_text ?? '', fallback_phone: cfg0.fallback_phone ?? '', live_location_interval_s: cfg0.live_location_interval_s ?? 15,
  });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [secret, setSecret] = useState<string | null>(null);

  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const sdk_config: SdkConfig = { categories: cfg.categories, complaint_categories: cfg.complaint_categories, hold_seconds: cfg.hold_seconds, live_location_interval_s: cfg.live_location_interval_s };
      if (cfg.button_text) sdk_config.button_text = cfg.button_text;
      if (cfg.recipient_text) sdk_config.recipient_text = cfg.recipient_text;
      if (cfg.fallback_phone) sdk_config.fallback_phone = cfg.fallback_phone;
      const a = await api<App>(`/portal/apps/${app.id}`, {
        method: 'PATCH',
        body: { ...f, name: f.name.trim(), webhook_url: f.webhook_url.trim() || null, sdk_config },
      });
      onSaved(a);
      toast('Pengaturan disimpan');
    } catch (e) {
      setErr(e instanceof ApiError ? e.detailMessage : String(e));
    } finally {
      setBusy(false);
    }
  }

  const originRule = (s: string) => (s === '*' || /^https:\/\/[a-z0-9.-]+(:\d+)?$/i.test(s) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(s)
    ? null : 'Format: https://domain (http hanya untuk localhost)');
  const bundleRule = (s: string) => (/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/.test(s) ? null : 'Format: com.perusahaan.app');

  return (
    <form className="stack" onSubmit={save}>
      {err && <Alert tone="error">{err}</Alert>}
      <fieldset disabled={!manage} className="stack" style={{ border: 0, padding: 0, margin: 0 }}>
        <div className="card">
          <div className="card-head"><div><h2>Akses</h2><p>SDK hanya menerima permintaan dari origin web / bundle id yang terdaftar.</p></div></div>
          <div className="card-body">
            <TextField label="Nama app" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} />
            <Field label="Origin web yang diizinkan" htmlFor="origins" hint={'Tekan Enter untuk menambah. "*" hanya berlaku untuk kunci test.'}>
              <ChipList id="origins" value={f.allowed_origins} onChange={(v) => setF({ ...f, allowed_origins: v.map((s) => s.toLowerCase()) })} placeholder="https://app.perusahaan.co.id" validate={originRule} />
            </Field>
            <Field label="Bundle id Android / iOS" htmlFor="bundles" hint="Dikirim SDK mobile lewat header X-SOS-Bundle">
              <ChipList id="bundles" value={f.allowed_bundle_ids} onChange={(v) => setF({ ...f, allowed_bundle_ids: v })} placeholder="com.perusahaan.app" validate={bundleRule} />
            </Field>
            <label className="check">
              <input type="checkbox" checked={f.auto_create_sources} onChange={(e) => setF({ ...f, auto_create_sources: e.target.checked })} />
              <span>Buat source otomatis saat SDK mengirim <code>sourceKey</code> baru</span>
            </label>
          </div>
        </div>

        <div className="card">
          <div className="card-head"><div><h2>Webhook</h2><p>Event <code>report.created</code>, <code>report.status_changed</code>, <code>report.cancelled</code> dikirim ke server Anda.</p></div></div>
          <div className="card-body">
            <TextField label="Webhook URL" type="url" placeholder="https://api.perusahaan.co.id/siagasos" hint="Wajib https. Kosongkan untuk menonaktifkan." value={f.webhook_url} onChange={(e) => setF({ ...f, webhook_url: e.target.value })} />
            <div className="row">
              {secret ? <div style={{ flex: 1, minWidth: 240 }}><KeyBox value={secret} /></div>
                : <Button type="button" size="sm" onClick={async () => {
                    try { setSecret((await api<{ webhook_secret: string }>(`/portal/apps/${app.id}/webhook-secret`)).webhook_secret); }
                    catch (e) { toast((e as Error).message, 'error'); }
                  }}><Key size={14} />Tampilkan webhook secret</Button>}
            </div>
            <p className="small muted">Verifikasi header <code>X-SOS-Signature: t=&lt;unix&gt;,v1=&lt;hex&gt;</code> dengan HMAC-SHA256(secret, "&lt;t&gt;.&lt;raw body&gt;").</p>
          </div>
        </div>

        <div className="card">
          <div className="card-head"><div><h2>Tampilan tombol SOS</h2><p>Dibaca SDK dari <code>/v1/sdk/config</code>; perubahan berlaku tanpa rilis ulang aplikasi.</p></div></div>
          <div className="card-body">
            <Field label="Kategori darurat" htmlFor="cats" hint="Maks. 12 kategori">
              <ChipList id="cats" value={cfg.categories} onChange={(v) => setCfg({ ...cfg, categories: v.slice(0, 12) })} placeholder="tambah kategori" validate={(s) => (s.length > 40 ? 'Maks. 40 karakter' : null)} />
            </Field>
            <p className="small muted">{cfg.categories.map(catLabel).join(' · ')}</p>
            <Field label="Jenis pengaduan" htmlFor="complaint-cats" hint="Menu &quot;Laporan pengaduan&quot; di tombol melayang SDK. Maks. 12">
              <ChipList id="complaint-cats" value={cfg.complaint_categories} onChange={(v) => setCfg({ ...cfg, complaint_categories: v.slice(0, 12) })} placeholder="tambah jenis pengaduan" validate={(s) => (s.length > 40 ? 'Maks. 40 karakter' : null)} />
            </Field>
            <p className="small muted">{cfg.complaint_categories.map(catLabel).join(' · ')}</p>
            <div className="grid-2">
              <TextField label="Teks tombol" placeholder="SOS" maxLength={20} value={cfg.button_text} onChange={(e) => setCfg({ ...cfg, button_text: e.target.value })} />
              <TextField label="Tahan tombol (detik)" type="number" min={1} max={10} value={cfg.hold_seconds} onChange={(e) => setCfg({ ...cfg, hold_seconds: Math.min(10, Math.max(1, Number(e.target.value) || 1)) })} hint="Mencegah tekan tidak sengaja" />
              <TextField label="Teks penerima" placeholder="Laporan dikirim ke tim keamanan kantor" maxLength={200} value={cfg.recipient_text} onChange={(e) => setCfg({ ...cfg, recipient_text: e.target.value })} />
              <TextField label="Nomor cadangan" placeholder="110" type="tel" maxLength={20} value={cfg.fallback_phone} onChange={(e) => setCfg({ ...cfg, fallback_phone: e.target.value })} hint="Ditampilkan bila pengiriman gagal" />
              <TextField label="Interval lokasi live (detik)" type="number" min={5} max={120} value={cfg.live_location_interval_s} onChange={(e) => setCfg({ ...cfg, live_location_interval_s: Math.min(120, Math.max(5, Number(e.target.value) || 15)) })} />
            </div>
          </div>
        </div>
      </fieldset>
      {manage && <div className="row" style={{ justifyContent: 'flex-end' }}><Button variant="primary" type="submit" loading={busy}>Simpan pengaturan</Button></div>}
    </form>
  );
}

// ---------------------------------------------------------------- source
interface Source { id: string; source_key: string; label: string | null; platform: string | null; report_count: number; created_at: string }

function SourcesTab({ app }: { app: App }) {
  const { can } = useAuth();
  const toast = useToast();
  const { data, loading, reload } = useLoad(() => api<{ data: Source[] }>(`/portal/apps/${app.id}/sources`), [app.id]);
  const [f, setF] = useState({ source_key: '', label: '', platform: 'web' });
  const [busy, setBusy] = useState(false);

  async function add(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await api(`/portal/apps/${app.id}/sources`, { body: { source_key: f.source_key, platform: f.platform, ...(f.label ? { label: f.label } : {}) } });
      setF({ source_key: '', label: '', platform: 'web' });
      toast('Source ditambahkan');
      void reload();
    } catch (e) { toast(e instanceof ApiError ? e.detailMessage : String(e), 'error'); } finally { setBusy(false); }
  }

  return (
    <div className="stack">
      <p className="muted small">Source membedakan lokasi / kanal asal laporan, mis. <code>gedung-a-web</code> atau <code>armada-android</code>. Dashboard bisa difilter per source.</p>
      {can('owner', 'admin') && (
        <form className="card card-pad row" style={{ alignItems: 'flex-end' }} onSubmit={add}>
          <div style={{ flex: '1 1 180px' }}><TextField label="source_key" placeholder="gedung-a-web" value={f.source_key} onChange={(e) => setF({ ...f, source_key: e.target.value.toLowerCase() })} /></div>
          <div style={{ flex: '1 1 180px' }}><TextField label="Label" placeholder="Gedung A lantai 3" value={f.label} onChange={(e) => setF({ ...f, label: e.target.value })} /></div>
          <Field label="Platform" htmlFor="platform">
            <select id="platform" className="select" value={f.platform} onChange={(e) => setF({ ...f, platform: e.target.value })}>
              {['web', 'android', 'ios', 'other'].map((p) => <option key={p}>{p}</option>)}
            </select>
          </Field>
          <Button type="submit" variant="primary" loading={busy} disabled={!f.source_key}><Plus size={14} />Tambah</Button>
        </form>
      )}
      <div className="card table-wrap">
        {loading && !data ? <Spinner /> : !data?.data.length ? <Empty icon={<Key size={32} />} title="Belum ada source" /> : (
          <table className="table">
            <thead><tr><th>source_key</th><th>Label</th><th>Platform</th><th>Laporan</th><th>Dibuat</th></tr></thead>
            <tbody>
              {data.data.map((s) => (
                <tr key={s.id}><td><code>{s.source_key}</code></td><td>{s.label ?? '—'}</td><td>{s.platform ?? '—'}</td><td>{s.report_count}</td><td className="small muted">{fmtDate(s.created_at)}</td></tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- penerima SOS (WhatsApp)
interface Recipient { id: string; name: string; phone: string; source_id: string | null; source_key: string | null; source_label: string | null; active: boolean; created_at: string }

function RecipientsTab({ app }: { app: App }) {
  const { can } = useAuth();
  const toast = useToast();
  const manage = can('owner', 'admin');
  const { data, loading, reload } = useLoad(() => api<{ data: Recipient[] }>(`/portal/apps/${app.id}/recipients`), [app.id]);
  const sources = useLoad(() => api<{ data: Source[] }>(`/portal/apps/${app.id}/sources`), [app.id]);
  const [f, setF] = useState({ name: '', phone: '', source_id: '' });
  const [busy, setBusy] = useState<string | null>(null);

  async function add(e: FormEvent) {
    e.preventDefault();
    setBusy('add');
    try {
      await api(`/portal/apps/${app.id}/recipients`, { body: { name: f.name, phone: f.phone, source_id: f.source_id || null } });
      setF({ name: '', phone: '', source_id: f.source_id });
      toast('Penerima SOS ditambahkan');
      void reload();
    } catch (e) { toast(e instanceof ApiError ? e.detailMessage : String(e), 'error'); } finally { setBusy(null); }
  }

  async function toggle(r: Recipient) {
    setBusy(r.id);
    try {
      await api(`/portal/apps/${app.id}/recipients/${r.id}`, { method: 'PATCH', body: { active: !r.active } });
      void reload();
    } catch (e) { toast(e instanceof ApiError ? e.detailMessage : String(e), 'error'); } finally { setBusy(null); }
  }

  async function remove(r: Recipient) {
    if (!window.confirm(`Hapus ${r.name} (${r.phone}) dari penerima SOS?`)) return;
    setBusy(r.id);
    try {
      await api(`/portal/apps/${app.id}/recipients/${r.id}`, { method: 'DELETE' });
      toast('Penerima SOS dihapus');
      void reload();
    } catch (e) { toast(e instanceof ApiError ? e.detailMessage : String(e), 'error'); } finally { setBusy(null); }
  }

  return (
    <div className="stack">
      <p className="muted small">
        Setiap SOS live dari app ini dikirim ke nomor WhatsApp di bawah: nama pelapor, lokasi (app · source), dan link Google Maps.
        Kontak darurat pribadi yang diatur pelapor di aplikasi (maks. 3) ikut dikabari. Pengaduan tidak memicu WhatsApp.
        Hasil pengiriman tiap nomor tercatat di timeline laporan.
      </p>
      {manage && (
        <form className="card card-pad row" style={{ alignItems: 'flex-end' }} onSubmit={add}>
          <div style={{ flex: '1 1 160px' }}><TextField label="Nama" placeholder="Pos satpam" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} /></div>
          <div style={{ flex: '1 1 160px' }}><TextField label="Nomor WhatsApp" placeholder="0812xxxxxxx" inputMode="tel" value={f.phone} onChange={(e) => setF({ ...f, phone: e.target.value })} /></div>
          <Field label="Cakupan" htmlFor="rcpt-source">
            <select id="rcpt-source" className="select" value={f.source_id} onChange={(e) => setF({ ...f, source_id: e.target.value })}>
              <option value="">Semua source</option>
              {sources.data?.data.map((s) => <option key={s.id} value={s.id}>{s.label ? `${s.label} (${s.source_key})` : s.source_key}</option>)}
            </select>
          </Field>
          <Button type="submit" variant="primary" loading={busy === 'add'} disabled={!f.name.trim() || !f.phone.trim()}><Plus size={14} />Tambah</Button>
        </form>
      )}
      <div className="card table-wrap">
        {loading && !data ? <Spinner /> : !data?.data.length ? (
          <Empty icon={<WhatsappLogo size={32} />} title="Belum ada penerima SOS">Tambahkan nomor pos satpam / pengelola yang harus dikabari saat ada SOS.</Empty>
        ) : (
          <table className="table">
            <thead><tr><th>Nama</th><th>WhatsApp</th><th>Cakupan</th><th>Status</th>{manage && <th />}</tr></thead>
            <tbody>
              {data.data.map((r) => (
                <tr key={r.id}>
                  <td>{r.name}</td>
                  <td className="mono small">+{r.phone}</td>
                  <td>{r.source_id ? <code>{r.source_label ?? r.source_key}</code> : <span className="muted">Semua source</span>}</td>
                  <td>{r.active ? <Badge tone="ok">Aktif</Badge> : <Badge tone="muted">Nonaktif</Badge>}</td>
                  {manage && (
                    <td style={{ whiteSpace: 'nowrap', textAlign: 'right' }}>
                      <Button size="sm" loading={busy === r.id} onClick={() => void toggle(r)}>{r.active ? 'Nonaktifkan' : 'Aktifkan'}</Button>{' '}
                      <Button size="sm" variant="danger" aria-label={`Hapus ${r.name}`} disabled={busy === r.id} onClick={() => void remove(r)}><Trash size={14} /></Button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- webhook log
interface Delivery { id: string; report_id: string; event: string; status_code: number | null; attempts: number; last_error: string | null; next_retry_at: string | null; delivered_at: string | null; created_at: string }

function WebhooksTab({ app }: { app: App }) {
  const { data, loading, reload } = useLoad(() => api<{ data: Delivery[] }>(`/portal/apps/${app.id}/webhooks`), [app.id]);
  return (
    <div className="stack">
      <div className="row-between">
        <p className="muted small">{app.webhook_url ? <>Tujuan: <code>{app.webhook_url}</code>. Retry eksponensial hingga 24 jam.</> : 'Webhook belum diatur di tab Pengaturan.'}</p>
        <Button size="sm" onClick={() => void reload()}><ArrowsClockwise size={14} />Muat ulang</Button>
      </div>
      <div className="card table-wrap">
        {loading && !data ? <Spinner /> : !data?.data.length ? <Empty icon={<ArrowsClockwise size={32} />} title="Belum ada pengiriman webhook" /> : (
          <table className="table">
            <thead><tr><th>Waktu</th><th>Event</th><th>Hasil</th><th>Percobaan</th><th>Keterangan</th></tr></thead>
            <tbody>
              {data.data.map((d) => (
                <tr key={d.id}>
                  <td className="small">{fmtDate(d.created_at)}</td>
                  <td><code>{d.event}</code></td>
                  <td>{d.delivered_at ? <Badge tone="ok">{d.status_code ?? 200} Terkirim</Badge>
                    : d.next_retry_at ? <Badge tone="warn">{d.status_code ?? 'Gagal'} · retry</Badge>
                    : <Badge tone="sos">{d.status_code ?? 'Gagal'} · berhenti</Badge>}</td>
                  <td>{d.attempts}</td>
                  <td className="small muted" style={{ maxWidth: 320 }}>{d.last_error ?? (d.next_retry_at ? `Coba lagi ${fmtDate(d.next_retry_at)}` : '—')}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
