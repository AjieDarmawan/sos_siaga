import { z } from 'zod';

/** Status laporan SOS. Urutan normal: open → acknowledged → in_progress → resolved. */
export const REPORT_STATUSES = ['open', 'acknowledged', 'in_progress', 'resolved', 'cancelled', 'false_alarm'] as const;
export type ReportStatus = (typeof REPORT_STATUSES)[number];
/** Status yang mengakhiri laporan: live location berhenti, SDK berhenti polling. */
export const TERMINAL_STATUSES: readonly ReportStatus[] = ['resolved', 'cancelled', 'false_alarm'];

export const ACCOUNT_STATUSES = ['pending_email', 'pending_review', 'needs_revision', 'approved', 'rejected', 'suspended'] as const;
export type AccountStatus = (typeof ACCOUNT_STATUSES)[number];

export const ENTITY_TYPES = ['pt', 'cv', 'yayasan', 'koperasi', 'lainnya'] as const;
export const DOC_TYPES = ['nib', 'npwp', 'akta', 'sk_kemenkumham', 'ktp_pic', 'surat_kuasa', 'lainnya'] as const;
export type DocType = (typeof DOC_TYPES)[number];
export const USER_ROLES = ['owner', 'admin', 'responder'] as const;
export const PLATFORMS = ['web', 'android', 'ios', 'other'] as const;
export const KEY_MODES = ['live', 'test'] as const;
export type KeyMode = (typeof KEY_MODES)[number];
export const REVIEW_DECISIONS = ['approved', 'needs_revision', 'rejected', 'suspended', 'reinstated'] as const;

export const DEFAULT_CATEGORIES = ['general', 'kriminal', 'medis', 'kebakaran', 'bencana', 'kecelakaan'] as const;
/** sos = darurat; pengaduan = laporan non-darurat (tanpa notifikasi darurat & lokasi live). */
export const REPORT_KINDS = ['sos', 'pengaduan'] as const;
export type ReportKind = (typeof REPORT_KINDS)[number];
export const DEFAULT_COMPLAINT_CATEGORIES = ['ketertiban', 'kebisingan', 'parkir_liar', 'pungli', 'kehilangan', 'patroli', 'lainnya'] as const;

// ---------- SDK payloads ----------
export const locationSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  accuracy_m: z.number().nonnegative().max(100000).optional(),
});
export type Location = z.infer<typeof locationSchema>;

/** 08xx / +62xx / 62xx / 8xx → 62xx (format nomor WhatsApp). null bila bukan nomor Indonesia yang masuk akal. */
export function toWhatsAppNumber(phone: string): string | null {
  let d = String(phone ?? '').replace(/\D/g, '');
  if (d.startsWith('0')) d = `62${d.slice(1)}`;
  else if (d.startsWith('8')) d = `62${d}`;
  return /^62[0-9]{8,13}$/.test(d) ? d : null;
}

/** Nomor WhatsApp pribadi yang dikabari saat SOS. Maks. 5 per laporan (kontak aktif di perangkat pelapor, sama dengan tata-warga). */
export const MAX_EMERGENCY_CONTACTS = 5;
export const emergencyContactSchema = z.object({
  name: z.string().trim().max(80).optional(),
  phone: z.string().max(32).transform((p, ctx) => {
    const n = toWhatsAppNumber(p);
    if (!n) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Nomor WhatsApp tidak valid (contoh 0812xxxxxxx)' });
    return n ?? p;
  }),
});
export type EmergencyContact = z.infer<typeof emergencyContactSchema>;

export const createReportSchema = z.object({
  kind: z.enum(REPORT_KINDS).default('sos'),
  source_key: z.string().min(1).max(64).regex(/^[a-z0-9][a-z0-9._-]*$/i).optional(),
  category: z.string().min(1).max(40).default('general'),
  message: z.string().max(2000).optional(),
  location: locationSchema.optional(),
  reporter: z
    .object({
      ref: z.string().max(128).optional(),
      name: z.string().max(120).optional(),
      phone: z.string().max(32).optional(),
    })
    .optional(),
  device: z
    .object({
      platform: z.enum(PLATFORMS).optional(),
      sdk_version: z.string().max(20).optional(),
      os: z.string().max(60).optional(),
      browser: z.string().max(120).optional(),
      battery: z.number().min(0).max(1).optional(),
    })
    .passthrough()
    .optional(),
  metadata: z.record(z.unknown()).optional(),
  client_created_at: z.string().datetime().optional(),
  /** Kontak darurat pribadi pelapor (hanya untuk SOS; diabaikan pada pengaduan). */
  emergency_contacts: z.array(emergencyContactSchema).max(MAX_EMERGENCY_CONTACTS).optional(),
}).refine((v) => v.kind !== 'pengaduan' || (v.message?.trim().length ?? 0) >= 5, {
  message: 'Pengaduan wajib berisi uraian (minimal 5 karakter)', path: ['message'],
});
export type CreateReportInput = z.input<typeof createReportSchema>;

export const locationUpdateSchema = locationSchema.extend({ recorded_at: z.string().datetime().optional() });

export interface ReportPublic {
  id: string;
  kind: ReportKind;
  status: ReportStatus;
  mode: KeyMode;
  category: string;
  created_at: string;
  acknowledged_at: string | null;
  resolved_at: string | null;
  /** Teks yang aman ditampilkan ke pengguna akhir, misalnya "Tim keamanan sedang menuju lokasi". */
  status_message: string | null;
}

export interface SdkConfig {
  app_name: string;
  mode: KeyMode;
  categories: string[];
  /** Kategori menu "Laporan pengaduan" (slug, maks 40 karakter). */
  complaint_categories: string[];
  button_text: string;
  hold_seconds: number;
  /** Teks wajib agar pengguna tahu laporan tidak dikirim ke 110. */
  recipient_text: string;
  fallback_phone: string;
  live_location_interval_s: number;
}

// ---------- Portal / server payloads ----------
export const updateReportSchema = z
  .object({
    status: z.enum(REPORT_STATUSES).optional(),
    note: z.string().min(1).max(2000).optional(),
  })
  .refine((v) => v.status || v.note, { message: 'status atau note wajib diisi' });

export interface ApiErrorBody {
  error: { code: string; message: string; details?: unknown };
}
