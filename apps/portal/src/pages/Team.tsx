import { useState, type FormEvent } from 'react';
import { UserPlus, UsersThree } from '@phosphor-icons/react';
import { api, ApiError } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtDate } from '../lib/format';
import type { Role } from '../lib/types';
import { Alert, Badge, Button, Empty, Field, KeyBox, Spinner, TextField, useLoad, useToast } from '../components/ui';

interface Member { id: string; email: string; full_name: string; phone: string | null; role: Role; disabled_at: string | null; created_at: string }
interface Invite { id: string; email: string; role: Role; expires_at: string; created_at: string }

const ROLE_LABEL: Record<Role, string> = { owner: 'Pemilik', admin: 'Admin', responder: 'Responder' };
const ROLE_HINT: Record<'admin' | 'responder', string> = {
  admin: 'Kelola app, kunci, tim, dan laporan',
  responder: 'Hanya dashboard laporan: menerima & menangani SOS',
};

export function TeamPage() {
  const { me, can } = useAuth();
  const toast = useToast();
  const { data, loading, error, reload } = useLoad(() => api<{ members: Member[]; pending_invites: Invite[] }>('/portal/team'));
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<'admin' | 'responder'>('responder');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [devLink, setDevLink] = useState<string | null>(null);
  const isOwner = can('owner');

  async function invite(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const r = await api<{ dev_invite_token?: string }>('/portal/team/invites', { body: { email: email.trim(), role } });
      toast(`Undangan dikirim ke ${email}`);
      setDevLink(r.dev_invite_token ? `${location.origin}/accept-invite?token=${r.dev_invite_token}` : null);
      setEmail('');
      void reload();
    } catch (e) {
      setErr(e instanceof ApiError ? e.detailMessage : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function update(m: Member, body: { role?: Role; disabled?: boolean }) {
    try {
      await api(`/portal/team/${m.id}`, { method: 'PATCH', body });
      toast('Anggota diperbarui');
      void reload();
    } catch (e) { toast((e as Error).message, 'error'); }
  }

  async function revoke(i: Invite) {
    try { await api(`/portal/team/invites/${i.id}`, { method: 'DELETE' }); toast('Undangan dicabut'); void reload(); }
    catch (e) { toast((e as Error).message, 'error'); }
  }

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h1>Tim</h1>
          <p>Undang responder yang akan menerima laporan SOS di dashboard.</p>
        </div>
      </div>

      <form className="card card-pad stack" onSubmit={invite}>
        <h2>Undang anggota</h2>
        {err && <Alert tone="error">{err}</Alert>}
        <div className="row" style={{ alignItems: 'flex-end' }}>
          <div style={{ flex: '2 1 240px' }}><TextField label="Email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></div>
          <div style={{ flex: '1 1 200px' }}>
            <Field label="Peran" htmlFor="role" hint={ROLE_HINT[role]}>
              <select id="role" className="select" value={role} onChange={(e) => setRole(e.target.value as typeof role)}>
                <option value="responder">Responder</option>
                {isOwner && <option value="admin">Admin</option>}
              </select>
            </Field>
          </div>
          <Button variant="primary" type="submit" loading={busy} disabled={!email} style={{ marginBottom: 22 }}><UserPlus size={16} />Kirim undangan</Button>
        </div>
        {devLink && <Alert tone="info" title="Mode pengembangan: tautan undangan"><KeyBox value={devLink} /></Alert>}
      </form>

      <div className="card table-wrap">
        {loading && !data ? <Spinner /> : error ? <Alert tone="error">{error}</Alert> : !data?.members.length ? <Empty icon={<UsersThree size={36} />} title="Belum ada anggota" /> : (
          <table className="table">
            <thead><tr><th>Nama</th><th>Peran</th><th>Status</th><th>Bergabung</th>{isOwner && <th />}</tr></thead>
            <tbody>
              {data.members.map((m) => {
                const editable = isOwner && m.role !== 'owner' && m.id !== me?.user.id;
                return (
                  <tr key={m.id} style={{ opacity: m.disabled_at ? 0.6 : 1 }}>
                    <td><strong>{m.full_name}</strong><div className="small muted">{m.email}</div></td>
                    <td>
                      {editable ? (
                        <select className="select" style={{ minHeight: 34, padding: '4px 8px', width: 'auto' }} aria-label={`Peran ${m.full_name}`}
                          value={m.role} onChange={(e) => update(m, { role: e.target.value as Role })}>
                          <option value="admin">Admin</option><option value="responder">Responder</option>
                        </select>
                      ) : ROLE_LABEL[m.role]}
                    </td>
                    <td>{m.disabled_at ? <Badge tone="muted">Nonaktif</Badge> : <Badge tone="ok">Aktif</Badge>}</td>
                    <td className="small muted">{fmtDate(m.created_at)}</td>
                    {isOwner && (
                      <td style={{ textAlign: 'right' }}>
                        {editable && <Button size="sm" variant="ghost" onClick={() => update(m, { disabled: !m.disabled_at })}>{m.disabled_at ? 'Aktifkan' : 'Nonaktifkan'}</Button>}
                      </td>
                    )}
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {!!data?.pending_invites.length && (
        <div className="card">
          <div className="card-head"><h2>Undangan tertunda</h2></div>
          <div className="table-wrap">
            <table className="table">
              <tbody>
                {data.pending_invites.map((i) => (
                  <tr key={i.id}>
                    <td>{i.email}</td><td>{ROLE_LABEL[i.role]}</td><td className="small muted">Berlaku s.d. {fmtDate(i.expires_at)}</td>
                    <td style={{ textAlign: 'right' }}><Button size="sm" variant="ghost" onClick={() => revoke(i)}>Cabut</Button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
