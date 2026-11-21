import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { api, session, setExpiredHandler, type AdminSession } from './api';

interface Ctx { s: AdminSession | null; signIn(email: string, password: string, totp: string): Promise<void>; signOut(): void }
const C = createContext<Ctx | null>(null);

export function AdminAuthProvider({ children }: { children: ReactNode }) {
  const [s, setS] = useState(session.get);
  const signOut = useCallback(() => { session.set(null); setS(null); }, []);
  useEffect(() => setExpiredHandler(signOut), [signOut]);
  const signIn = useCallback(async (email: string, password: string, totp: string) => {
    const r = await api<AdminSession>('/admin/auth/login', { body: { email, password, totp } });
    session.set(r);
    setS(r);
  }, []);
  const v = useMemo(() => ({ s, signIn, signOut }), [s, signIn, signOut]);
  return <C.Provider value={v}>{children}</C.Provider>;
}

export function useAdmin() {
  const c = useContext(C);
  if (!c) throw new Error('useAdmin di luar provider');
  return c;
}
