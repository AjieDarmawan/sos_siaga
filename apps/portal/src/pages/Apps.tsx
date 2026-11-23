import { useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { CaretRight, DeviceMobile, Globe, Plus, SquaresFour, Warning } from '@phosphor-icons/react';
import { api, ApiError } from '../lib/api';
import { fmtDate } from '../lib/format';
import type { ApiKey, App } from '../lib/types';
import { TestModeNotice } from '../components/Layout';
import { Alert, Badge, Button, Empty, KeyBox, Modal, Spinner, TextField, useLoad } from '../components/ui';

export interface NewKeys { publishable: ApiKey; secret: ApiKey }

export function AppsPage() {
  const { data, loading, error, reload } = useLoad(() => api<{ data: App[] }>('/portal/apps'));
  const [creating, setCreating] = useState(false);
  const [created, setCreated] = useState<{ app: App; keys: Record<string, NewKeys> } | null>(null);
  const nav = useNavigate();

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h1>App & kunci API</h1>
          <p>Satu app untuk setiap produk yang memasang tombol SOS (web, Android, atau iOS).</p>
        </div>
        <Button variant="primary" onClick={() => setCreating(true)}><Plus size={16} weight="bold" />App baru</Button>
      </div>
      <TestModeNotice />

      {loading && !data ? <Spinner /> : error ? <Alert tone="error">{error}</Alert> : !data?.data.length ? (
        <div className="card">
          <Empty icon={<SquaresFour size={40} />} title="Belum ada app"
            action={<Button variant="primary" onClick={() => setCreating(true)}><Plus size={16} />Buat app pertama</Button>}>
            Buat app untuk mendapatkan publishable key (dipasang di SDK) dan secret key (dipakai server Anda).
          </Empty>
        </div>
      ) : (
        <div className="card table-wrap">
          <table className="table">
            <thead><tr><th>Nama</th><th>Origin / bundle</th><th>Kunci aktif</th><th>Dibuat</th><th><span className="sr-only">Aksi</span></th></tr></thead>
            <tbody>
              {data.data.map((a) => {
                const active = a.keys.filter((k) => k.active && k.kind === 'publishable');
                const modes = (['test', 'live'] as const).map((m) => ({ m, n: active.filter((k) => k.mode === m).length })).filter((x) => x.n);
                const mobile = a.allowed_bundle_ids.length > 0, web = a.allowed_origins.length > 0;
                const AppIc = mobile && !web ? DeviceMobile : Globe;
                return (
                  <tr key={a.id} style={{ cursor: 'pointer' }} onClick={() => nav(`/apps/${a.id}`)}>
                    <td>
                      <span className="app-name">
                        <span className="app-ic" aria-hidden><AppIc size={20} weight="duotone" /></span>
                        <span style={{ minWidth: 0 }}>
                          <Link to={`/apps/${a.id}`} onClick={(e) => e.stopPropagation()} style={{ fontWeight: 600, color: 'var(--text)' }}>{a.name}</Link>
                          {a.disabled && <> <Badge tone="sos">Dinonaktifkan</Badge></>}
                          <small className="row" style={{ gap: 4, marginTop: 3 }}>
                            {web && <span className="plat"><Globe size={12} />Web</span>}
                            {mobile && <span className="plat"><DeviceMobile size={12} />Mobile</span>}
                          </small>
                        </span>
                      </span>
                    </td>
                    <td className="small muted">
                      {[...a.allowed_origins, ...a.allowed_bundle_ids].slice(0, 2).join(', ') || <span className="row" style={{ gap: 4, color: 'var(--warn)' }}><Warning size={14} />Belum diatur</span>}
                      {a.allowed_origins.length + a.allowed_bundle_ids.length > 2 && ` +${a.allowed_origins.length + a.allowed_bundle_ids.length - 2}`}
                    </td>
                    <td><div className="row">{modes.map(({ m, n }) => <Badge key={m} tone={m === 'live' ? 'ok' : 'test'}><span title={n > 1 ? `${n} kunci ${m} aktif (mis. masa tenggang rotasi)` : undefined}>{m.toUpperCase()}{n > 1 ? ` ×${n}` : ''}</span></Badge>)}</div></td>
                    <td className="small muted">{fmtDate(a.created_at)}</td>
                    <td style={{ width: 40 }}><CaretRight size={16} aria-hidden /></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {creating && <CreateAppModal onClose={() => setCreating(false)} onCreated={(r) => { setCreating(false); setCreated(r); void reload(); }} />}
      {created && <NewKeysModal title={`Kunci untuk ${created.app.name}`} keys={created.keys} onClose={() => { const id = created.app.id; setCreated(null); nav(`/apps/${id}`); }} />}
    </div>
  );
}

function CreateAppModal({ onClose, onCreated }: { onClose: () => void; onCreated: (r: { app: App; keys: Record<string, NewKeys> }) => void }) {
  const [name, setName] = useState('');
  const [origin, setOrigin] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const r = await api<{ app: App; keys: Record<string, NewKeys> }>('/portal/apps', {
        body: { name: name.trim(), allowed_origins: origin.trim() ? [origin.trim()] : [] },
      });
      onCreated(r);
    } catch (e) {
      setErr(e instanceof ApiError ? e.detailMessage : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="App baru" onClose={onClose}>
      <form className="stack" onSubmit={submit} id="create-app">
        {err && <Alert tone="error">{err}</Alert>}
        <TextField label="Nama app" placeholder="mis. Aplikasi Karyawan" required minLength={2} value={name} onChange={(e) => setName(e.target.value)} />
        <TextField label="Origin web" hint="Domain tempat SDK web dipasang, mis. https://app.perusahaan.co.id. Bisa ditambah nanti." placeholder="https://" value={origin} onChange={(e) => setOrigin(e.target.value)} />
        <div className="row" style={{ justifyContent: 'flex-end' }}>
          <Button type="button" onClick={onClose}>Batal</Button>
          <Button variant="primary" type="submit" loading={busy} disabled={name.trim().length < 2}>Buat app</Button>
        </div>
      </form>
    </Modal>
  );
}

/** Secret key hanya tampil sekali; modal ini memaksa pengguna menyalinnya dulu. */
export function NewKeysModal({ title, keys, onClose }: { title: string; keys: Record<string, NewKeys>; onClose: () => void }) {
  const [ack, setAck] = useState(false);
  return (
    <Modal title={title} onClose={() => ack && onClose()}
      footer={<Button variant="primary" disabled={!ack} onClick={onClose}>Selesai</Button>}>
      <Alert tone="warn" title="Simpan secret key sekarang">Secret key hanya ditampilkan sekali. Simpan di server / secret manager, jangan di aplikasi klien.</Alert>
      {Object.entries(keys).map(([mode, pair]) => (
        <div key={mode} className="stack-sm">
          <h3 className="row"><Badge tone={mode === 'live' ? 'ok' : 'test'}>{mode.toUpperCase()}</Badge></h3>
          <span className="label">Publishable key (untuk SDK)</span>
          <KeyBox value={pair.publishable.key!} />
          <span className="label">Secret key (untuk server)</span>
          <KeyBox value={pair.secret.key!} />
        </div>
      ))}
      <label className="check"><input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} />Saya sudah menyimpan secret key</label>
    </Modal>
  );
}
