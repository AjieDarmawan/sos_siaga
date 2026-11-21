import { createContext, useCallback, useContext, useEffect, useId, useRef, useState, type ButtonHTMLAttributes, type ReactNode } from 'react';
import { CheckCircle, Copy, Info, Warning, WarningCircle, X } from '@phosphor-icons/react';
import type { Tone } from '../lib/format';

export function Button({ variant = 'default', size, loading, children, className = '', ...rest }:
  ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'default' | 'primary' | 'danger' | 'ghost'; size?: 'sm'; loading?: boolean }) {
  const cls = ['btn', variant !== 'default' && `btn-${variant}`, size && `btn-${size}`, className].filter(Boolean).join(' ');
  return (
    <button className={cls} disabled={loading || rest.disabled} aria-busy={loading || undefined} {...rest}>
      {loading && <span className="spinner" aria-hidden />}
      {children}
    </button>
  );
}

export function Field({ label, hint, error, children, htmlFor }: { label: ReactNode; hint?: ReactNode; error?: string; children: ReactNode; htmlFor?: string }) {
  return (
    <div className="field">
      <label htmlFor={htmlFor}>{label}</label>
      {children}
      {error ? <span className="error" role="alert" id={htmlFor ? `${htmlFor}-err` : undefined}><WarningCircle size={14} weight="bold" />{error}</span>
        : hint ? <span className="hint" id={htmlFor ? `${htmlFor}-hint` : undefined}>{hint}</span> : null}
    </div>
  );
}

/** Input + label + error, dengan aria terhubung. */
export function TextField({ label, hint, error, id, ...rest }: React.InputHTMLAttributes<HTMLInputElement> & { label: ReactNode; hint?: ReactNode; error?: string }) {
  const auto = useId();
  const fid = id ?? auto;
  return (
    <Field label={label} hint={hint} error={error} htmlFor={fid}>
      <input id={fid} className="input" aria-invalid={!!error || undefined}
        aria-describedby={error ? `${fid}-err` : hint ? `${fid}-hint` : undefined} {...rest} />
    </Field>
  );
}

export function Badge({ tone, children, dot }: { tone: Tone | 'test'; children: ReactNode; dot?: boolean }) {
  return (
    <span className={`badge badge-${tone}`}>
      {dot && <span aria-hidden style={{ width: 6, height: 6, borderRadius: 3, background: 'currentColor' }} />}
      {children}
    </span>
  );
}

export function Alert({ tone = 'info', title, children }: { tone?: 'info' | 'warn' | 'error' | 'ok'; title?: ReactNode; children?: ReactNode }) {
  const Icon = tone === 'ok' ? CheckCircle : tone === 'info' ? Info : tone === 'warn' ? Warning : WarningCircle;
  return (
    <div className={`alert alert-${tone}`} role={tone === 'error' ? 'alert' : 'status'}>
      <Icon size={18} weight="fill" />
      <div className="stack-sm" style={{ gap: 2 }}>
        {title && <strong>{title}</strong>}
        {children && <div>{children}</div>}
      </div>
    </div>
  );
}

export function Empty({ icon, title, children, action }: { icon: ReactNode; title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="empty">
      {icon}
      <h3>{title}</h3>
      {children && <p className="small" style={{ maxWidth: 360 }}>{children}</p>}
      {action}
    </div>
  );
}

export function Spinner({ label = 'Memuat' }: { label?: string }) {
  return <div className="empty" role="status"><span className="spinner" /><span className="small">{label}…</span></div>;
}

// ---------------------------------------------------------------- toast
type ToastT = { id: number; text: string; tone: 'default' | 'error' };
const ToastCtx = createContext<(text: string, tone?: ToastT['tone']) => void>(() => {});
export const useToast = () => useContext(ToastCtx);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastT[]>([]);
  const seq = useRef(0);
  const push = useCallback((text: string, tone: ToastT['tone'] = 'default') => {
    const id = ++seq.current;
    setItems((x) => [...x, { id, text, tone }]);
    setTimeout(() => setItems((x) => x.filter((t) => t.id !== id)), tone === 'error' ? 6000 : 3500);
  }, []);
  return (
    <ToastCtx.Provider value={push}>
      {children}
      <div className="toasts" aria-live="polite">
        {items.map((t) => (
          <div key={t.id} className={`toast ${t.tone === 'error' ? 'toast-error' : ''}`}>
            {t.tone === 'error' ? <WarningCircle size={18} weight="fill" /> : <CheckCircle size={18} weight="fill" />}
            <span style={{ flex: 1 }}>{t.text}</span>
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}

// ---------------------------------------------------------------- copy
export function CopyButton({ value, label = 'Salin' }: { value: string; label?: string }) {
  const [done, setDone] = useState(false);
  return (
    <Button size="sm" variant="ghost" aria-label={`${label}: ${done ? 'tersalin' : ''}`} onClick={async () => {
      await navigator.clipboard.writeText(value).catch(() => {});
      setDone(true);
      setTimeout(() => setDone(false), 1500);
    }}>
      {done ? <CheckCircle size={16} weight="bold" /> : <Copy size={16} />}
      {done ? 'Tersalin' : label}
    </Button>
  );
}

export function KeyBox({ value, mask }: { value: string; mask?: boolean }) {
  return (
    <div className="keybox">
      <code title={mask ? undefined : value}>{mask ? value.slice(0, 12) + '••••••••••••' : value}</code>
      {!mask && <CopyButton value={value} />}
    </div>
  );
}

// ---------------------------------------------------------------- modal
export function Modal({ title, onClose, children, footer }: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const titleId = useId();
  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null;
    ref.current?.querySelector<HTMLElement>('input, select, textarea, button:not([data-close])')?.focus();
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => { window.removeEventListener('keydown', onKey); prev?.focus(); };
  }, [onClose]);
  return (
    <div className="modal-scrim" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div ref={ref} className="card modal" role="dialog" aria-modal="true" aria-labelledby={titleId}>
        <div className="card-head">
          <h2 id={titleId}>{title}</h2>
          <button className="btn btn-ghost btn-icon" data-close onClick={onClose} aria-label="Tutup"><X size={18} /></button>
        </div>
        <div className="card-body">{children}</div>
        {footer && <div className="card-body" style={{ borderTop: '1px solid var(--border)', paddingTop: 16, display: 'flex', justifyContent: 'flex-end', gap: 8 }}>{footer}</div>}
      </div>
    </div>
  );
}

/** Hook data sederhana: load + reload + error. */
export function useLoad<T>(fn: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const reload = useCallback(async () => {
    setLoading(true);
    try { setData(await fn()); setError(null); } catch (e) { setError((e as Error).message); } finally { setLoading(false); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(() => { void reload(); }, [reload]);
  return { data, setData, error, loading, reload };
}
