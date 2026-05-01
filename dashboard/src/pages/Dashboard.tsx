// dashboard/src/pages/Dashboard.tsx
import { useEffect, useState } from 'react';
import { ShieldCheck, ShieldAlert, Users, RadioTower, MapPin } from 'lucide-react';
import api from '../api';
import './Dashboard.css';

interface DashboardMetrics {
  active_zones: number;
  registered_tourists: number;
  active_sos: number;
  resolved_sos: number;
}

interface Location {
  tourist_id: string;
  latitude: number;
  longitude: number;
  zone_status: string;
  timestamp: string;
}

const Dashboard = () => {
  const [stats, setStats] = useState<DashboardMetrics>({
    active_zones: 0,
    registered_tourists: 0,
    active_sos: 0,
    resolved_sos: 0,
  });
  const [locations, setLocations] = useState<Location[]>([]);
  const [showLocations, setShowLocations] = useState(false);

  let authority: any = {};
  try { authority = JSON.parse(localStorage.getItem('authority') || '{}'); } catch(e) {}

  const fetchMetrics = async () => {
    try {
      const res = await api.get('/dashboard/metrics');
      setStats(res.data);
    } catch (err) {
      console.error('Failed to fetch metrics', err);
    }
  };

  const fetchLocations = async () => {
    try {
      const res = await api.get('/dashboard/locations');
      setLocations(res.data);
    } catch (err) {
      console.error('Failed to fetch locations', err);
    }
  };

  useEffect(() => {
    fetchMetrics();
    const interval = setInterval(fetchMetrics, 10000);
    return () => clearInterval(interval);
  }, []);

  const handleShowLocations = () => {
    if (!showLocations) fetchLocations();
    setShowLocations(!showLocations);
  };

  const zoneColor = (status: string) => {
    if (status === 'RESTRICTED') return '#ff2d55';
    if (status === 'CAUTION') return '#ffcc00';
    return '#00ffcc';
  };

  return (
    <div className="dashboard-container">
      <header className="page-header">
        <h1 className="neon-text-cyan">Command Center</h1>
        <p className="subtitle">
          JURISDICTION: {authority.district?.toUpperCase() || 'NATIONAL'}, {authority.jurisdiction_zone?.toUpperCase() || authority.state?.toUpperCase()}
        </p>
      </header>

      <div className="metrics-grid">
        <div className="metric-card glass-panel glitch-hover">
          <div className="metric-icon cyan"><RadioTower size={28} /></div>
          <div className="metric-details">
            <span className="metric-value">{stats.active_zones}</span>
            <span className="metric-label">Active Zones</span>
          </div>
        </div>

        <div className="metric-card glass-panel glitch-hover" style={{ cursor: 'pointer' }} onClick={handleShowLocations}>
          <div className="metric-icon green"><Users size={28} /></div>
          <div className="metric-details">
            <span className="metric-value">{stats.registered_tourists}</span>
            <span className="metric-label">Registered Tourists ↓</span>
          </div>
        </div>

        <div className="metric-card glass-panel glitch-hover" style={{ borderColor: stats.active_sos > 0 ? 'var(--accent-alert)' : ''}}>
          <div className={`metric-icon ${stats.active_sos > 0 ? 'alert' : 'muted'}`}><ShieldAlert size={28} /></div>
          <div className="metric-details">
            <span className={`metric-value ${stats.active_sos > 0 ? 'neon-text-pink' : ''}`}>{stats.active_sos}</span>
            <span className="metric-label">Active SOS</span>
          </div>
        </div>

        <div className="metric-card glass-panel glitch-hover">
          <div className="metric-icon cyan"><ShieldCheck size={28} /></div>
          <div className="metric-details">
            <span className="metric-value">{stats.resolved_sos}</span>
            <span className="metric-label">Resolved Events</span>
          </div>
        </div>
      </div>

      {showLocations && (
        <div className="tourist-tracker glass-panel mt-5">
          <h3 className="neon-text-cyan mb-4">
            <MapPin size={18} style={{ display: 'inline', marginRight: 8 }} />
            LAST KNOWN POSITIONS ({locations.length})
          </h3>
          {locations.length === 0 ? (
            <div className="empty-state">No location pings received yet.</div>
          ) : (
            <div className="location-table">
              <div className="location-header-row">
                <span>TOURIST ID</span>
                <span>LAT / LNG</span>
                <span>ZONE STATUS</span>
                <span>LAST PING</span>
              </div>
              {locations.map((loc) => (
                <div key={loc.tourist_id} className="location-row">
                  <span className="neon-text-cyan">{loc.tourist_id}</span>
                  <span>{loc.latitude?.toFixed(5)}, {loc.longitude?.toFixed(5)}</span>
                  <span style={{ color: zoneColor(loc.zone_status) }}>{loc.zone_status || '—'}</span>
                  <span style={{ opacity: 0.6 }}>{loc.timestamp ? new Date(loc.timestamp).toLocaleTimeString() : '—'}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      <div className="system-status glass-panel mt-4">
        <h3 className="neon-text-cyan">SYSTEM UPLINK</h3>
        <div className="status-indicator">
          <div className="status-dot pulsing"></div>
          <span>Connection Stable — Monitoring Active</span>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
