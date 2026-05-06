import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  CheckCircle2,
  Clock,
  Crosshair,
  RefreshCw,
  ShieldCheck,
  UsersRound,
} from 'lucide-react';
import {
  POLL_INTERVAL_MS,
  acknowledgeSos,
  fetchSosDelivery,
  fetchSosEvents,
  getErrorMessage,
  respondToSos,
  type SosDeliveryAudit,
  type SOSEvent,
} from '../api';
import './SOS.css';

const PAGE_SIZE = 50;

const eventAge = (timestamp: string) => {
  const minutes = Math.max(0, Math.floor((Date.now() - new Date(timestamp).getTime()) / 60000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m active`;
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m active`;
};

const SOS = () => {
  const [events, setEvents] = useState<SOSEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [offset, setOffset] = useState(0);
  const [hasMore, setHasMore] = useState(true);
  const [error, setError] = useState('');
  const [deliveryAudit, setDeliveryAudit] = useState<Record<number, SosDeliveryAudit>>({});

  const refreshEvents = useCallback(async (newOffset = 0) => {
    setRefreshing(true);
    setError('');
    try {
      const nextEvents = await fetchSosEvents(PAGE_SIZE, newOffset);
      setEvents((current) => (newOffset === 0 ? nextEvents : [...current, ...nextEvents]));
      setHasMore(nextEvents.length === PAGE_SIZE);
      setOffset(newOffset);
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void Promise.resolve().then(() => refreshEvents(0));
    const interval = window.setInterval(() => refreshEvents(0), POLL_INTERVAL_MS);
    const manualRefresh = () => refreshEvents(0);
    window.addEventListener('saferoute:manual-refresh', manualRefresh);
    return () => {
      window.clearInterval(interval);
      window.removeEventListener('saferoute:manual-refresh', manualRefresh);
    };
  }, [refreshEvents]);

  const handleRespond = async (id: number) => {
    const confirmed = window.confirm('Mark response initiated for this SOS event?');
    if (!confirmed) return;

    try {
      await respondToSos(id);
      setEvents((current) =>
        current.map((event) =>
          event.id === id
            ? { ...event, status: 'RESOLVED', incident_status: 'RESOLVED', dispatch_status: 'resolved' }
            : event,
        ),
      );
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    }
  };

  const handleAcknowledge = async (id: number) => {
    try {
      await acknowledgeSos(id);
      setEvents((current) =>
        current.map((event) =>
          event.id === id
            ? { ...event, status: 'ACKNOWLEDGED', incident_status: 'ACKNOWLEDGED' }
            : event,
        ),
      );
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    }
  };

  const handleToggleAudit = async (id: number) => {
    if (deliveryAudit[id]) {
      setDeliveryAudit((current) => {
        const next = { ...current };
        delete next[id];
        return next;
      });
      return;
    }
    try {
      const audit = await fetchSosDelivery(id);
      setDeliveryAudit((current) => ({ ...current, [id]: audit }));
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    }
  };

  const isActiveIncident = (event: SOSEvent) =>
    !['RESOLVED', 'EXPIRED_NO_DELIVERY', 'EXPIRED_NO_RESPONSE'].includes(
      (event.incident_status || event.status || 'ACTIVE').toUpperCase(),
    );

  const activeEvents = useMemo(
    () =>
      events
        .filter(isActiveIncident)
        .sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()),
    [events],
  );
  const resolvedEvents = useMemo(
    () =>
      events
        .filter((event) => !isActiveIncident(event))
        .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()),
    [events],
  );

  return (
    <div className="sos-container">
      <section className="page-title-row">
        <div>
          <p className="eyebrow">Emergency Response</p>
          <h1>SOS Triage Board</h1>
          <p className="page-subtitle">
            Active incidents are sorted oldest first so unresolved alerts cannot drift.
          </p>
        </div>
        <button className="btn-primary" onClick={() => refreshEvents(0)} disabled={refreshing}>
          <RefreshCw size={16} className={refreshing ? 'spinning' : ''} />
          Refresh
        </button>
      </section>

      {error && <div className="alert-banner">{error}</div>}

      {loading && events.length === 0 ? (
        <div className="page-state">Loading SOS events...</div>
      ) : (
        <div className="triage-layout">
          <section className="triage-section">
            <div className="section-heading danger">
              <AlertTriangle size={20} />
              <h2>Active incidents</h2>
              <span>{activeEvents.length}</span>
            </div>

            {activeEvents.length === 0 ? (
              <div className="empty-state">No active distress signals.</div>
            ) : (
              <div className="incident-stack">
                {activeEvents.map((event) => (
                  <article className="sos-card active" key={event.id}>
                    <div className="sos-card-main">
                      <div className="incident-badge">SOS-{event.id}</div>
                      <div>
                        <h3>{event.tourist_id}</h3>
                        <p>{event.tuid || 'No TUID'} - {eventAge(event.timestamp)}</p>
                      </div>
                    </div>
                    <div className="incident-meta-grid">
                      <span><Crosshair size={14} /> {event.latitude.toFixed(5)}, {event.longitude.toFixed(5)}</span>
                      <span><Clock size={14} /> {new Date(event.timestamp).toLocaleString()}</span>
                      <span className={event.group_id ? 'group-context active' : 'group-context'}>
                        <UsersRound size={14} /> Group: {event.group_id || 'solo'}
                      </span>
                      <span>Trigger: {event.trigger_type}</span>
                      <span>Incident: {event.incident_status || event.status}</span>
                      <span>Delivery: {event.delivery_state || 'PENDING'}</span>
                      <span>Attempts: {event.attempt_count ?? 0}</span>
                      <span>Last channel: {event.last_successful_channel || 'none yet'}</span>
                    </div>
                    <div className="incident-actions">
                      {event.incident_status !== 'ACKNOWLEDGED' && (
                        <button className="btn-secondary" onClick={() => handleAcknowledge(event.id)}>
                          Acknowledge
                        </button>
                      )}
                      <button className="btn-secondary" onClick={() => handleToggleAudit(event.id)}>
                        {deliveryAudit[event.id] ? 'Hide audit' : 'Audit'}
                      </button>
                      <button className="btn-danger" onClick={() => handleRespond(event.id)}>
                        Resolve
                      </button>
                    </div>
                    {deliveryAudit[event.id] && (
                      <div className="audit-drawer">
                        <strong>{deliveryAudit[event.id].event.message}</strong>
                        {deliveryAudit[event.id].audit.length === 0 ? (
                          <span>No delivery attempts recorded yet.</span>
                        ) : (
                          deliveryAudit[event.id].audit.slice(0, 8).map((row) => (
                            <span key={row.audit_id}>
                              {row.channel} - {row.status}
                              {row.provider_status ? ` (${row.provider_status})` : ''}
                            </span>
                          ))
                        )}
                      </div>
                    )}
                  </article>
                ))}
              </div>
            )}
          </section>

          <section className="triage-section">
            <div className="section-heading">
              <ShieldCheck size={20} />
              <h2>Resolved log</h2>
              <span>{resolvedEvents.length}</span>
            </div>

            {resolvedEvents.length === 0 ? (
              <div className="empty-state">No resolved SOS records in this page.</div>
            ) : (
              <div className="resolved-table">
                {resolvedEvents.map((event) => (
                  <div className="resolved-row" key={event.id}>
                    <CheckCircle2 size={16} />
                    <div>
                      <strong>{event.tourist_id}</strong>
                      <span>{event.trigger_type} - {new Date(event.timestamp).toLocaleString()}</span>
                      {event.group_id && <span>Group: {event.group_id}</span>}
                    </div>
                    <span>{event.incident_status || event.status}</span>
                  </div>
                ))}
              </div>
            )}

            {hasMore && (
              <button className="btn-secondary load-more" onClick={() => refreshEvents(offset + PAGE_SIZE)}>
                Load more
              </button>
            )}
          </section>
        </div>
      )}
    </div>
  );
};

export default SOS;
