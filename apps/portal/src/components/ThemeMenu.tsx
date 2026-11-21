import { useEffect, useId, useRef, useState } from 'react';
import { Check, Desktop, Moon, Palette, Sun } from '@phosphor-icons/react';
import { ACCENTS, useTheme, type ThemeMode } from '../lib/theme';

const MODES: { id: ThemeMode; label: string; icon: typeof Sun }[] = [
  { id: 'light', label: 'Terang', icon: Sun },
  { id: 'dark', label: 'Gelap', icon: Moon },
  { id: 'system', label: 'Sistem', icon: Desktop },
];

/**
 * Tombol pengaturan tampilan: mode terang/gelap/ikut sistem + warna aksen.
 * `variant="dark"` untuk dipasang di atas latar gelap (navbar landing).
 */
export function ThemeMenu({ variant = 'default', placement = 'down', withLabel }: { variant?: 'default' | 'dark'; placement?: 'down' | 'up'; withLabel?: boolean }) {
  const { prefs, resolved, setMode, setAccent } = useTheme();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const id = useId();

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => !ref.current?.contains(e.target as Node) && setOpen(false);
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('mousedown', onDown); document.removeEventListener('keydown', onKey); };
  }, [open]);

  const Icon = resolved === 'dark' ? Moon : Sun;
  return (
    <div className={`theme-menu tm-${variant}`} ref={ref}>
      <button type="button" className={`tm-trigger ${withLabel ? 'with-label' : ''}`} aria-haspopup="dialog" aria-expanded={open} aria-controls={id}
        aria-label="Tampilan: tema & warna" title="Tampilan: tema & warna" onClick={() => setOpen(!open)}>
        <Icon size={18} weight="bold" />{withLabel && <span>Tampilan</span>}
      </button>
      {open && (
        <div id={id} role="dialog" aria-label="Pengaturan tampilan" className={`tm-pop tm-${placement}`}>
          <p className="tm-title">Tema</p>
          <div className="tm-modes" role="radiogroup" aria-label="Mode tema">
            {MODES.map(({ id: m, label, icon: I }) => (
              <button key={m} type="button" role="radio" aria-checked={prefs.mode === m} onClick={() => setMode(m)}>
                <I size={18} weight={prefs.mode === m ? 'fill' : 'regular'} />{label}
              </button>
            ))}
          </div>
          <p className="tm-title"><Palette size={14} weight="bold" />Warna aksen</p>
          <div className="tm-accents" role="radiogroup" aria-label="Warna aksen">
            {ACCENTS.map((a) => (
              <button key={a.id} type="button" role="radio" aria-checked={prefs.accent === a.id} aria-label={a.label} title={a.label}
                style={{ ['--sw' as string]: a.swatch }} onClick={() => setAccent(a.id)}>
                {prefs.accent === a.id && <Check size={14} weight="bold" />}
              </button>
            ))}
          </div>
          <p className="tm-note">Merah dikhususkan untuk tanda darurat.</p>
        </div>
      )}
    </div>
  );
}
