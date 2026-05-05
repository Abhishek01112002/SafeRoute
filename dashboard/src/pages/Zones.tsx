import { useCallback, useEffect, useMemo, useState } from 'react';
import type { FormEvent } from 'react';
import * as QRCode from 'qrcode';
import { Database, MapPin, Navigation, Plus, QrCode, RadioTower, RefreshCw, Trash2, X } from 'lucide-react';
import api, { getErrorMessage, type Destination, type Zone } from '../api';
import ZoneMap from '../components/ZoneMap';
import './Zones.css';

const defaultZone = {
  name: '',
  type: 'SAFE',
  shape: 'POLYGON',
  center_lat: 0,
  center_lng: 0,
  radius_m: 500,
};

interface Authority {
  state?: string;
  jurisdiction_zone?: string;
}

const normalize = (value?: string | null) => (value || '').trim().toLowerCase();

const Zones = () => {
  const [zones, setZones] = useState<Zone[]>([]);
  const [destinations, setDestinations] = useState<Destination[]>([]);
  const [selectedDest, setSelectedDest] = useState('');
  const [loading, setLoading] = useState(false);
  const [destinationsLoading, setDestinationsLoading] = useState(false);
  const [showAddForm, setShowAddForm] = useState(false);
  const [newZone, setNewZone] = useState(defaultZone);
  const [mapPoints, setMapPoints] = useState<{ lat: number; lng: number }[]>([]);
  const [qrBundle, setQrBundle] = useState<{ token: string; zone_count: number } | null>(null);
  const [qrImage, setQrImage] = useState('');
  const [qrLoading, setQrLoading] = useState(false);
  const [error, setError] = useState('');

  const authority: Authority = useMemo(() => {
    try {
      const authData = localStorage.getItem('authority');
      return authData ? JSON.parse(authData) : {};
    } catch {
      return {};
    }
  }, []);

  const fetchDestinations = useCallback(async () => {
    setError('');
    setDestinationsLoading(true);
    try {
      const response = await api.get<Destination[]>('/destinations');
      const allDestinations = (response.data || []).filter(
        (destination) => destination.id && destination.name,
      );
      const jurisdiction = normalize(authority.state || authority.jurisdiction_zone);
      const jurisdictionDestinations = jurisdiction
        ? allDestinations.filter(
            (destination) =>
              normalize(destination.state) === jurisdiction ||
              normalize(destination.name).includes(jurisdiction) ||
              normalize(destination.id).includes(jurisdiction),
          )
        : allDestinations;
      const nextDestinations = jurisdictionDestinations.length
        ? jurisdictionDestinations
        : allDestinations;

      setDestinations(nextDestinations);
      if (nextDestinations.length > 0) {
        setSelectedDest((current) =>
          nextDestinations.some((destination) => destination.id === current)
            ? current
            : nextDestinations[0].id,
        );
      } else {
        setSelectedDest('');
        setZones([]);
        setError('No destination catalogue is available from the backend yet.');
      }
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    } finally {
      setDestinationsLoading(false);
    }
  }, [authority.state, authority.jurisdiction_zone]);

  const fetchZones = useCallback(async (destinationId = selectedDest) => {
    if (!destinationId) {
      setZones([]);
      return;
    }
    setLoading(true);
    setError('');
    try {
      const response = await api.get<Zone[]>('/zones', {
        params: { destination_id: destinationId },
      });
      setZones(response.data);
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    } finally {
      setLoading(false);
    }
  }, [selectedDest]);

  useEffect(() => {
    void Promise.resolve().then(fetchDestinations);
    const manualRefresh = () => {
      fetchDestinations();
      fetchZones();
    };
    window.addEventListener('saferoute:manual-refresh', manualRefresh);
    return () => window.removeEventListener('saferoute:manual-refresh', manualRefresh);
  }, [fetchDestinations, fetchZones]);

  useEffect(() => {
    void Promise.resolve().then(() => {
      fetchZones(selectedDest);
      setQrBundle(null);
      setQrImage('');
    });
  }, [selectedDest, fetchZones]);

  useEffect(() => {
    if (!qrBundle) return;
    QRCode.toDataURL(qrBundle.token, {
      width: 220,
      margin: 2,
      color: { dark: '#0f172a', light: '#ffffff' },
    })
      .then(setQrImage)
      .catch((qrError) => setError(getErrorMessage(qrError)));
  }, [qrBundle]);

  const currentDest = destinations.find((destination) => destination.id === selectedDest);
  const mapCenter: [number, number] = currentDest
    ? [currentDest.center_lat, currentDest.center_lng]
    : [30.7352, 79.0669];
  const zoneStats = useMemo(
    () =>
      zones.reduce(
        (acc, zone) => {
          const type = (zone.type || 'UNKNOWN').toUpperCase();
          acc[type] = (acc[type] || 0) + 1;
          return acc;
        },
        {} as Record<string, number>,
      ),
    [zones],
  );

  const validateZoneDraft = () => {
    if (!selectedDest) return 'Select a destination before deploying a zone.';
    if (!newZone.name.trim()) return 'Zone name is required.';
    if (newZone.shape === 'POLYGON' && mapPoints.length < 3) {
      return 'Polygon zones require at least 3 map points.';
    }
    if (newZone.shape === 'CIRCLE' && mapPoints.length === 0) {
      return 'Click the map to set the circle center.';
    }
    if (newZone.shape === 'CIRCLE' && Number(newZone.radius_m) <= 0) {
      return 'Circle radius must be greater than 0 metres.';
    }
    return '';
  };

  const handleDelete = async (zoneId: string) => {
    if (!window.confirm('Deactivate this zone?')) return;
    setError('');
    try {
      await api.delete(`/zones/${zoneId}`);
      setZones((current) => current.filter((zone) => zone.id !== zoneId));
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    }
  };

  const handleAddZone = async (event: FormEvent) => {
    event.preventDefault();
    const validationError = validateZoneDraft();
    if (validationError) {
      setError(validationError);
      return;
    }

    setError('');
    try {
      const payload = {
        ...newZone,
        name: newZone.name.trim(),
        destination_id: selectedDest,
        center_lat: mapPoints[0].lat,
        center_lng: mapPoints[0].lng,
        radius_m: newZone.shape === 'CIRCLE' ? Number(newZone.radius_m) : null,
        polygon_points: mapPoints,
        is_active: 1,
      };

      const response = await api.post<Zone>('/zones', payload);
      setZones((current) => [...current, response.data]);
      setShowAddForm(false);
      setMapPoints([]);
      setNewZone(defaultZone);
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    }
  };

  const handleGenerateQR = async () => {
    if (!selectedDest) return;
    setQrLoading(true);
    setError('');
    try {
      const response = await api.get<{ qr_token: string; zone_count: number }>(
        `/onboard/preview/${selectedDest}`,
      );
      setQrBundle({ token: response.data.qr_token, zone_count: response.data.zone_count });
    } catch (requestError) {
      setError(getErrorMessage(requestError));
    } finally {
      setQrLoading(false);
    }
  };

  return (
    <div className="zones-container">
      <section className="page-title-row">
        <div>
          <p className="eyebrow">Jurisdiction Tools</p>
          <h1>Zone Operations</h1>
          <p className="page-subtitle">Deploy, review, and package safety zones for offline mobile use.</p>
        </div>
        <div className="page-actions">
          <button className="btn-secondary" onClick={() => fetchZones()} disabled={!selectedDest || loading}>
            <RefreshCw size={16} className={loading ? 'spinning' : ''} />
            Refresh
          </button>
          <button className="btn-secondary" onClick={handleGenerateQR} disabled={qrLoading || !selectedDest}>
            <QrCode size={16} />
            {qrLoading ? 'Generating' : 'Generate QR'}
          </button>
          <button className="btn-primary" onClick={() => setShowAddForm((current) => !current)}>
            <Plus size={16} />
            New zone
          </button>
        </div>
      </section>

      {error && <div className="alert-banner">{error}</div>}

      <section className="selector-panel">
        <div className="selector-command">
          <div className="selector-icon">
            <Navigation size={20} />
          </div>
          <div className="selector-copy">
            <label htmlFor="destination">Target destination</label>
            <span>
              {destinationsLoading
                ? 'Loading catalogue...'
                : `${destinations.length} destination target(s) available`}
            </span>
          </div>
        </div>
        <div className="selector-field">
          <select
            id="destination"
            value={selectedDest}
            disabled={destinationsLoading || destinations.length === 0}
            onChange={(event) => setSelectedDest(event.target.value)}
          >
            {destinations.length === 0 && <option value="">No destinations loaded</option>}
            {destinations.map((destination) => (
              <option key={destination.id} value={destination.id}>
                {destination.name} ({destination.id})
              </option>
            ))}
          </select>
          <button className="btn-secondary" type="button" onClick={fetchDestinations} disabled={destinationsLoading}>
            <RefreshCw size={16} className={destinationsLoading ? 'spinning' : ''} />
            Reload
          </button>
        </div>
        <div className="destination-brief">
          <div>
            <Database size={15} />
            <span>{currentDest?.state || 'State pending'}</span>
          </div>
          <div>
            <MapPin size={15} />
            <span>
              {currentDest
                ? `${currentDest.center_lat.toFixed(4)}, ${currentDest.center_lng.toFixed(4)}`
                : 'No target selected'}
            </span>
          </div>
          <div>
            <RadioTower size={15} />
            <span>{zones.length} active zone(s)</span>
          </div>
        </div>
        <div className="zone-summary-strip">
          <span className="summary-safe">SAFE {zoneStats.SAFE || 0}</span>
          <span className="summary-caution">CAUTION {zoneStats.CAUTION || 0}</span>
          <span className="summary-restricted">RESTRICTED {zoneStats.RESTRICTED || 0}</span>
        </div>
      </section>

      {qrBundle && (
        <section className="qr-panel">
          <div className="qr-panel-header">
            <div>
              <h2>Offline onboarding QR</h2>
              <p>{qrBundle.zone_count} active zone(s) bundled for the selected destination.</p>
            </div>
            <button className="icon-button" onClick={() => setQrBundle(null)} title="Close QR panel">
              <X size={18} />
            </button>
          </div>
          <div className="qr-panel-body">
            {qrImage ? <img src={qrImage} alt="Zone onboarding QR code" className="qr-image" /> : <div className="qr-placeholder">Generating QR...</div>}
            <div className="qr-token-box">
              <span>Raw token for field testing</span>
              <code>{qrBundle.token}</code>
            </div>
          </div>
        </section>
      )}

      <section className="map-section">
        <div className="map-guidance">
          <strong>{showAddForm ? 'Drawing mode active' : 'Review mode'}</strong>
          <span>
            {showAddForm
              ? 'Click the map to place polygon points or a circle centre. Use Undo/Clear before deploying.'
              : 'Existing active zones are shown by risk color.'}
          </span>
        </div>
        <ZoneMap
          center={mapCenter}
          existingZones={zones}
          drawingMode={showAddForm}
          onPointsChange={setMapPoints}
          zoneType={newZone.type}
          currentShape={newZone.shape}
          radiusM={Number(newZone.radius_m)}
        />
      </section>

      {showAddForm && (
        <form className="add-zone-form" onSubmit={handleAddZone}>
          <h2>Define new zone</h2>
          <div className="form-grid">
            <div className="form-group">
              <label>Name</label>
              <input
                required
                value={newZone.name}
                onChange={(event) => setNewZone({ ...newZone, name: event.target.value })}
                placeholder="e.g. Northern Ridge"
              />
            </div>
            <div className="form-group">
              <label>Type</label>
              <select
                value={newZone.type}
                onChange={(event) => setNewZone({ ...newZone, type: event.target.value })}
              >
                <option value="SAFE">SAFE</option>
                <option value="CAUTION">CAUTION</option>
                <option value="RESTRICTED">RESTRICTED</option>
              </select>
            </div>
            <div className="form-group">
              <label>Shape</label>
              <select
                value={newZone.shape}
                onChange={(event) => {
                  setNewZone({ ...newZone, shape: event.target.value });
                  setMapPoints([]);
                }}
              >
                <option value="POLYGON">POLYGON</option>
                <option value="CIRCLE">CIRCLE</option>
              </select>
            </div>
            {newZone.shape === 'CIRCLE' && (
              <div className="form-group">
                <label>Radius (m)</label>
                <input
                  required
                  type="number"
                  min="1"
                  value={newZone.radius_m}
                  onChange={(event) =>
                    setNewZone({ ...newZone, radius_m: Number.parseInt(event.target.value, 10) || 0 })
                  }
                />
              </div>
            )}
          </div>
          <div className="form-actions">
            <button type="button" className="btn-secondary" onClick={() => { setShowAddForm(false); setMapPoints([]); }}>
              Cancel
            </button>
            <button type="submit" className="btn-primary">
              Deploy zone
            </button>
          </div>
        </form>
      )}

      {loading ? (
        <div className="page-state">Loading zones...</div>
      ) : (
        <section className="zones-grid">
          {zones.map((zone) => (
            <article key={zone.id} className={`zone-card type-${(zone.type || 'safe').toLowerCase()}`}>
              <div className="zone-header">
                <div>
                  <h2>{zone.name || 'Unnamed zone'}</h2>
                  <span>{zone.destination_id}</span>
                </div>
                <span className="zone-badge">{zone.type || 'SAFE'}</span>
              </div>
              <div className="zone-details">
                <p><MapPin size={14} /> {(zone.center_lat || 0).toFixed(4)}, {(zone.center_lng || 0).toFixed(4)}</p>
                <p>{zone.shape || 'POLYGON'}{zone.shape === 'CIRCLE' ? ` - ${zone.radius_m}m radius` : ''}</p>
              </div>
              <button className="icon-button delete" onClick={() => handleDelete(zone.id)} title="Deactivate zone">
                <Trash2 size={17} />
              </button>
            </article>
          ))}
          {zones.length === 0 && <div className="empty-state">No active zones for this destination.</div>}
        </section>
      )}
    </div>
  );
};

export default Zones;
