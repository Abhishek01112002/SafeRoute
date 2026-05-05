import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import {
  AlertTriangle,
  Clock,
  MapPin,
  RadioTower,
  RefreshCw,
  Route,
  ShieldCheck,
  Users,
} from 'lucide-react';
import {
  POLL_INTERVAL_MS,
  fetchDashboardAnalytics,
  fetchLocations,
  fetchSosEvents,
  getErrorMessage,
  type ActivityItem,
  type DashboardAnalytics,
  type LocationRecord,
  type SOSEvent,
} from '../api';
import './Dashboard.css';

const PAGE_SIZE = 50;

const formatDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString() : 'No data';

const minutesSince = (value?: string | null) => {
  if (!value) return 'No signal';
  const diff = Date.now() - new Date(value).getTime();
  const minutes = Math.max(0, Math.floor(diff / 60000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m ago`;
};

const statusClass = (status?: string | null) =>
  (status || 'UNKNOWN').toLowerCase().replace(/[^a-z0-9]+/g, '-');

const Dashboard = () => {
  const [analytics, setAnalytics] = useState<DashboardAnalytics | null>(null);
  const [locations, setLocations] = useState<LocationRecord[]>([]);
  const [incidents, setIncidents] = useState<SOSEvent[]>([]);
  const [locationOffset, setLocationOffset] = useState(0);
  const [hasMoreLocations, setHasMoreLocations] = useState(true);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [lastUpdated, setLastUpdated] = useState<string | null>(null);

  const refreshDashboard = useCallback(async () => {
    setRefreshing(true);
    setError('');
    try {
      const [nextAnalytics, nextLocations, nextIncidents] = await Promise.all([
        fetchDashboardAnalytics(),
        fetchLocations(PAGE_SIZE, 0),
        fetchSosEvents(20, 0),
      ]);
      setAnalytics(nextAnalytics);
      setLocations(nextLocations);
      setIncidents(nextIncidents);
      setLocationOffset(0);
      setHasMoreLocations(nextLocations.length === PAGE_SIZE);
      setLastUpdated(new Date().toISOString());
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void Promise.resolve().then(refreshDashboard);
    const interval = window.setInterval(refreshDashboard, POLL_INTERVAL_MS);
    const manualRefresh = () => refreshDashboard();
    window.addEventListener('saferoute:manual-refresh', manualRefresh);
    return () => {
      window.clearInterval(interval);
      window.removeEventListener('saferoute:manual-refresh', manualRefresh);
    };
  }, [refreshDashboard]);

  const loadMoreLocations = async () => {
    const nextOffset = locationOffset + PAGE_SIZE;
    try {
      const next = await fetchLocations(PAGE_SIZE, nextOffset);
      setLocations((current) => [...current, ...next]);
      setLocationOffset(nextOffset);
      setHasMoreLocations(next.length === PAGE_SIZE);
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    }
  };

  const activeIncidents = useMemo(
    () =>
      incidents
        .filter((event) => event.status === 'ACTIVE')
        .sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()),
    [incidents],
  );

  const metrics = analytics?.metrics;
  const zoneBreakdown = analytics?.zone_breakdown ?? {
    SAFE: 0,
    CAUTION: 0,
    RESTRICTED: 0,
    UNKNOWN: 0,
  };
  const totalZones = Object.values(zoneBreakdown).reduce((sum, count) => sum + count, 0);

  if (loading && !analytics) {
    return <div className="page-state">Loading command dashboard...</div>;
  }

  return (
    <div className="dashboard-container">
      <section className="page-title-row">
        <div>
          <p className="eyebrow">Authority Dashboard</p>
          <h1>Command Overview</h1>
          <p className="page-subtitle">
            Operational view of tourists, locations, zones, trips, and SOS events.
          </p>
        </div>
        <button className="btn-primary" onClick={refreshDashboard} disabled={refreshing}>
          <RefreshCw size={16} className={refreshing ? 'spinning' : ''} />
          Refresh data
        </button>
      </section>

      {error && <div className="alert-banner">{error}</div>}

      <section className="kpi-grid">
        <KpiCard icon={<Users />} label="Registered tourists" value={metrics?.registered_tourists ?? 0} />
        <KpiCard icon={<AlertTriangle />} label="Active SOS" value={metrics?.active_sos ?? 0} tone="danger" />
        <KpiCard icon={<RadioTower />} label="Active zones" value={metrics?.active_zones ?? 0} />
        <KpiCard icon={<Route />} label="Active trips" value={metrics?.active_trips ?? 0} />
        <KpiCard icon={<ShieldCheck />} label="Resolved SOS" value={metrics?.resolved_sos ?? 0} tone="success" />
      </section>

      <section className="dashboard-grid">
        <Panel title="Active incident queue" action={`${activeIncidents.length} active`}>
          {activeIncidents.length === 0 ? (
            <EmptyState message="No active SOS events." />
          ) : (
            <div className="incident-list">
              {activeIncidents.map((event) => (
                <div className="incident-row" key={event.id}>
                  <div>
                    <strong>{event.tourist_id}</strong>
                    <span>{event.trigger_type} - {minutesSince(event.timestamp)}</span>
                  </div>
                  <div className="incident-location">
                    <MapPin size={14} />
                    {event.latitude.toFixed(5)}, {event.longitude.toFixed(5)}
                  </div>
                </div>
              ))}
            </div>
          )}
        </Panel>

        <Panel title="Location freshness" action={`Updated ${minutesSince(lastUpdated)}`}>
          <div className="freshness-stack">
            <div>
              <span className="field-label">Latest location ping</span>
              <strong>{formatDateTime(analytics?.freshness.last_location_ping_at)}</strong>
            </div>
            <div>
              <span className="field-label">Stale tourists</span>
              <strong>{analytics?.freshness.stale_tourist_count ?? 0}</strong>
              <small>Threshold {analytics?.freshness.stale_threshold_minutes ?? 15} minutes</small>
            </div>
            <div>
              <span className="field-label">Latest SOS</span>
              <strong>{formatDateTime(analytics?.freshness.latest_sos_at)}</strong>
            </div>
          </div>
        </Panel>

        <Panel title="Zone risk distribution" action={`${totalZones} zones`}>
          <div className="distribution-list">
            {Object.entries(zoneBreakdown).map(([status, count]) => (
              <DistributionBar key={status} label={status} value={count} total={Math.max(totalZones, 1)} />
            ))}
          </div>
        </Panel>

        <Panel title="Trip workload" action="Lifecycle">
          <div className="trip-grid">
            <TripMetric label="Active" value={metrics?.active_trips ?? 0} />
            <TripMetric label="Planned" value={metrics?.planned_trips ?? 0} />
            <TripMetric label="Completed" value={metrics?.completed_trips ?? 0} />
            <TripMetric label="Cancelled" value={metrics?.cancelled_trips ?? 0} />
          </div>
        </Panel>
      </section>

      <section className="wide-grid">
        <Panel title="Last known positions" action={`${locations.length} loaded`}>
          {locations.length === 0 ? (
            <EmptyState message="No location pings received yet." />
          ) : (
            <>
              <div className="data-table location-table">
                <div className="table-header">
                  <span>Tourist</span>
                  <span>Coordinates</span>
                  <span>Zone</span>
                  <span>Freshness</span>
                </div>
                {locations.map((location) => (
                  <div className="table-row" key={`${location.tourist_id}-${location.timestamp}`}>
                    <span>
                      <strong>{location.tourist_id}</strong>
                      <small>{location.tuid || 'No TUID'}</small>
                    </span>
                    <span>{location.latitude.toFixed(5)}, {location.longitude.toFixed(5)}</span>
                    <span className={`status-chip ${statusClass(location.zone_status)}`}>
                      {location.zone_status || 'UNKNOWN'}
                    </span>
                    <span>{minutesSince(location.timestamp)}</span>
                  </div>
                ))}
              </div>
              {hasMoreLocations && (
                <button className="btn-secondary load-more" onClick={loadMoreLocations}>
                  Load more locations
                </button>
              )}
            </>
          )}
        </Panel>

        <Panel title="Recent activity" action="Latest 20">
          {analytics?.recent_activity.length ? (
            <div className="activity-list">
              {analytics.recent_activity.map((item) => (
                <ActivityRow item={item} key={`${item.type}-${item.id}-${item.timestamp}`} />
              ))}
            </div>
          ) : (
            <EmptyState message="No activity recorded yet." />
          )}
        </Panel>
      </section>
    </div>
  );
};

const KpiCard = ({
  icon,
  label,
  value,
  tone = 'default',
}: {
  icon: ReactNode;
  label: string;
  value: number;
  tone?: 'default' | 'danger' | 'success';
}) => (
  <div className={`kpi-card ${tone}`}>
    <div className="kpi-icon">{icon}</div>
    <div>
      <span>{label}</span>
      <strong>{value.toLocaleString()}</strong>
    </div>
  </div>
);

const Panel = ({
  title,
  action,
  children,
}: {
  title: string;
  action?: string;
  children: ReactNode;
}) => (
  <section className="ops-panel">
    <div className="panel-header">
      <h2>{title}</h2>
      {action && <span>{action}</span>}
    </div>
    {children}
  </section>
);

const EmptyState = ({ message }: { message: string }) => (
  <div className="empty-state">{message}</div>
);

const DistributionBar = ({ label, value, total }: { label: string; value: number; total: number }) => (
  <div className="distribution-row">
    <div>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
    <div className="bar-track">
      <div className={`bar-fill ${statusClass(label)}`} style={{ width: `${(value / total) * 100}%` }} />
    </div>
  </div>
);

const TripMetric = ({ label, value }: { label: string; value: number }) => (
  <div className="trip-metric">
    <span>{label}</span>
    <strong>{value}</strong>
  </div>
);

const ActivityRow = ({ item }: { item: ActivityItem }) => (
  <div className="activity-row">
    <Clock size={15} />
    <div>
      <strong>{item.label}</strong>
      <span>
        {item.tourist_id || item.id} - {item.status} - {minutesSince(item.timestamp)}
      </span>
    </div>
  </div>
);

export default Dashboard;
