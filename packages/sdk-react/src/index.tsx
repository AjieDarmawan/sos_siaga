import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState,
  type CSSProperties, type ReactNode,
} from 'react';
import { SiagaSOS, SiagaSOSError, type ActiveReport, type AttachOptions, type MediaPublic, type SiagaSOSOptions, type TriggerInput, type SdkConfig } from '@siagasos/js';

export type { ActiveReport, TriggerInput, SdkConfig, MediaPublic, AttachOptions } from '@siagasos/js';
export { SiagaSOSError } from '@siagasos/js';

type Status = ActiveReport['status'] | 'idle' | 'sending';

interface SOSContextValue {
  client: SiagaSOS | null;
  config: SdkConfig | null;
  status: Status;
  activeReport: ActiveReport | null;
  error: SiagaSOSError | null;
  trigger: (input?: TriggerInput) => Promise<ActiveReport | null>;
  cancel: (reason?: string) => Promise<void>;
  reset: () => void;
  /** Lampirkan foto/video/suara ke laporan aktif. Progres tersedia di `attachments`. */
  attach: (file: Blob, opts?: Omit<AttachOptions, 'onProgress'> & { name?: string }) => Promise<MediaPublic | null>;
  attachments: Attachment[];
}

export interface Attachment {
  key: string;
  name: string;
  kind: 'image' | 'video' | 'audio';
  progress: number;
  state: 'uploading' | 'done' | 'error';
  error?: string;
}

const Ctx = createContext<SOSContextValue | null>(null);

export interface SOSProviderProps extends SiagaSOSOptions {
  children: ReactNode;
}

