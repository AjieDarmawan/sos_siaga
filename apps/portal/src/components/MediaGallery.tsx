import { useEffect, useRef, useState } from 'react';
import { CaretLeft, CaretRight, FileArrowUp, Image as ImageIcon, Microphone, Paperclip, VideoCamera, X } from '@phosphor-icons/react';
import { api } from '../lib/api';
import { fmtBytes, fmtTime } from '../lib/format';
import type { MediaKind, ReportMedia } from '../lib/types';
import { Button, useToast } from './ui';

export const MEDIA_ICON: Record<MediaKind, typeof ImageIcon> = { image: ImageIcon, video: VideoCamera, audio: Microphone };
const KIND_LABEL: Record<MediaKind, string> = { image: 'Foto', video: 'Video', audio: 'Suara' };
const fmtDur = (s: number | null) => (s == null ? '' : `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, '0')}`);

/** Ringkas jumlah lampiran per jenis, dipakai di daftar laporan. */
export function MediaBadges({ count }: { count?: Record<MediaKind, number> | null }) {
  if (!count) return null;
  const items = (Object.keys(count) as MediaKind[]).filter((k) => count[k]);
  if (!items.length) return null;
  return (
    <span className="row media-badges" style={{ gap: 6 }} aria-label={items.map((k) => `${count[k]} ${KIND_LABEL[k].toLowerCase()}`).join(', ')}>
      {items.map((k) => { const I = MEDIA_ICON[k]; return <span key={k} className="row" style={{ gap: 2 }}><I size={13} weight="bold" />{count[k]}</span>; })}
    </span>
  );
}

/**
 * Galeri lampiran laporan. URL bertanda tangan berlaku ±15 menit; bila kedaluwarsa (error memuat), `onExpired` memuat ulang detail.
 */
export function MediaGallery({ reportId, media, onExpired, canUpload }: { reportId: string; media: ReportMedia[]; onExpired: () => void; canUpload: boolean }) {
  const [viewer, setViewer] = useState<number | null>(null);
  const images = media.filter((m) => m.kind === 'image' && m.url);
  const others = media.filter((m) => m.kind !== 'image');
  const expiredOnce = useRef(false);
  const expired = () => { if (!expiredOnce.current) { expiredOnce.current = true; onExpired(); } };
  useEffect(() => { expiredOnce.current = false; }, [media]);

  return (
    <div className="stack-sm">
      <div className="row-between">
        <h3 className="row" style={{ gap: 6 }}><Paperclip size={16} />Lampiran {media.length > 0 && <span className="muted small">({media.length})</span>}</h3>
        {canUpload && <UploadButton reportId={reportId} />}
      </div>
      {!media.length ? <p className="small muted">Belum ada foto, video, atau rekaman suara.</p> : (
        <>
          {images.length > 0 && (
            <div className="media-grid">
              {images.map((m, i) => (
                <button key={m.id} className="media-thumb" onClick={() => setViewer(i)} aria-label={`Buka foto ${i + 1} dari ${images.length}`}>
                  <img src={m.url!} alt={`Foto lampiran ${i + 1}`} loading="lazy" onError={expired} />
                  {m.uploaded_by === 'user' && <span className="media-by">Petugas</span>}
                </button>
              ))}
            </div>
          )}
          {others.map((m) => (
            <div key={m.id} className="media-item">
              <div className="row-between small" style={{ flexWrap: 'nowrap' }}>
                <span className="row" style={{ gap: 6 }}>
                  {m.kind === 'video' ? <VideoCamera size={15} /> : <Microphone size={15} />}
                  <b>{KIND_LABEL[m.kind]}</b>{m.duration_s != null && <span className="muted">{fmtDur(m.duration_s)}</span>}
                  {m.uploaded_by === 'user' && <span className="badge badge-info">Petugas</span>}
                </span>
                <span className="muted">{fmtBytes(m.size_bytes)} · {fmtTime(m.uploaded_at ?? m.created_at)}</span>
              </div>
              {m.url && (m.kind === 'video'
                ? <video src={m.url} controls preload="metadata" playsInline onError={expired} />
                : <audio src={m.url} controls preload="metadata" onError={expired} />)}
            </div>
          ))}
        </>
      )}
      {viewer != null && images[viewer] && <Lightbox images={images} index={viewer} onIndex={setViewer} onClose={() => setViewer(null)} />}
    </div>
  );
}

