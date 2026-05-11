import { useEffect, useMemo, useState } from 'react';
import { AlertTriangle, Filter, MapPinned } from 'lucide-react';
import { CircleMarker, MapContainer, Popup, TileLayer, useMap } from 'react-leaflet';
import type { LocationRecord, SOSEvent } from '../api';
import './OperationsMap.css';

type StatusFilter = 'ALL' | 'SAFE' | 'CAUTION' | 'RESTRICTED' | 'UNKNOWN';

interface OperationsMapProps {
  locations: LocationRecord[];
  incidents: SOSEvent[];
  staleThresholdMinutes: number;
  loading: boolean;
  error?: string;
}

const fallbackCenter: [number, number] = [30.7352, 79.0669];

const hasCoordinates = <T extends { latitude: number | null; longitude: number | null }>(
  value: T,
): value is T & { latitude: number; longitude: number } =>
  typeof value.latitude === 'number' && typeof value.longitude === 'number';

const statusColor = (status?: string | null) => {
  switch ((status || 'UNKNOWN').toUpperCase()) {
    case 'RESTRICTED':
      return '#ff5f5f';
    case 'CAUTION':
      return '#f6b44b';
    case 'SAFE':
      return '#39d98a';
    default:
      return '#22d3ee';
  }
};

const isActiveIncident = (event: SOSEvent) =>
  !['RESOLVED', 'EXPIRED_NO_DELIVERY', 'EXPIRED_NO_RESPONSE'].includes(
    (event.incident_status || event.status || 'ACTIVE').toUpperCase(),
  );

const isStale = (location: LocationRecord, staleThresholdMinutes: number) => {
  if (!location.timestamp) return true;
  return Date.now() - new Date(location.timestamp).getTime() > staleThresholdMinutes * 60_000;
};

const ChangeView = ({ center }: { center: [number, number] }) => {
  const map = useMap();
  useEffect(() => {
    map.setView(center, map.getZoom(), { animate: false });
  }, [center, map]);
  return null;
};

const OperationsMap = ({
  locations,
  incidents,
  staleThresholdMinutes,
  loading,
  error,
}: OperationsMapProps) => {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('ALL');
  const [destinationFilter, setDestinationFilter] = useState('ALL');
  const [showActiveIncidents, setShowActiveIncidents] = useState(true);
  const [staleOnly, setStaleOnly] = useState(false);

  const destinationOptions = useMemo(() => {
    const values = new Set<string>();
    locations.forEach((location) => {
      if (location.destination_state) values.add(location.destination_state);
    });
    incidents.forEach((incident) => {
      if (incident.destination_state) values.add(incident.destination_state);
    });
    return [...values].sort((a, b) => a.localeCompare(b));
  }, [incidents, locations]);

  const filteredLocations = useMemo(
    () =>
      locations.filter((location) => {
        if (!hasCoordinates(location)) return false;
        const zoneStatus = (location.zone_status || 'UNKNOWN').toUpperCase();
        const destination = location.destination_state || 'Unassigned';
        if (statusFilter !== 'ALL' && zoneStatus !== statusFilter) return false;
        if (destinationFilter !== 'ALL' && destination !== destinationFilter) return false;
        if (staleOnly && !isStale(location, staleThresholdMinutes)) return false;
        return true;
      }),
    [destinationFilter, locations, staleOnly, staleThresholdMinutes, statusFilter],
  );

  const filteredIncidents = useMemo(
    () =>
      incidents.filter((incident) => {
        if (!showActiveIncidents || !isActiveIncident(incident) || !hasCoordinates(incident)) {
          return false;
        }
        const destination = incident.destination_state || 'Unassigned';
        return destinationFilter === 'ALL' || destination === destinationFilter;
      }),
    [destinationFilter, incidents, showActiveIncidents],
  );

  const center = useMemo<[number, number]>(() => {
    const incident = filteredIncidents[0];
    if (incident && hasCoordinates(incident)) return [incident.latitude, incident.longitude];
    const location = filteredLocations[0];
    if (location) return [location.latitude, location.longitude];
    return fallbackCenter;
  }, [filteredIncidents, filteredLocations]);

  const hasVisibleMarkers = filteredLocations.length > 0 || filteredIncidents.length > 0;

  return (
    <section className="ops-map-panel">
      <div className="panel-header">
        <h2>Operational map</h2>
        <span>{filteredLocations.length} tourists / {filteredIncidents.length} incidents</span>
      </div>

      <div className="map-filter-bar">
        <div className="filter-field">
          <Filter size={15} />
          <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value as StatusFilter)}>
            <option value="ALL">All statuses</option>
            <option value="SAFE">Safe</option>
            <option value="CAUTION">Caution</option>
            <option value="RESTRICTED">Restricted</option>
            <option value="UNKNOWN">Unknown</option>
          </select>
        </div>
        <div className="filter-field">
          <MapPinned size={15} />
          <select value={destinationFilter} onChange={(event) => setDestinationFilter(event.target.value)}>
            <option value="ALL">All destinations</option>
            {destinationOptions.map((destination) => (
              <option key={destination} value={destination}>
                {destination}
              </option>
            ))}
          </select>
        </div>
        <button
          className={`toggle-filter ${showActiveIncidents ? 'active' : ''}`}
          type="button"
          onClick={() => setShowActiveIncidents((current) => !current)}
        >
          <AlertTriangle size={15} />
          Active incidents
        </button>
        <button
          className={`toggle-filter ${staleOnly ? 'active' : ''}`}
          type="button"
          onClick={() => setStaleOnly((current) => !current)}
        >
          Stale tourists
        </button>
      </div>

      <div className="ops-map-wrapper">
        <MapContainer center={center} zoom={12} scrollWheelZoom style={{ height: '420px', width: '100%' }}>
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
            url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
          />
          <ChangeView center={center} />
          {filteredLocations.map((location) => {
            const stale = isStale(location, staleThresholdMinutes);
            const color = stale ? '#9aa8b8' : statusColor(location.zone_status);
            return (
              <CircleMarker
                key={`${location.tourist_id}-${location.timestamp || 'latest'}`}
                center={[location.latitude, location.longitude]}
                radius={stale ? 6 : 8}
                pathOptions={{ color, fillColor: color, fillOpacity: stale ? 0.55 : 0.82, weight: 2 }}
              >
                <Popup>
                  <div className="map-popup">
                    <strong>{location.tourist_id}</strong>
                    <span>{location.zone_status || 'UNKNOWN'} / {stale ? 'stale' : 'fresh'}</span>
                    <span>{location.destination_state || 'Unassigned'}</span>
                  </div>
                </Popup>
              </CircleMarker>
            );
          })}
          {filteredIncidents.map((incident) => (
            <CircleMarker
              key={`incident-${incident.id}`}
              center={[incident.latitude as number, incident.longitude as number]}
              radius={12}
              pathOptions={{ color: '#ff5f5f', fillColor: '#ff5f5f', fillOpacity: 0.9, weight: 3 }}
            >
              <Popup>
                <div className="map-popup">
                  <strong>SOS-{incident.id}</strong>
                  <span>{incident.tourist_id}</span>
                  <span>{incident.trigger_type} / {incident.incident_status || incident.status}</span>
                </div>
              </Popup>
            </CircleMarker>
          ))}
        </MapContainer>
        {(loading || error || !hasVisibleMarkers) && (
          <div className="ops-map-overlay">
            {loading ? 'Loading map data...' : error || 'No map markers match the selected filters.'}
          </div>
        )}
      </div>
    </section>
  );
};

export default OperationsMap;
