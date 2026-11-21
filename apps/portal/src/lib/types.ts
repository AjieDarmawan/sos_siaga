import type { AccountStatus, DocType, ReportStatus } from '@siagasos/shared';
export type { AccountStatus, DocType, ReportStatus };

export type Role = 'owner' | 'admin' | 'responder';

export interface Me {
  user: { id: string; email: string; full_name: string; role: Role };
  account: { id: string; legal_name: string; status: AccountStatus; status_note: string | null; plan?: string; limited: boolean };
}

export interface ApiKey {
  id: string; kind: 'publishable' | 'secret'; mode: 'live' | 'test'; prefix: string; key?: string;
  revoked_at: string | null; expires_at: string | null; last_used_at: string | null; created_at: string; active: boolean;
}

export interface SdkConfig {
  categories?: string[]; button_text?: string; hold_seconds?: number; recipient_text?: string;
  fallback_phone?: string; live_location_interval_s?: number;
}

export interface App {
  id: string; name: string; allowed_origins: string[]; allowed_bundle_ids: string[]; webhook_url: string | null;
  auto_create_sources: boolean; sdk_config: SdkConfig; disabled: boolean; disabled_reason: string | null;
  created_at: string; keys: ApiKey[];
}

export interface Report {
  id: string; app_id: string; source_key: string | null; mode: 'live' | 'test'; category: string; status: ReportStatus;
  status_message: string | null; message: string | null;
  location: { lat: number; lng: number; accuracy_m: number | null } | null;
  reporter: { ref: string | null; name: string | null; phone: string | null };
  device: Record<string, unknown> | null; metadata: Record<string, unknown> | null;
  client_created_at: string | null; created_at: string; acknowledged_at: string | null; resolved_at: string | null; updated_at: string;
  /** Jumlah lampiran siap per jenis (hanya di daftar portal). */
  media_count?: Record<MediaKind, number> | null;
}

export type MediaKind = 'image' | 'video' | 'audio';
export interface ReportMedia {
  id: string; kind: MediaKind; content_type: string; size_bytes: number; duration_s: number | null;
  status: 'pending' | 'ready'; uploaded_by: 'reporter' | 'user' | 'server'; created_at: string; uploaded_at: string | null;
  url: string | null; url_expires_in: number;
}

export interface ReportDetail extends Report {
  timeline: { id: string; type: string; actor_kind: string; from_status: string | null; to_status: string | null; note: string | null; created_at: string; actor_name: string | null }[];
  locations: { lat: number; lng: number; accuracy_m: number | null; recorded_at: string }[];
  media: ReportMedia[];
}

export interface OnboardingStatus {
  status: AccountStatus; note: string | null; submitted_at: string | null; estimated_decision_by: string | null;
  in_review: boolean; required_documents: DocType[]; missing_documents: DocType[]; needs_reupload: DocType[];
  documents: { id: string; doc_type: DocType; original_name: string; mime_type: string; size_bytes: number; review_state: string; review_note: string | null; uploaded_at: string }[];
  test_mode_available: boolean;
}