export function SOSProvider({ children, ...options }: SOSProviderProps) {
  const [client, setClient] = useState<SiagaSOS | null>(null);
  const [config, setConfig] = useState<SdkConfig | null>(null);
  const [activeReport, setActive] = useState<ActiveReport | null>(null);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<SiagaSOSError | null>(null);
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const key = JSON.stringify(options);

  useEffect(() => {
    const c = SiagaSOS.init(options);
    setClient(c);
    c.getConfig().then(setConfig, () => {});
    const offs = [
      c.on('status', (r) => setActive((cur) => (!cur || cur.localId === r.localId ? r : cur))),
      c.on('queued', (r) => setActive(r)),
      c.on('error', setError),
    ];
    const pending = c.activeReports[0];
    if (pending) setActive(pending);
    return () => {
      offs.forEach((off) => off());
      c.destroy();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const trigger = useCallback(async (input?: TriggerInput) => {
    if (!client) return null;
    setSending(true);
    setError(null);
    try {
      const r = await client.trigger(input);
      setActive(r);
      return r;
    } catch (e) {
      setError(e instanceof SiagaSOSError ? e : new SiagaSOSError(0, 'unknown', String(e)));
      return null;
    } finally {
      setSending(false);
    }
  }, [client]);

  const cancel = useCallback(async (reason?: string) => {
    if (!client || !activeReport) return;
    try {
      const r = await client.cancel(activeReport.id ?? activeReport.localId, reason);
      if (r) setActive(r);
    } catch (e) {
      setError(e as SiagaSOSError);
    }
  }, [client, activeReport]);

  const attach = useCallback(async (file: Blob, opts: Omit<AttachOptions, 'onProgress'> & { name?: string } = {}) => {
    if (!client || !activeReport) return null;
    const k = Math.random().toString(36).slice(2);
    const kind = file.type.startsWith('video') ? 'video' : file.type.startsWith('audio') ? 'audio' : 'image';
    const patch = (p: Partial<Attachment>) => setAttachments((xs) => xs.map((x) => (x.key === k ? { ...x, ...p } : x)));
    setAttachments((xs) => [...xs, { key: k, name: opts.name ?? (file as File).name ?? kind, kind, progress: 0, state: 'uploading' }]);
    try {
      const m = await client.attach(activeReport.id ?? activeReport.localId, file, { ...opts, onProgress: (progress) => patch({ progress }) });
      patch({ state: 'done', progress: 1 });
      return m;
    } catch (e) {
      patch({ state: 'error', error: (e as Error).message });
      return null;
    }
  }, [client, activeReport]);

  const value = useMemo<SOSContextValue>(() => ({
    client, config, activeReport, error, trigger, cancel, attach, attachments,
    status: sending ? 'sending' : activeReport?.status ?? 'idle',
    reset: () => { setActive(null); setError(null); setAttachments([]); },
  }), [client, config, activeReport, error, trigger, cancel, sending, attach, attachments]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useSOS(): SOSContextValue {
  const v = useContext(Ctx);
  if (!v) throw new Error('useSOS() harus dipakai di dalam <SOSProvider>');
  return v;
}

// ---------------------------------------------------------------- <SOSButton>

export interface SOSButtonProps extends TriggerInput {
  /** Detik menahan tombol sebelum laporan terkirim (default dari config app, biasanya 3). */
  holdToConfirm?: number;
  label?: string;
  className?: string;
  style?: CSSProperties;
  theme?: { color?: string; size?: number };
  /** Tampilkan tautan tel: cadangan (default true). */
  showFallbackCall?: boolean;
  onSent?: (r: ActiveReport) => void;
  onError?: (e: SiagaSOSError) => void;
}

const TERMINAL = ['resolved', 'cancelled', 'false_alarm'];

export function SOSButton({
  holdToConfirm, label, className, style, theme, showFallbackCall = true, onSent, onError, ...input
}: SOSButtonProps) {
  const { config, status, activeReport, error, trigger, cancel, reset } = useSOS();
  const hold = holdToConfirm ?? config?.hold_seconds ?? 3;
  const [progress, setProgress] = useState(0); // 0..1
  const raf = useRef<number | null>(null);
  const start = useRef(0);
  const fired = useRef(false);
  const color = theme?.color ?? '#d92d20';
  const size = theme?.size ?? 160;

  useEffect(() => { if (error) onError?.(error); }, [error, onError]);

  const stop = () => {
    if (raf.current) cancelAnimationFrame(raf.current);
    raf.current = null;
    if (!fired.current) setProgress(0); // dilepas sebelum waktunya → tidak terkirim
  };

  const tick = () => {
    const p = Math.min((performance.now() - start.current) / (hold * 1000), 1);
    setProgress(p);
    if (p >= 1) {
      fired.current = true;
      raf.current = null;
      navigator.vibrate?.(200);
      trigger(input).then((r) => { if (r) onSent?.(r); });
      return;
    }
    raf.current = requestAnimationFrame(tick);
  };

  const begin = () => {
    if (status === 'sending' || (activeReport && !TERMINAL.includes(activeReport.status))) return;
    if (activeReport) reset();
    fired.current = false;
    start.current = performance.now();
    raf.current = requestAnimationFrame(tick);
  };

  useEffect(() => () => { if (raf.current) cancelAnimationFrame(raf.current); }, []);

  const active = activeReport && !TERMINAL.includes(activeReport.status);
  const remaining = Math.ceil(hold * (1 - progress));
  const text =
    status === 'sending' ? 'Mengirim…'
      : active ? (activeReport!.statusMessage ?? activeReport!.status)
        : progress > 0 && progress < 1 ? `Tahan… ${remaining}`
          : label ?? config?.button_text ?? 'SOS';

  const r = size / 2 - 6;
  const circ = 2 * Math.PI * r;

  return (
    <div className={className} style={{ display: 'inline-flex', flexDirection: 'column', alignItems: 'center', gap: 8, fontFamily: 'system-ui, sans-serif', ...style }}>
      <button
        type="button"
        aria-label={`Tombol darurat. Tahan ${hold} detik untuk mengirim laporan.`}
        onPointerDown={begin}
        onPointerUp={stop}
        onPointerLeave={stop}
        onPointerCancel={stop}
        onKeyDown={(e) => { if ((e.key === ' ' || e.key === 'Enter') && !e.repeat) begin(); }}
        onKeyUp={stop}
        onContextMenu={(e) => e.preventDefault()}
        disabled={!!active || status === 'sending'}
        style={{
          position: 'relative', width: size, height: size, borderRadius: '50%', border: 'none',
          background: active ? '#475467' : color, color: '#fff', fontWeight: 700,
          fontSize: active ? 14 : size / 5, padding: 16, cursor: 'pointer', touchAction: 'none',
          userSelect: 'none', WebkitUserSelect: 'none', boxShadow: `0 6px 24px ${color}55`,
        }}
      >
        <svg width={size} height={size} style={{ position: 'absolute', inset: 0, transform: 'rotate(-90deg)', pointerEvents: 'none' }} aria-hidden>
          <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="#fff" strokeOpacity={0.9} strokeWidth={6}
            strokeDasharray={circ} strokeDashoffset={circ * (1 - progress)} />
        </svg>
        <span style={{ position: 'relative' }}>{text}</span>
      </button>
      {(active && activeReport!.status === 'open') || activeReport?.status === 'queued' ? (
        <button type="button" onClick={() => cancel('Salah pencet')} style={{ background: 'none', border: '1px solid #98a2b3', borderRadius: 6, padding: '4px 12px', cursor: 'pointer' }}>
          Batalkan
        </button>
      ) : null}
      {activeReport?.mode === 'test' && <small style={{ color: '#b54708', fontWeight: 600 }}>MODE TEST — tidak ada petugas yang dikirim</small>}
      {config?.recipient_text && <small style={{ color: '#475467', textAlign: 'center', maxWidth: 260 }}>{config.recipient_text}</small>}
      {error && <small role="alert" style={{ color: '#b42318' }}>{error.message}</small>}
      {showFallbackCall && (
        <a href={`tel:${config?.fallback_phone ?? '110'}`} style={{ color: '#475467', fontSize: 13 }}>
          Darurat polisi? Telepon {config?.fallback_phone ?? '110'}
        </a>
      )}
    </div>
  );
}

// ---------------------------------------------------------------- <SOSAttach>

export interface SOSAttachProps {
  /** Jenis lampiran yang ditawarkan. Default semua. */
  allow?: ('image' | 'video' | 'audio')[];
  /** Durasi maksimal rekaman suara (detik). Default 60. */
  maxAudioSeconds?: number;
  color?: string;
  className?: string;
  style?: CSSProperties;
}

const ICON: Record<'image' | 'video' | 'audio', string> = {
  image: 'M4 8h3l2-3h6l2 3h3v11H4z M12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  video: 'M3 7h12v10H3z M15 10l6-3v10l-6-3z',
  audio: 'M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3z M5 11a7 7 0 0 0 14 0 M12 18v3',
};
const Icon = ({ d }: { d: string }) => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={d} /></svg>
);

const btnStyle = (color: string): CSSProperties => ({
  flex: 1, minHeight: 48, borderRadius: 12, border: `1.5px solid ${color}`, background: 'transparent', color,
  fontWeight: 700, fontSize: 14, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, padding: '0 10px',
});

/**
 * Tombol lampiran setelah SOS terkirim: ambil foto, rekam video (kamera belakang), atau rekam suara.
 * Hanya tampil selama ada laporan aktif.
 */
export function SOSAttach({ allow = ['image', 'video', 'audio'], maxAudioSeconds = 60, color = '#dc2626', className, style }: SOSAttachProps) {
  const { activeReport, attach, attachments } = useSOS();
  const photo = useRef<HTMLInputElement>(null);
  const video = useRef<HTMLInputElement>(null);
  const rec = useRef<{ mr: MediaRecorder; t0: number; timer: ReturnType<typeof setTimeout> } | null>(null);
  const [recording, setRecording] = useState(0);
  const [recErr, setRecErr] = useState<string | null>(null);

  useEffect(() => {
    if (!recording) return;
    const t = setInterval(() => setRecording(Math.max(1, Math.round((Date.now() - rec.current!.t0) / 1000))), 500);
    return () => clearInterval(t);
  }, [recording > 0]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!activeReport || ['resolved', 'cancelled', 'false_alarm'].includes(activeReport.status)) return null;

  const pick = (e: React.ChangeEvent<HTMLInputElement>) => {
    for (const f of Array.from(e.target.files ?? [])) void attach(f, { name: f.name });
    e.target.value = '';
  };

  async function toggleRecord() {
    if (rec.current) { rec.current.mr.stop(); return; }
    setRecErr(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const type = ['audio/webm', 'audio/mp4', 'audio/ogg'].find((t) => MediaRecorder.isTypeSupported(t));
      const mr = new MediaRecorder(stream, type ? { mimeType: type } : undefined);
      const chunks: Blob[] = [];
      mr.ondataavailable = (ev) => ev.data.size && chunks.push(ev.data);
      mr.onstop = () => {
        const cur = rec.current!;
        clearTimeout(cur.timer);
        stream.getTracks().forEach((tr) => tr.stop());
        const durationS = Math.round((Date.now() - cur.t0) / 1000);
        rec.current = null;
        setRecording(0);
        const blob = new Blob(chunks, { type: (mr.mimeType || type || 'audio/webm').split(';')[0] });
        if (blob.size) void attach(blob, { durationS, name: `Rekaman ${durationS} dtk` });
      };
      mr.start();
      rec.current = { mr, t0: Date.now(), timer: setTimeout(() => mr.state === 'recording' && mr.stop(), maxAudioSeconds * 1000) };
      setRecording(1);
    } catch {
      setRecErr('Mikrofon tidak bisa dipakai. Periksa izin mikrofon di browser.');
    }
  }

  const label = { image: 'Foto', video: 'Video', audio: recording ? `Stop ${recording}s` : 'Suara' };
  return (
    <div className={className} style={{ display: 'grid', gap: 10, ...style }} aria-label="Tambah lampiran laporan">
      <div style={{ fontSize: 13, fontWeight: 600, color: '#475569' }}>Tambahkan bukti untuk petugas</div>
      <div style={{ display: 'flex', gap: 8 }}>
        {allow.includes('image') && <button type="button" style={btnStyle(color)} onClick={() => photo.current?.click()}><Icon d={ICON.image} />{label.image}</button>}
        {allow.includes('video') && <button type="button" style={btnStyle(color)} onClick={() => video.current?.click()}><Icon d={ICON.video} />{label.video}</button>}
        {allow.includes('audio') && typeof MediaRecorder !== 'undefined' && (
          <button type="button" style={{ ...btnStyle(color), ...(recording ? { background: color, color: '#fff' } : {}) }} onClick={toggleRecord} aria-pressed={!!recording}>
            <Icon d={ICON.audio} />{label.audio}
          </button>
        )}
      </div>
      <input ref={photo} type="file" accept="image/*" capture="environment" multiple hidden onChange={pick} />
      <input ref={video} type="file" accept="video/*" capture="environment" hidden onChange={pick} />
      {recErr && <div role="alert" style={{ color: '#b91c1c', fontSize: 13 }}>{recErr}</div>}
      {attachments.length > 0 && (
        <ul style={{ listStyle: 'none', margin: 0, padding: 0, display: 'grid', gap: 6 }} aria-live="polite">
          {attachments.map((a) => (
            <li key={a.key} style={{ fontSize: 13, display: 'grid', gap: 4 }}>
              <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{a.name}</span>
                <span style={{ color: a.state === 'error' ? '#b91c1c' : a.state === 'done' ? '#15803d' : '#475569', fontWeight: 600 }}>
                  {a.state === 'done' ? 'Terkirim' : a.state === 'error' ? 'Gagal' : `${Math.round(a.progress * 100)}%`}
                </span>
              </span>
              {a.state === 'uploading' && <span style={{ height: 4, borderRadius: 2, background: '#e2e8f0', overflow: 'hidden' }}><span style={{ display: 'block', height: '100%', width: `${a.progress * 100}%`, background: color, transition: 'width 200ms' }} /></span>}
              {a.error && <span style={{ color: '#b91c1c' }}>{a.error}</span>}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
