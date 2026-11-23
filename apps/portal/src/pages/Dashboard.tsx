import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { BellRinging, BellSlash, DownloadSimple, MapPin, MapPinLine, Phone, Siren, User, X } from '@phosphor-icons/react';
import { TERMINAL_STATUSES } from '@siagasos/shared';
import { api, API_URL, download, tokenStore } from '../lib/api';
import { useAuth } from '../lib/auth';
import { catLabel, fmtAgo, fmtDate, fmtTime, REPORT_STATUS } from '../lib/format';
import { playAlarm, unlock } from '../lib/sound';
import type { Report, ReportDetail, ReportStatus } from '../lib/types';
import { ReportMap } from '../components/ReportMap';
import { MediaBadges, MediaGallery } from '../components/MediaGallery';
import { Alert, Badge, Button, Empty, Spinner, useToast } from '../components/ui';

type Group = 'active' | 'all' | 'closed';
const GROUPS: [Group, string][] = [['active', 'Aktif'], ['all', 'Semua'], ['closed', 'Selesai']];
const ACTIVE: ReportStatus[] = ['open', 'acknowledged', 'in_progress'];
const PERIODS: [number, string][] = [[1, '24 jam'], [7, '7 hari'], [30, '30 hari']];
const SOUND_KEY = 'siagasos.dashboard.sound';
const REMIND_MS = 20_000;

const isTerminal = (s: ReportStatus) => TERMINAL_STATUSES.includes(s);
const inGroup = (r: Report, g: Group) => (g === 'all' ? true : g === 'active' ? !isTerminal(r.status) : isTerminal(r.status));

type StreamEvent =
  | { type: 'report.created' | 'report.status_changed' | 'report.cancelled' | 'report.note_added'; data: { report: Report; actor?: { name: string | null } } }
  | { type: 'report.location_updated'; data: { report_id: string; location: { lat: number; lng: number; accuracy_m?: number | null; recorded_at?: string } } }
  | { type: 'report.media_added'; data: { report_id: string; media: { kind: 'image' | 'video' | 'audio' } } };