function Lightbox({ images, index, onIndex, onClose }: { images: ReportMedia[]; index: number; onIndex: (i: number) => void; onClose: () => void }) {
  const m = images[index]!;
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.stopPropagation(); onClose(); }
      if (e.key === 'ArrowRight') onIndex((index + 1) % images.length);
      if (e.key === 'ArrowLeft') onIndex((index - 1 + images.length) % images.length);
    };
    window.addEventListener('keydown', k, true);
    return () => window.removeEventListener('keydown', k, true);
  }, [index, images.length, onClose, onIndex]);
  return (
    <div className="lightbox" role="dialog" aria-modal="true" aria-label={`Foto ${index + 1} dari ${images.length}`} onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <img src={m.url!} alt={`Foto lampiran ${index + 1}`} />
      <button className="lb-btn lb-close" onClick={onClose} aria-label="Tutup"><X size={22} /></button>
      {images.length > 1 && <>
        <button className="lb-btn lb-prev" onClick={() => onIndex((index - 1 + images.length) % images.length)} aria-label="Sebelumnya"><CaretLeft size={24} /></button>
        <button className="lb-btn lb-next" onClick={() => onIndex((index + 1) % images.length)} aria-label="Berikutnya"><CaretRight size={24} /></button>
      </>}
      <span className="lb-count">{index + 1} / {images.length} · {fmtTime(m.uploaded_at ?? m.created_at)}</span>
    </div>
  );
}

/** Petugas melampirkan file (dokumentasi lokasi). Sama seperti SDK: minta presigned PUT, unggah langsung ke storage, konfirmasi. */
function UploadButton({ reportId }: { reportId: string }) {
  const input = useRef<HTMLInputElement>(null);
  const [progress, setProgress] = useState<number | null>(null);
  const toast = useToast();

  async function upload(file: File) {
    setProgress(0);
    try {
      const out = await api<{ media: { id: string }; upload: { url: string; headers: Record<string, string> } }>(
        `/portal/reports/${reportId}/media`, { body: { content_type: file.type || 'application/octet-stream', size_bytes: file.size } });
      await new Promise<void>((resolve, reject) => {
        const x = new XMLHttpRequest();
        x.open('PUT', out.upload.url);
        for (const [k, v] of Object.entries(out.upload.headers)) x.setRequestHeader(k, v);
        x.upload.onprogress = (e) => e.lengthComputable && setProgress(e.loaded / e.total);
        x.onload = () => (x.status < 300 ? resolve() : reject(new Error(`Upload gagal (${x.status})`)));
        x.onerror = () => reject(new Error('Upload gagal: koneksi terputus'));
        x.send(file);
      });
      await api(`/portal/reports/${reportId}/media/${out.media.id}/complete`, { method: 'POST' });
      toast('Lampiran ditambahkan');
    } catch (e) {
      toast((e as Error).message, 'error');
    } finally {
      setProgress(null);
      if (input.current) input.current.value = '';
    }
  }

  return (
    <>
      <input ref={input} type="file" hidden accept="image/*,video/*,audio/*" onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])} />
      <Button size="sm" variant="ghost" onClick={() => input.current?.click()} loading={progress != null} aria-label="Lampirkan file">
        <FileArrowUp size={14} />{progress != null ? `${Math.round(progress * 100)}%` : 'Lampirkan'}
      </Button>
    </>
  );
}
