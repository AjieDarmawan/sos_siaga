/**
 * Bunyi alert laporan baru via Web Audio (tanpa file aset).
 * Browser memblokir audio sebelum ada interaksi pengguna, jadi `unlock()` harus dipanggil dari klik.
 */
let ctx: AudioContext | null = null;

export function audioReady() {
  return ctx?.state === 'running';
}

export async function unlock() {
  ctx ??= new AudioContext();
  if (ctx.state !== 'running') await ctx.resume();
  return audioReady();
}

/** Dua nada naik-turun ala sirine, ±1,2 detik. */
export function playAlarm(times = 2) {
  if (!ctx || ctx.state !== 'running') return false;
  const t0 = ctx.currentTime;
  for (let i = 0; i < times; i++) {
    for (const [j, f] of [880, 660].entries()) {
      const start = t0 + i * 0.6 + j * 0.3;
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = 'square';
      o.frequency.setValueAtTime(f, start);
      g.gain.setValueAtTime(0.0001, start);
      g.gain.exponentialRampToValueAtTime(0.18, start + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, start + 0.27);
      o.connect(g).connect(ctx.destination);
      o.start(start);
      o.stop(start + 0.3);
    }
  }
  return true;
}