export function DashboardPage() {
  const { me, can } = useAuth();
  const toast = useToast();
  const [group, setGroup] = useState<Group>('active');
  const [days, setDays] = useState(7);
  const [mode, setMode] = useState<'' | 'live' | 'test'>('');
  const [byId, setById] = useState<Map<string, Report>>(new Map());
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<ReportDetail | null>(null);
  const [live, setLive] = useState(false);
  const [fresh, setFresh] = useState<Set<string>>(new Set());
  const [sound, setSound] = useState(() => { try { return localStorage.getItem(SOUND_KEY) === '1'; } catch { return false; } });
  const [soundBlocked, setSoundBlocked] = useState(false);
  const soundRef = useRef(sound);
  soundRef.current = sound;
  const selectedRef = useRef(selected);
  selectedRef.current = selected;

  // ------------------------------------------------------------ muat daftar
  const load = useCallback(async () => {
    setLoading(true);
    const p = new URLSearchParams({ limit: '200', from: new Date(Date.now() - days * 86400_000).toISOString() });
    if (group === 'active') p.set('status', ACTIVE.join(','));
    if (group === 'closed') p.set('status', TERMINAL_STATUSES.join(','));
    if (mode) p.set('mode', mode);
    try {
      const r = await api<{ data: Report[] }>(`/portal/reports?${p}`);
      setById(new Map(r.data.map((x) => [x.id, x])));
      setLoadErr(null);
    } catch (e) {
      setLoadErr((e as Error).message);
    } finally {
      setLoading(false);
    }
  }, [group, days, mode]);
  useEffect(() => { void load(); }, [load]);

  // ------------------------------------------------------------ detail
  const loadDetail = useCallback(async (id: string) => {
    try { setDetail(await api<ReportDetail>(`/portal/reports/${id}`)); }
    catch (e) { toast((e as Error).message, 'error'); setSelected(null); }
  }, [toast]);
  useEffect(() => { setDetail(null); if (selected) void loadDetail(selected); }, [selected, loadDetail]);

  // ------------------------------------------------------------ realtime SSE
  useEffect(() => {
    const token = tokenStore.get();
    if (!token) return;
    const es = new EventSource(`${API_URL}/portal/reports/stream?access_token=${encodeURIComponent(token)}`);
    es.onopen = () => setLive(true);
    es.onerror = () => setLive(false); // EventSource reconnect otomatis (retry: 3000)
    es.onmessage = (m) => {
      let ev: StreamEvent;
      try { ev = JSON.parse(m.data); } catch { return; }
      if (ev.type === 'report.media_added') {
        const { report_id, media } = ev.data;
        setById((prev) => {
          const r = prev.get(report_id);
          if (!r) return prev;
          const c = { image: 0, video: 0, audio: 0, ...(r.media_count ?? {}) };
          c[media.kind] += 1;
          return new Map(prev).set(report_id, { ...r, media_count: c });
        });
        if (selectedRef.current === report_id) void loadDetail(report_id);
        return;
      }
      if (ev.type === 'report.location_updated') {
        const { report_id, location } = ev.data;
        setById((prev) => {
          const r = prev.get(report_id);
          if (!r) return prev;
          const n = new Map(prev);
          n.set(report_id, { ...r, location: { lat: location.lat, lng: location.lng, accuracy_m: location.accuracy_m ?? null } });
          return n;
        });
        if (selectedRef.current === report_id) {
          setDetail((d) => d && { ...d, locations: [...d.locations, { lat: location.lat, lng: location.lng, accuracy_m: location.accuracy_m ?? null, recorded_at: location.recorded_at ?? new Date().toISOString() }] });
        }
        return;
      }
      const r = ev.data.report;
      setById((prev) => new Map(prev).set(r.id, { ...r, media_count: prev.get(r.id)?.media_count ?? null }));
      if (ev.type === 'report.created') {
        setFresh((s) => new Set(s).add(r.id));
        setTimeout(() => setFresh((s) => { const n = new Set(s); n.delete(r.id); return n; }), 4000);
        // Pengaduan bukan darurat: tanpa alarm & notifikasi browser.
        if (r.kind !== 'pengaduan') {
          if (soundRef.current && !playAlarm(3)) setSoundBlocked(true);
          notifyBrowser(r);
        }
      }
      if (selectedRef.current === r.id) void loadDetail(r.id);
    };
    return () => { es.close(); setLive(false); };
  }, [loadDetail]);

  // ------------------------------------------------------------ tampilan
  const reports = useMemo(() => [...byId.values()]
    .filter((r) => inGroup(r, group) && (!mode || r.mode === mode))
    .sort((a, b) => (a.status === 'open') !== (b.status === 'open') ? (a.status === 'open' ? -1 : 1) : b.created_at.localeCompare(a.created_at)),
  [byId, group, mode]);
  const openCount = useMemo(() => [...byId.values()].filter((r) => r.status === 'open').length, [byId]);

  // pengingat bunyi berulang selama masih ada laporan "Baru" yang belum diterima
  useEffect(() => {
    if (!sound || !openCount) return;
    const t = setInterval(() => playAlarm(1), REMIND_MS);
    return () => clearInterval(t);
  }, [sound, openCount]);

  useEffect(() => {
    document.title = openCount ? `(${openCount}) Laporan baru · SiagaSOS` : 'Dashboard · SiagaSOS';
    return () => { document.title = 'SiagaSOS Portal'; };
  }, [openCount]);

  async function toggleSound() {
    if (sound) {
      setSound(false);
      try { localStorage.setItem(SOUND_KEY, '0'); } catch { /* */ }
      return;
    }
    const ok = await unlock();
    if (ok) {
      setSound(true);
      setSoundBlocked(false);
      playAlarm(1);
      try { localStorage.setItem(SOUND_KEY, '1'); } catch { /* */ }
      if ('Notification' in window && Notification.permission === 'default') void Notification.requestPermission();
    }
  }

  // Preferensi suara tersimpan, tapi browser tetap butuh satu klik per sesi untuk membuka audio.
  useEffect(() => {
    if (!sound) return;
    const once = () => { void unlock().then((ok) => ok && setSoundBlocked(false)); };
    void unlock().then((ok) => setSoundBlocked(!ok));
    window.addEventListener('pointerdown', once, { once: true });
    return () => window.removeEventListener('pointerdown', once);
  }, [sound]);

  const selReport = selected ? byId.get(selected) ?? detail : null;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {openCount > 0 && (
        <div className="alarm-banner" role="alert">
          <Siren size={22} weight="fill" />
          <span style={{ flex: 1 }}>{openCount} laporan baru belum diterima</span>
          <Button size="sm" onClick={() => { const first = [...byId.values()].find((r) => r.status === 'open'); if (first) setSelected(first.id); }}>Lihat</Button>
        </div>
      )}
      <div className="dash" style={{ flex: 1, height: 'auto' }}>
        <section className="dash-list" aria-label="Daftar laporan">
          <div className="dash-toolbar">
            <div className="row-between">
              <div className="row" style={{ gap: 10 }}>
                <h1 style={{ fontSize: 18 }}>Laporan</h1>
                <span className="row small muted" style={{ gap: 6 }} aria-live="polite">
                  <span className={`live-dot ${live ? '' : 'off'}`} aria-hidden />{live ? 'Realtime' : 'Menyambung…'}
                </span>
              </div>
              <div className="row" style={{ gap: 4 }}>
                <Button size="sm" variant={sound ? 'default' : 'ghost'} onClick={toggleSound} aria-pressed={sound}
                  title={sound ? 'Matikan bunyi alert' : 'Aktifkan bunyi alert'}>
                  {sound ? <BellRinging size={16} weight="fill" /> : <BellSlash size={16} />}{sound ? 'Bunyi aktif' : 'Bunyi mati'}
                </Button>
                {can('owner', 'admin') && (
                  <Button size="sm" variant="ghost" aria-label="Ekspor CSV" title="Ekspor CSV sesuai filter" onClick={() => {
                    const p = new URLSearchParams({ from: new Date(Date.now() - days * 86400_000).toISOString() });
                    if (mode) p.set('mode', mode);
                    if (group !== 'all') p.set('status', (group === 'active' ? ACTIVE : TERMINAL_STATUSES).join(','));
                    download(`/portal/reports/export.csv?${p}`, 'siagasos-reports.csv').catch((e) => toast(e.message, 'error'));
                  }}><DownloadSimple size={16} /></Button>
                )}
              </div>
            </div>
            {sound && soundBlocked && <p className="small" style={{ color: 'var(--warn)' }}>Klik di mana saja pada halaman untuk mengaktifkan suara.</p>}
            <div className="seg" role="group" aria-label="Status">
              {GROUPS.map(([g, l]) => <button key={g} aria-pressed={group === g} onClick={() => setGroup(g)}>{l}</button>)}
            </div>
            <div className="row" style={{ gap: 8 }}>
              <select className="select" style={{ minHeight: 34, padding: '4px 8px', flex: 1 }} aria-label="Periode" value={days} onChange={(e) => setDays(Number(e.target.value))}>
                {PERIODS.map(([d, l]) => <option key={d} value={d}>{l} terakhir</option>)}
              </select>
              {!me?.account.limited && (
                <select className="select" style={{ minHeight: 34, padding: '4px 8px', flex: 1 }} aria-label="Mode" value={mode} onChange={(e) => setMode(e.target.value as typeof mode)}>
                  <option value="">Live + test</option><option value="live">Live saja</option><option value="test">Test saja</option>
                </select>
              )}
            </div>
          </div>
          <div className="dash-items">
            {loading && !byId.size ? <Spinner label="Memuat laporan" />
              : loadErr ? <div style={{ padding: 16 }}><Alert tone="error">{loadErr}</Alert></div>
              : !reports.length ? (
                <Empty icon={<MapPinLine size={36} />} title={group === 'active' ? 'Tidak ada laporan aktif' : 'Belum ada laporan'}>
                  Laporan baru muncul otomatis di sini{sound ? ' disertai bunyi alert' : ''}.
                  {me?.account.limited && ' Akun dalam mode test: hanya laporan test yang tampil.'}
                </Empty>
              ) : reports.map((r) => <ReportItem key={r.id} r={r} active={r.id === selected} isNew={fresh.has(r.id)} onClick={() => setSelected(r.id)} />)}
          </div>
        </section>

        <section className="dash-map" aria-label="Peta">
          <ReportMap reports={reports} selected={selected} trail={detail?.locations ?? null} onSelect={setSelected} />
          {selected && selReport && (
            <DetailPanel report={selReport} detail={detail} onClose={() => setSelected(null)} onChanged={(r) => {
              setById((prev) => new Map(prev).set(r.id, { ...r, media_count: prev.get(r.id)?.media_count ?? null }));
              void loadDetail(r.id);
            }} />
          )}
        </section>
      </div>
    </div>
  );
}

