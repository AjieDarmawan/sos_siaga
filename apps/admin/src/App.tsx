import type { ReactNode } from 'react';
import { BrowserRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { ToastProvider } from '@portal/components/ui';
import { AdminAuthProvider, useAdmin } from './lib/auth';
import { AdminLayout } from './Layout';
import { LoginPage } from './pages/Login';
import { OverviewPage } from './pages/Overview';
import { AccountsPage } from './pages/Accounts';
import { AccountDetailPage } from './pages/AccountDetail';

function Guard({ children }: { children: ReactNode }) {
  const { s } = useAdmin();
  const loc = useLocation();
  return s ? <>{children}</> : <Navigate to="/login" replace state={{ from: loc.pathname }} />;
}

export function App() {
  return (
    <BrowserRouter>
      <ToastProvider>
        <AdminAuthProvider>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route element={<Guard><AdminLayout /></Guard>}>
              <Route path="/" element={<OverviewPage />} />
              <Route path="/queue" element={<AccountsPage mode="queue" />} />
              <Route path="/accounts" element={<AccountsPage mode="all" />} />
              <Route path="/accounts/:id" element={<AccountDetailPage />} />
            </Route>
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </AdminAuthProvider>
      </ToastProvider>
    </BrowserRouter>
  );
}
