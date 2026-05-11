// dashboard/src/App.tsx
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import type { ReactNode } from 'react';
import Layout from './components/Layout';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Zones from './pages/Zones';
import SOS from './pages/SOS';
import {
  getLandingPath,
  hasAnyDashboardPermission,
  hasPermission,
  readAuthoritySession,
  type DashboardPermission,
} from './auth';

const PermissionRoute = ({
  permission,
  children,
}: {
  permission: DashboardPermission;
  children: ReactNode;
}) => {
  const session = readAuthoritySession();
  const token = localStorage.getItem('token');

  if (!token) return <Navigate to="/login" replace />;
  if (!hasPermission(session, permission)) {
    return (
      <div className="page-state">
        This authority account does not have permission to open this dashboard area.
      </div>
    );
  }

  return children;
};

function App() {
  const session = readAuthoritySession();
  const isAuthenticated = !!localStorage.getItem('token') && hasAnyDashboardPermission(session);
  const landingPath = getLandingPath(session);

  return (
    <Router>
      <Routes>
        <Route path="/login" element={!isAuthenticated ? <Login /> : <Navigate to={landingPath} replace />} />

        <Route path="/" element={isAuthenticated ? <Layout /> : <Navigate to="/login" />}>
          <Route
            index
            element={
              <PermissionRoute permission="overview:view">
                <Dashboard />
              </PermissionRoute>
            }
          />
          <Route
            path="zones"
            element={
              <PermissionRoute permission="zones:view">
                <Zones />
              </PermissionRoute>
            }
          />
          <Route
            path="sos"
            element={
              <PermissionRoute permission="sos:view">
                <SOS />
              </PermissionRoute>
            }
          />
        </Route>
      </Routes>
    </Router>
  );
}

export default App;
