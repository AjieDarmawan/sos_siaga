import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { api, setUnauthorizedHandler, tokenStore } from './api';
import type { Me, Role } from './types';

interface AuthCtx {
  me: Me | null;
  loading: boolean;
  signIn(token: string): Promise<Me>;
  signOut(): void;
  refresh(): Promise<void>;
  can(...roles: Role[]): boolean;
}

const Ctx = createContext<AuthCtx | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(!!tokenStore.get());

  const signOut = useCallback(() => {
    tokenStore.set(null);
    setMe(null);
  }, []);

  const refresh = useCallback(async () => {
    if (!tokenStore.get()) return;
    try {
      setMe(await api<Me>('/portal/me'));
    } catch {
      signOut();
    } finally {
      setLoading(false);
    }
  }, [signOut]);

  useEffect(() => {
    setUnauthorizedHandler(signOut);
    void refresh();
  }, [refresh, signOut]);

  const signIn = useCallback(async (token: string) => {
    tokenStore.set(token);
    const m = await api<Me>('/portal/me');
    setMe(m);
    return m;
  }, []);

  const value = useMemo<AuthCtx>(() => ({
    me, loading, signIn, signOut, refresh,
    can: (...roles) => !!me && roles.includes(me.user.role),
  }), [me, loading, signIn, signOut, refresh]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAuth() {
  const c = useContext(Ctx);
  if (!c) throw new Error('useAuth di luar AuthProvider');
  return c;
}

/** Halaman awal sesuai peran: responder langsung ke dashboard. */
export const homeFor = (m: Me) => (m.user.role === 'responder' ? '/dashboard' : m.account.limited ? '/onboarding' : '/dashboard');
