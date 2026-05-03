// dashboard/src/pages/SOS.tsx
import { useEffect, useState } from 'react';
import { AlertTriangle, Clock, Crosshair, CheckCircle } from 'lucide-react';
import api from '../api';
import './SOS.css';

interface SOSEvent {
  id: number;
  tourist_id: string;
  latitude: number;
  longitude: number;
  trigger_type: string;
  status: string;
  timestamp: string;
}

const SOS = () => {
  const [events, setEvents] = useState<SOSEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [offset, setOffset] = useState(0);
  const [hasMore, setHasMore] = useState(true);
  const PAGE_SIZE = 50;

  const fetchEvents = async (newOffset = 0) => {
    try {
      const res = await api.get(`/sos/events?limit=${PAGE_SIZE}&offset=${newOffset}`);
      if (newOffset === 0) {
        setEvents(res.data);
      } else {
        setEvents(prev => [...prev, ...res.data]);
      }
      setHasMore(res.data.length === PAGE_SIZE);
      setOffset(newOffset);
    } catch (err) {
      console.error('Failed to fetch SOS events', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchEvents(0);
    const interval = setInterval(() => fetchEvents(0), 10000); // Poll first page only for new alerts
    return () => clearInterval(interval);
  }, []);

  const loadMore = () => {
    fetchEvents(offset + PAGE_SIZE);
  };

  const handleRespond = async (id: number) => {
    try {
      await api.post(`/sos/events/${id}/respond`);
      // Optimistically update
      setEvents(events.map(e => e.id === id ? { ...e, status: 'RESOLVED' } : e));
    } catch (err) {
      alert('Failed to respond to SOS');
    }
  };

  const activeEvents = events.filter(e => e.status === 'ACTIVE');
  const resolvedEvents = events.filter(e => e.status === 'RESOLVED');

  return (
    <div className="sos-container">
      <header className="page-header">
        <h1 className="neon-text-pink">Emergency Monitoring</h1>
        <p className="subtitle">Real-time distress signal tracking</p>
      </header>

      {loading && events.length === 0 ? (
        <div className="loading-state">ESTABLISHING CONNECTION...</div>
      ) : (
        <div className="sos-content">
          <section className="sos-section">
            <h2 className="section-title neon-text-pink">
              <AlertTriangle size={20} /> ACTIVE DISTRESS SIGNALS ({activeEvents.length})
            </h2>

            {activeEvents.length === 0 ? (
              <div className="empty-state glass-panel">ALL FREQUENCIES CLEAR</div>
            ) : (
              <div className="events-list">
                {activeEvents.map(e => (
                  <div key={e.id} className="event-card active glass-panel">
                    <div className="event-main">
                      <div className="event-icon pulse-alert"><AlertTriangle size={24} /></div>
                      <div className="event-info">
                        <h3>TOURIST: {e.tourist_id}</h3>
                        <div className="event-meta">
                          <span><Crosshair size={14} /> {e.latitude.toFixed(5)}, {e.longitude.toFixed(5)}</span>
                          <span><Clock size={14} /> {new Date(e.timestamp).toLocaleTimeString()}</span>
                          <span className="trigger-type">TRIGGER: {e.trigger_type}</span>
                        </div>
                      </div>
                    </div>
                    <button className="btn-danger respond-btn" onClick={() => handleRespond(e.id)}>
                      INITIATE RESPONSE
                    </button>
                  </div>
                ))}
              </div>
            )}
          </section>

          <section className="sos-section mt-5">
            <h2 className="section-title neon-text-cyan">
              <CheckCircle size={20} /> RESOLVED LOGS ({resolvedEvents.length})
            </h2>

            <div className="events-list resolved-list">
              {resolvedEvents.map(e => (
                <div key={e.id} className="event-card resolved glass-panel">
                  <div className="event-main">
                    <div className="event-info">
                      <h3>TOURIST: {e.tourist_id} <span className="resolved-badge">RESOLVED</span></h3>
                      <div className="event-meta">
                        <span>{e.latitude.toFixed(5)}, {e.longitude.toFixed(5)}</span>
                        <span>{new Date(e.timestamp).toLocaleString()}</span>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
            {hasMore && (
              <div className="load-more-container mt-4 text-center">
                <button className="btn-secondary" onClick={loadMore}>LOAD MORE RESOLVED</button>
              </div>
            )}
          </section>
        </div>
      )}
    </div>
  );
};

export default SOS;
