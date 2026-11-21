import { lazy, Suspense, type ReactNode } from 'react';
import { BrowserRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { AuthProvider, useAuth } from './lib/auth';
import type { Role } from './lib/types';
import { Spinner, ToastProvider } from './components/ui';
import { Layout } from './components/Layout';
import { LandingPage } from './pages/Landing';
import { LoginPage } from './pages/Login';
import { RegisterPage } from './pages/Register';
import { VerifyEmailPage } from './pages/VerifyEmail';
import { AcceptInvitePage } from './pages/AcceptInvite';

// Halaman setelah login dimuat terpisah: Leaflet hanya diunduh saat membuka dashboard.
const OnboardingPage = lazy(() => import('./pages/Onboarding').then((m) => ({ default: m.OnboardingPage })));
const AppsPage = lazy(() => import('./pages/Apps').then((m) => ({ default: m.AppsPage })));
const AppDetailPage = lazy(() => import('./pages/AppDetail').then((m) => ({ default: m.AppDetailPage })));
const DashboardPage = lazy(() => import('./pages/Dashboard').then((m) => ({ default: m.DashboardPage })));
const DocsPage = lazy(() => import('./pages/Docs').then((m) => ({ default: m.DocsPage })));
const TeamPage = lazy(() => import('./pages/Team').then((m) => ({ default: m.TeamPage })));

function Protected({ children, roles }: { children: ReactNode; roles?: Role[] }) {
  const { me, loading } = useAuth();
  const loc = useLocation();
  if (loading) return <Spinner label="Memeriksa sesi" />;
  if (!me) return <Navigate to="/login" replace state={{ from: loc.pathname }} />;
  if (roles && !roles.includes(me.user.role)) return <Navigate to="/dashboard" replace />;
  return <>{children}</>;
}

export function App() {
  return (
    <BrowserRouter>
      <ToastProvider>
        <AuthProvider>
          <Routes>
            <Route path="/" element={<LandingPage />} />
            <Route path="/docs" element={<Suspense fallback={<Spinner />}><DocsPage /></Suspense>} />
            <Route path="/login" element={<LoginPage />} />
            <Route path="/register" element={<RegisterPage />} />
            <Route path="/verify-email" element={<VerifyEmailPage />} />
            <Route path="/accept-invite" element={<AcceptInvitePage />} />
            <Route element={<Protected><Layout /></Protected>}>
              <Route path="/dashboard" element={<DashboardPage />} />
              <Route path="/onboarding" element={<Protected roles={['owner', 'admin']}><OnboardingPage /></Protected>} />
              <Route path="/apps" element={<Protected roles={['owner', 'admin']}><AppsPage /></Protected>} />
              <Route path="/apps/:id" element={<Protected roles={['owner', 'admin']}><AppDetailPage /></Protected>} />
              <Route path="/team" element={<Protected roles={['owner', 'admin']}><TeamPage /></Protected>} />
            </Route>
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </AuthProvider>
      </ToastProvider>
    </BrowserRouter>
  );
}
