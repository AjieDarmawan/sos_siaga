import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { CheckCircle } from '@phosphor-icons/react';
import { BrandMark } from './Layout';
import { ThemeMenu } from './ThemeMenu';

export function AuthLayout({ children, wide }: { children: ReactNode; wide?: boolean }) {
  return (
    <div className="auth">
      <aside className="auth-aside">
        <Link to="/" className="brand"><BrandMark />SiagaSOS</Link>
        <div style={{ marginTop: 'auto', display: 'grid', gap: 24 }}>
          <h2>Tombol darurat untuk aplikasi Anda, tanpa membangun pusat komando sendiri.</h2>
          <ul>
            <li><CheckCircle size={20} weight="fill" />Pasang SDK web atau Android dalam hitungan menit.</li>
            <li><CheckCircle size={20} weight="fill" />Laporan masuk realtime ke dashboard tim responder Anda, lengkap dengan lokasi.</li>
            <li><CheckCircle size={20} weight="fill" />Mulai dengan kunci test sekarang. Kunci live aktif setelah dokumen perusahaan diverifikasi (±2 hari kerja).</li>
          </ul>
        </div>
        <p className="small" style={{ color: '#94a3b8' }}>Dalam keadaan darurat langsung, hubungi 110 / 112.</p>
      </aside>
      <div className="auth-main" style={{ position: 'relative' }}>
        <div style={{ position: 'absolute', top: 16, right: 16 }}><ThemeMenu /></div>
        <div className={`auth-card ${wide ? 'wide' : ''}`}>{children}</div>
      </div>
    </div>
  );
}
