// dashboard/src/pages/Zones.tsx
import { useEffect, useState } from 'react';
import { Trash2, Plus, MapPin, QrCode, X } from 'lucide-react';
import api from '../api';
import './Zones.css';
import ZoneMap from '../components/ZoneMap';

interface Zone {
  id: string;
  destination_id: string;
  name: string;
  type: string;
  shape: string;
  center_lat: number;
  center_lng: number;
  radius_m: number | null;
  polygon_points: {lat: number, lng: number}[];
}

interface Destination {
  id: string;
  name: string;
  center_lat: number;
  center_lng: number;
}

interface Authority {
  state?: string;
  authority_id?: string;
  full_name?: string;
}

const Zones = () => {
  const [zones, setZones] = useState<Zone[]>([]);
  const [destinations, setDestinations] = useState<Destination[]>([]);
  const [selectedDest, setSelectedDest] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [showAddForm, setShowAddForm] = useState(false);

  // Form State
  const [newZone, setNewZone] = useState({
    name: '',
    type: 'SAFE',
    shape: 'POLYGON',
    center_lat: 0,
    center_lng: 0,
    radius_m: 500
  });

  const [mapPoints, setMapPoints] = useState<{lat: number, lng: number}[]>([]);
  const [qrBundle, setQrBundle] = useState<{token: string; zone_count: number} | null>(null);
  const [qrLoading, setQrLoading] = useState(false);

  let authority: Authority = {};
  try {
    const authData = localStorage.getItem('authority');
    if (authData) {
      authority = JSON.parse(authData);
    }
  } catch {
    // Silent fail for storage access
  }

  useEffect(() => {
    const fetchDestinations = async () => {
      try {
        const res = await api.get(`/destinations/${authority.state || 'Uttarakhand'}`);
        setDestinations(res.data);
        if (res.data.length > 0) {
          setSelectedDest(res.data[0].id);
        }
      } catch {
        console.error('Failed to fetch destinations');
      }
    };
    fetchDestinations();
  }, [authority.state]);

  useEffect(() => {
    if (!selectedDest) return;
    const fetchZones = async () => {
      setLoading(true);
      try {
        const res = await api.get(`/zones?destination_id=${selectedDest}`);
        setZones(res.data);
      } catch {
        console.error('Failed to fetch zones');
      } finally {
        setLoading(false);
      }
    };
    fetchZones();
  }, [selectedDest]);

  const handleDelete = async (zoneId: string) => {
    if (!window.confirm('Are you sure you want to delete this zone?')) return;
    try {
      await api.delete(`/zones/${zoneId}`);
      setZones(zones.filter(z => z.id !== zoneId));
    } catch {
      alert('Failed to delete zone');
    }
  };

  const handleAddZone = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newZone.shape === 'POLYGON' && mapPoints.length < 3) {
      alert('Polygon requires at least 3 points.');
      return;
    }
    if (newZone.shape === 'CIRCLE' && mapPoints.length === 0) {
      alert('Please click on the map to set the circle center.');
      return;
    }

    try {
      const payload = {
        ...newZone,
        destination_id: selectedDest,
        center_lat: mapPoints[0].lat,
        center_lng: mapPoints[0].lng,
        radius_m: newZone.shape === 'CIRCLE' ? Number(newZone.radius_m) : null,
        polygon_points: mapPoints,
        is_active: 1
      };

      const res = await api.post('/zones', payload);
      setZones([...zones, res.data]);
      setShowAddForm(false);
      setMapPoints([]);
      setNewZone({ name: '', type: 'SAFE', shape: 'POLYGON', center_lat: 0, center_lng: 0, radius_m: 500 });
    } catch {
      alert('Failed to add zone');
    }
  };

  const currentDest = destinations.find(d => d.id === selectedDest);
  const mapCenter: [number, number] = currentDest ? [currentDest.center_lat, currentDest.center_lng] : [30.7352, 79.0669];

  const handleGenerateQR = async () => {
    if (!selectedDest) return;
    setQrLoading(true);
    try {
      const res = await api.get(`/onboard/preview/${selectedDest}`);
      setQrBundle({ token: res.data.qr_token, zone_count: res.data.zone_count });
    } catch {
      alert('Failed to generate QR token');
    } finally {
      setQrLoading(false);
    }
  };

  return (
    <div className="zones-container">
      <header className="page-header">
        <div className="header-flex">
          <div>
            <h1 className="neon-text-cyan">Zone Manager</h1>
            <p className="subtitle">Configure jurisdiction boundaries</p>
          </div>
          <div style={{ display: 'flex', gap: '0.75rem' }}>
            <button className="btn-secondary" onClick={handleGenerateQR} disabled={qrLoading || !selectedDest}>
              <QrCode size={18} /> {qrLoading ? 'GENERATING...' : 'GENERATE QR'}
            </button>
            <button className="btn-primary" onClick={() => setShowAddForm(!showAddForm)}>
              <Plus size={18} /> NEW ZONE
            </button>
          </div>
        </div>
      </header>

      <div className="dest-selector glass-panel">
        <label>TARGET DESTINATION:</label>
        <select value={selectedDest} onChange={(e) => { setSelectedDest(e.target.value); setQrBundle(null); }}>
          {destinations.map(d => (
            <option key={d.id} value={d.id}>{d.name} ({d.id})</option>
          ))}
        </select>
      </div>

      {qrBundle && (
        <div className="qr-panel glass-panel">
          <div className="qr-panel-header">
            <div>
              <h3 className="neon-text-cyan" style={{ marginBottom: '0.25rem' }}>ONBOARDING QR CODE</h3>
              <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                {qrBundle.zone_count} zone(s) bundled · Tourists scan this to download zone data offline
              </p>
            </div>
            <button className="delete-btn" onClick={() => setQrBundle(null)} title="Close"><X size={18} /></button>
          </div>
          <div className="qr-panel-body">
            <img
              src={`https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(qrBundle.token)}&bgcolor=0d0d1a&color=00ffcc&qzone=2`}
              alt="Zone QR Code"
              className="qr-image"
            />
            <div className="qr-token-box">
              <p style={{ fontSize: '0.7rem', color: 'var(--text-muted)', marginBottom: '0.5rem', letterSpacing: '1px' }}>RAW TOKEN (for testing)</p>
              <code style={{ fontSize: '0.65rem', wordBreak: 'break-all', color: 'var(--accent-cyan)', opacity: 0.8 }}>{qrBundle.token}</code>
            </div>
          </div>
        </div>
      )}

      <ZoneMap
        center={mapCenter}
        existingZones={zones}
        drawingMode={showAddForm}
        onPointsChange={setMapPoints}
        zoneType={newZone.type}
        currentShape={newZone.shape}
      />

      {showAddForm && (
        <form className="add-zone-form glass-panel" onSubmit={handleAddZone}>
          <h3 className="neon-text-pink mb-4">DEFINE NEW ZONE</h3>
          <div className="form-grid">
            <div className="form-group">
              <label>NAME</label>
              <input required value={newZone.name} onChange={e => setNewZone({...newZone, name: e.target.value})} placeholder="e.g. Northern Ridge" />
            </div>
            <div className="form-group">
              <label>TYPE</label>
              <select value={newZone.type} onChange={e => setNewZone({...newZone, type: e.target.value})}>
                <option value="SAFE">SAFE</option>
                <option value="CAUTION">CAUTION</option>
                <option value="RESTRICTED">RESTRICTED</option>
              </select>
            </div>
            <div className="form-group">
              <label>SHAPE</label>
              <select value={newZone.shape} onChange={e => setNewZone({...newZone, shape: e.target.value})}>
                <option value="POLYGON">POLYGON (MULTI-CLICK)</option>
                <option value="CIRCLE">CIRCLE (SINGLE-CLICK)</option>
              </select>
            </div>
            {newZone.shape === 'CIRCLE' && (
              <div className="form-group">
                <label>RADIUS (M)</label>
                <input required type="number" value={newZone.radius_m} onChange={e => setNewZone({...newZone, radius_m: parseInt(e.target.value)})} />
              </div>
            )}
          </div>
          <div className="form-actions mt-4">
            <button type="button" className="btn-danger" onClick={() => {setShowAddForm(false); setMapPoints([]);}}>CANCEL</button>
            <button type="submit" className="btn-primary">DEPLOY ZONE</button>
          </div>
        </form>
      )}

      {loading ? (
        <div className="loading-state">SCANNING JURISDICTION...</div>
      ) : (
        <div className="zones-grid">
          {zones.map(z => (
            <div key={z.id} className={`zone-card glass-panel type-${(z.type || 'safe').toLowerCase()}`}>
              <div className="zone-header">
                <h3>{z.name || 'Unnamed Zone'}</h3>
                <span className="zone-badge">{z.type || 'SAFE'}</span>
              </div>
              <div className="zone-details">
                <p><MapPin size={14} /> {(z.center_lat || 0).toFixed(4)}, {(z.center_lng || 0).toFixed(4)}</p>
                <p>SHAPE: {z.shape || 'POLYGON'}</p>
                {z.shape === 'CIRCLE' && <p>RADIUS: {z.radius_m}m</p>}
              </div>
              <button className="delete-btn" onClick={() => handleDelete(z.id)} title="Remove Zone">
                <Trash2 size={18} />
              </button>
            </div>
          ))}
          {zones.length === 0 && !loading && (
            <div className="empty-state">No active zones detected in this destination.</div>
          )}
        </div>
      )}
    </div>
  );
};

export default Zones;
