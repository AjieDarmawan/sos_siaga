import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState,
  type CSSProperties, type ReactNode,
} from 'react';
import { SiagaSOS, SiagaSOSError, type ActiveReport, type SiagaSOSOptions, type TriggerInput, type SdkConfig } from '@siagasos/js';

export type { ActiveReport, TriggerInput, SdkConfig } from '@siagasos/js';
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

  const value = useMemo<SOSContextValue>(() => ({
    client, config, activeReport, error, trigger, cancel,
    status: sending ? 'sending' : activeReport?.status ?? 'idle',
    reset: () => { setActive(null); setError(null); },
  }), [client, config, activeReport, error, trigger, cancel, sending]);

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
