// dashboard/src/pages/Dashboard.tsx
import { useEffect, useState } from 'react';
import { ShieldCheck, ShieldAlert, Users, RadioTower } from 'lucide-react';
import api from '../api';
import './Dashboard.css';

interface DashboardStats {
  activeZones: number;
  activeTourists: number;
  activeSOS: number;
  resolvedSOS: number;
}

const Dashboard = () => {
  const [stats, setStats] = useState<DashboardStats>({
    activeZones: 0,
    activeTourists: 0,
    activeSOS: 0,
    resolvedSOS: 0
  });

  let authority: any = {};
  try {
    authority = JSON.parse(localStorage.getItem('authority') || '{}');
  } catch(e) {}

  useEffect(() => {
    // In a real scenario, this would be a single /metrics endpoint
    // We'll mock the aggregated numbers here based on available API
    const fetchStats = async () => {
      try {
        const [zonesRes, sosRes] = await Promise.all([
          api.get('/zones/active'),
          api.get('/sos/events')
        ]);
        
        const sosData = sosRes.data as any[];
        const activeSosCount = sosData.filter(s => s.status === 'ACTIVE').length;
        const resolvedSosCount = sosData.filter(s => s.status === 'RESOLVED').length;

        setStats({
          activeZones: zonesRes.data.length || 0,
          activeTourists: 142, // Mocked for UI purposes until /tourists is ready
          activeSOS: activeSosCount,
          resolvedSOS: resolvedSosCount
        });
      } catch (err) {
        console.error('Failed to fetch dashboard metrics', err);
      }
    };

    fetchStats();
    const interval = setInterval(fetchStats, 10000); // Poll every 10s
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="dashboard-container">
      <header className="page-header">
        <h1 className="neon-text-cyan">Global Overview</h1>
        <p className="subtitle">
          JURISDICTION: {authority.district?.toUpperCase() || 'UNKNOWN'}, {authority.state?.toUpperCase()}
        </p>
      </header>

      <div className="metrics-grid">
        <div className="metric-card glass-panel glitch-hover">
          <div className="metric-icon cyan"><RadioTower size={28} /></div>
          <div className="metric-details">
            <span className="metric-value">{stats.activeZones}</span>
            <span className="metric-label">Monitored Zones</span>
          </div>
        </div>

        <div className="metric-card glass-panel glitch-hover">
          <div className="metric-icon green"><Users size={28} /></div>
          <div className="metric-details">
            <span className="metric-value">{stats.activeTourists}</span>
            <span className="metric-label">Active Tourists</span>
          </div>
        </div>

        <div className="metric-card glass-panel glitch-hover" style={{ borderColor: stats.activeSOS > 0 ? 'var(--accent-alert)' : ''}}>
          <div className={`metric-icon ${stats.activeSOS > 0 ? 'alert' : 'muted'}`}><ShieldAlert size={28} /></div>
          <div className="metric-details">
            <span className={`metric-value ${stats.activeSOS > 0 ? 'neon-text-pink' : ''}`}>{stats.activeSOS}</span>
            <span className="metric-label">Critical SOS</span>
          </div>
        </div>

        <div className="metric-card glass-panel glitch-hover">
          <div className="metric-icon cyan"><ShieldCheck size={28} /></div>
          <div className="metric-details">
            <span className="metric-value">{stats.resolvedSOS}</span>
            <span className="metric-label">Resolved Events</span>
          </div>
        </div>
      </div>
      
      <div className="system-status glass-panel">
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
