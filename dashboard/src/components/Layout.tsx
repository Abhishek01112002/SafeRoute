import { useCallback, useEffect, useState } from 'react';
import { Outlet, NavLink } from 'react-router-dom';
import {
  Activity,
  AlertCircle,
  CheckCircle2,
  Cloud,
  Database,
  HardDrive,
  LayoutDashboard,
  LogOut,
  Map,
  RefreshCw,
  ShieldAlert,
} from 'lucide-react';
import {
  API_BASE_URL,
  POLL_INTERVAL_MS,
  fetchReadiness,
  getErrorMessage,
  type Readiness,
} from '../api';
import './Layout.css';

const formatTime = (value?: string) => {
  if (!value) return 'Never';
  return new Date(value).toLocaleTimeString();
};

const readinessCheck = (readiness: Readiness | null, key: string) =>
  Boolean(readiness?.checks?.[key]);

const Layout = () => {
  const [readiness, setReadiness] = useState<Readiness | null>(null);
  const [lastRefresh, setLastRefresh] = useState<string | undefined>();
  const [statusError, setStatusError] = useState('');
  const [refreshing, setRefreshing] = useState(false);
  const [clock, setClock] = useState(() => new Date());

  const refreshStatus = useCallback(async () => {
    setRefreshing(true);
    setStatusError('');
    try {
      const next = await fetchReadiness();
      setReadiness(next);
      setLastRefresh(new Date().toISOString());
    } catch (error) {
      setStatusError(getErrorMessage(error));
    } finally {
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void Promise.resolve().then(refreshStatus);
    const interval = window.setInterval(refreshStatus, POLL_INTERVAL_MS);
    return () => window.clearInterval(interval);
  }, [refreshStatus]);

  useEffect(() => {
    const interval = window.setInterval(() => setClock(new Date()), 1000);
    return () => window.clearInterval(interval);
  }, []);

  const handleManualRefresh = () => {
    refreshStatus();
    window.dispatchEvent(new Event('saferoute:manual-refresh'));
  };

  const handleLogout = () => {
    localStorage.removeItem('token');
    localStorage.removeItem('authority');
    window.location.href = '/login';
  };

  const isReady = readiness?.status === 'ready' && !statusError;

  return (
    <div className="layout-container">
      <aside className="sidebar">
        <div className="sidebar-header">
          <div className="brand-mark">
            <LayoutDashboard size={22} />
          </div>
          <div>
            <h2>SafeRoute</h2>
            <span>Control Room</span>
          </div>
        </div>

        <div className="live-ops-card">
          <span className="live-label">LIVE OPERATIONS</span>
          <strong>{clock.toLocaleTimeString()}</strong>
          <small>IST command watch</small>
        </div>

        <nav className="sidebar-nav" aria-label="Primary navigation">
          <NavLink to="/" className={({ isActive }) => (isActive ? 'nav-item active' : 'nav-item')}>
            <Activity size={19} />
            <span>Overview</span>
          </NavLink>
          <NavLink to="/zones" className={({ isActive }) => (isActive ? 'nav-item active' : 'nav-item')}>
            <Map size={19} />
            <span>Zones</span>
          </NavLink>
          <NavLink to="/sos" className={({ isActive }) => (isActive ? 'nav-item active' : 'nav-item')}>
            <ShieldAlert size={19} />
            <span>SOS Triage</span>
          </NavLink>
        </nav>

        <div className="side-telemetry">
          <h3>System Checks</h3>
          <div className="telemetry-row">
            <Database size={15} />
            <span>Database</span>
            <i className={readinessCheck(readiness, 'db') ? 'ok' : 'warn'} />
          </div>
          <div className="telemetry-row">
            <Cloud size={15} />
            <span>Cache</span>
            <i className={readinessCheck(readiness, 'redis') ? 'ok' : 'warn'} />
          </div>
          <div className="telemetry-row">
            <HardDrive size={15} />
            <span>Media store</span>
            <i className={readinessCheck(readiness, 'minio') ? 'ok' : 'warn'} />
          </div>
        </div>

        <div className="sidebar-footer">
          <button className="nav-item logout-btn" onClick={handleLogout}>
            <LogOut size={19} />
            <span>Sign out</span>
          </button>
        </div>
      </aside>

      <div className="workspace">
        <header className="top-status-bar">
          <div className="status-group">
            <span className="command-chip">CONTROL ROOM LIVE</span>
            <span className={`system-pill ${isReady ? 'ready' : 'degraded'}`}>
              {isReady ? <CheckCircle2 size={15} /> : <AlertCircle size={15} />}
              {isReady ? 'Backend ready' : 'Backend degraded'}
            </span>
            <span className="status-meta">API {API_BASE_URL}</span>
            <span className="status-meta">Last refresh {formatTime(lastRefresh)}</span>
            <span className="status-meta">Polling every {POLL_INTERVAL_MS / 1000}s</span>
          </div>

          {statusError && <span className="status-error">{statusError}</span>}

          <button className="refresh-button" onClick={handleManualRefresh} disabled={refreshing}>
            <RefreshCw size={16} className={refreshing ? 'spinning' : ''} />
            Refresh
          </button>
        </header>

        <main className="main-content">
          <Outlet />
        </main>
      </div>
    </div>
  );
};

export default Layout;