function notifyBrowser(r: Report) {
  if (!('Notification' in window) || Notification.permission !== 'granted' || document.visibilityState === 'visible') return;
  try {
    new Notification(`SOS: ${catLabel(r.category)}${r.mode === 'test' ? ' (TEST)' : ''}`, {
      body: [r.reporter.name, r.message, r.source_key].filter(Boolean).join(' · ') || 'Laporan darurat baru', tag: r.id, requireInteraction: true,
    });
  } catch { /* Safari lama */ }
}

function ReportItem({ r, active, isNew, onClick }: { r: Report; active: boolean; isNew: boolean; onClick: () => void }) {
  const st = REPORT_STATUS[r.status];
  const cls = r.status === 'open' ? 'is-open' : r.status === 'acknowledged' || r.status === 'in_progress' ? 'is-ack' : '';
  return (
    <button className={`report-item ${cls} ${isNew ? 'is-new' : ''}`} aria-current={active} onClick={onClick}>
      <span className="rail" aria-hidden />
      <span style={{ minWidth: 0 }}>
        <span className="row-between" style={{ flexWrap: 'nowrap' }}>
          <span className="title">
            {catLabel(r.category)}
            {r.kind === 'pengaduan' && <Badge tone="info">Pengaduan</Badge>}
            {r.mode === 'test' && <Badge tone="test">TEST</Badge>}
          </span>
          <Badge tone={st.tone}>{st.label}</Badge>
        </span>
        <span className="meta">
          <span title={fmtDate(r.created_at)}>{fmtAgo(r.created_at)}</span>
          {r.reporter.name && <span className="row" style={{ gap: 3 }}><User size={12} />{r.reporter.name}</span>}
          {r.source_key && <span className="mono">{r.source_key}</span>}
          {!r.location && <span className="row" style={{ gap: 3 }}><MapPin size={12} />tanpa lokasi</span>}
          <MediaBadges count={r.media_count} />
        </span>
        {r.message && <span className="small" style={{ display: 'block', marginTop: 4, color: 'var(--text-2)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{r.message}</span>}
      </span>
    </button>
  );
}

const NEXT: Partial<Record<ReportStatus, { to: ReportStatus; label: string; variant: 'primary' | 'default' | 'danger' }[]>> = {
  open: [{ to: 'acknowledged', label: 'Terima laporan', variant: 'danger' }, { to: 'false_alarm', label: 'Alarm palsu', variant: 'default' }],
  acknowledged: [{ to: 'in_progress', label: 'Mulai tangani', variant: 'primary' }, { to: 'resolved', label: 'Selesai', variant: 'default' }, { to: 'false_alarm', label: 'Alarm palsu', variant: 'default' }],
  in_progress: [{ to: 'resolved', label: 'Tandai selesai', variant: 'primary' }, { to: 'false_alarm', label: 'Alarm palsu', variant: 'default' }],
};

const EVENT_LABEL: Record<string, string> = { created: 'Laporan dibuat', status_changed: 'Status diubah', cancelled: 'Dibatalkan pelapor', note: 'Catatan', media: 'Lampiran' };

function DetailPanel({ report: r, detail, onClose, onChanged }: { report: Report; detail: ReportDetail | null; onClose: () => void; onChanged: (r: Report) => void }) {
  const toast = useToast();
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const st = REPORT_STATUS[r.status];
  const closeRef = useRef<HTMLButtonElement>(null);
  useEffect(() => { closeRef.current?.focus(); }, [r.id]);
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, [onClose]);

  async function change(status?: ReportStatus, e?: FormEvent) {
    e?.preventDefault();
    setBusy(status ?? 'note');
    try {
      const out = await api<Report>(`/portal/reports/${r.id}`, { method: 'PATCH', body: { ...(status ? { status } : {}), ...(note.trim() ? { note: note.trim() } : {}) } });
      setNote('');
      onChanged(out);
      toast(status ? `Status: ${REPORT_STATUS[status].label}` : 'Catatan ditambahkan');
    } catch (err) {
      toast((err as Error).message, 'error');
    } finally {
      setBusy(null);
    }
  }

  const loc = r.location;
  return (
    <aside className="card detail" aria-label="Detail laporan" style={{ boxShadow: 'var(--shadow-lg)' }}>
      <div className="card-head">
        <div style={{ minWidth: 0 }}>
          <h2 className="row" style={{ gap: 8 }}>{catLabel(r.category)}{r.kind === 'pengaduan' && <Badge tone="info">Pengaduan</Badge>}{r.mode === 'test' && <Badge tone="test">TEST</Badge>}</h2>
          <p>{fmtDate(r.created_at)} · {fmtAgo(r.created_at)}</p>
        </div>
        <button ref={closeRef} className="btn btn-ghost btn-icon" onClick={onClose} aria-label="Tutup detail"><X size={18} /></button>
      </div>
      <div className="detail-body">
        <div className="row-between">
          <Badge tone={st.tone} dot>{st.label}</Badge>
          {r.acknowledged_at && <span className="small muted">Diterima {fmtTime(r.acknowledged_at)}</span>}
        </div>

        {NEXT[r.status] && (
          <div className="row">
            {NEXT[r.status]!.map((a) => (
              <Button key={a.to} variant={a.variant} size="sm" loading={busy === a.to} disabled={!!busy} onClick={() => change(a.to)}>{a.label}</Button>
            ))}
          </div>
        )}

        {r.message && <p style={{ background: 'var(--surface-2)', padding: 12, borderRadius: 8 }}>{r.message}</p>}

        <dl className="kv">
          <dt>Pelapor</dt><dd>{r.reporter.name ?? '—'}{r.reporter.ref && <span className="muted mono small"> · {r.reporter.ref}</span>}</dd>
          <dt>Telepon</dt><dd>{r.reporter.phone ? <a href={`tel:${r.reporter.phone}`} className="row" style={{ gap: 4 }}><Phone size={14} />{r.reporter.phone}</a> : '—'}</dd>
          <dt>Source</dt><dd className="mono">{r.source_key ?? '—'}</dd>
          <dt>Lokasi</dt>
          <dd>{loc ? (
            <>
              <a href={`https://www.google.com/maps?q=${loc.lat},${loc.lng}`} target="_blank" rel="noreferrer" className="mono">{loc.lat.toFixed(5)}, {loc.lng.toFixed(5)}</a>
              {loc.accuracy_m != null && <span className="muted small"> ±{Math.round(loc.accuracy_m)} m</span>}
              {detail && detail.locations.length > 1 && <div className="small muted">{detail.locations.length} titik live, terakhir {fmtTime(detail.locations[detail.locations.length - 1]!.recorded_at)}</div>}
            </>
          ) : 'Tidak dibagikan'}</dd>
          {r.status_message && <><dt>Pesan ke pelapor</dt><dd>{r.status_message}</dd></>}
        </dl>

        {detail ? <MediaGallery reportId={r.id} media={detail.media ?? []} onExpired={() => onChanged(r)} canUpload={!TERMINAL_STATUSES.includes(r.status)} />
          : <div className="skeleton" style={{ height: 60 }} />}

        <form className="stack-sm" onSubmit={(e) => change(undefined, e)}>
          <label className="label" htmlFor="note">Catatan penanganan</label>
          <textarea id="note" className="textarea" rows={2} maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} placeholder="mis. Satpam lantai 3 menuju lokasi" />
          <div className="row" style={{ justifyContent: 'flex-end' }}>
            <Button size="sm" type="submit" loading={busy === 'note'} disabled={!note.trim() || !!busy}>Tambah catatan</Button>
          </div>
        </form>

        <div className="stack-sm">
          <h3>Timeline</h3>
          {!detail ? <div className="skeleton" style={{ height: 80 }} /> : (
            <ol className="timeline">
              {detail.timeline.map((e) => (
                <li key={e.id}>
                  <span>
                    <strong>{e.to_status ? `${EVENT_LABEL[e.type] ?? e.type}: ${REPORT_STATUS[e.to_status as ReportStatus]?.label ?? e.to_status}` : EVENT_LABEL[e.type] ?? e.type}</strong>
                    <span className="muted"> · {fmtTime(e.created_at)} · {e.actor_name ?? (e.actor_kind === 'reporter' ? 'Pelapor' : e.actor_kind === 'server' ? 'Server klien' : 'Sistem')}</span>
                    {e.note && <span style={{ display: 'block', color: 'var(--text-2)' }}>{e.note}</span>}
                  </span>
                </li>
              ))}
            </ol>
          )}
        </div>
      </div>
    </aside>
  );
}
