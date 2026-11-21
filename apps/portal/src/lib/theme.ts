import { useEffect, useState } from 'react';

export type ThemeMode = 'system' | 'light' | 'dark';
export type Accent = 'slate' | 'blue' | 'violet' | 'emerald' | 'orange';
export interface ThemePrefs { mode: ThemeMode; accent: Accent }

/** Kunci yang sama dibaca skrip inline di index.html supaya tema terpasang sebelum render pertama (tanpa kedip). */
export const THEME_KEY = 'siagasos.theme';
const DEFAULT: ThemePrefs = { mode: 'system', accent: 'slate' };

export const ACCENTS: { id: Accent; label: string; swatch: string }[] = [
  { id: 'slate', label: 'Netral', swatch: '#0f172a' },
  { id: 'blue', label: 'Biru', swatch: '#1d4ed8' },
  { id: 'violet', label: 'Ungu', swatch: '#6d28d9' },
  { id: 'emerald', label: 'Hijau', swatch: '#047857' },
  { id: 'orange', label: 'Oranye', swatch: '#c2410c' },
];

export function readPrefs(): ThemePrefs {
  try { return { ...DEFAULT, ...JSON.parse(localStorage.getItem(THEME_KEY) ?? '{}') }; } catch { return DEFAULT; }
}

const mq = () => window.matchMedia('(prefers-color-scheme: dark)');
const resolve = (m: ThemeMode) => (m === 'system' ? (mq().matches ? 'dark' : 'light') : m);

export function applyPrefs(p: ThemePrefs) {
  const root = document.documentElement;
  root.dataset.theme = resolve(p.mode);
  if (p.accent === 'slate') delete root.dataset.accent; else root.dataset.accent = p.accent;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', root.dataset.theme === 'dark' ? '#0b1120' : '#ffffff');
}

const listeners = new Set<(p: ThemePrefs) => void>();

export function setPrefs(p: ThemePrefs) {
  try { localStorage.setItem(THEME_KEY, JSON.stringify(p)); } catch { /* storage diblokir: tetap berlaku di sesi ini */ }
  applyPrefs(p);
  listeners.forEach((fn) => fn(p));
}

/** Preferensi tema + setter. Mode "system" ikut berubah saat OS berganti terang/gelap. */
export function useTheme() {
  const [prefs, set] = useState(readPrefs);
  useEffect(() => {
    listeners.add(set);
    const m = mq();
    const onOs = () => { const p = readPrefs(); if (p.mode === 'system') applyPrefs(p); };
    m.addEventListener('change', onOs);
    return () => { listeners.delete(set); m.removeEventListener('change', onOs); };
  }, []);
  return { prefs, resolved: resolve(prefs.mode), setMode: (mode: ThemeMode) => setPrefs({ ...prefs, mode }), setAccent: (accent: Accent) => setPrefs({ ...prefs, accent }) };
}

/** Panggil sekali di main.tsx: terapkan preferensi & ikuti perubahan OS walau tidak ada ThemeMenu yang terpasang. */
export function initTheme() {
  applyPrefs(readPrefs());
  mq().addEventListener('change', () => { const p = readPrefs(); if (p.mode === 'system') applyPrefs(p); });
}
