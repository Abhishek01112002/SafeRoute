// dashboard/src/components/ZoneMap.tsx
import React, { useState, useEffect, useMemo } from 'react';
import { MapContainer, TileLayer, Polygon, Circle, Marker, useMapEvents, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import './ZoneMap.css';

// Fix for default marker icons in Leaflet with Vite/React
import icon from 'leaflet/dist/images/marker-icon.png';
import iconShadow from 'leaflet/dist/images/marker-shadow.png';

let DefaultIcon = L.icon({
    iconUrl: icon,
    shadowUrl: iconShadow,
    iconSize: [25, 41],
    iconAnchor: [12, 41]
});
L.Marker.prototype.options.icon = DefaultIcon;

interface Point {
  lat: number;
  lng: number;
}

interface Zone {
  id: string;
  name: string;
  type: string;
  shape: string;
  center_lat: number;
  center_lng: number;
  radius_m: number | null;
  polygon_points: {lat: number, lng: number}[];
}

interface ZoneMapProps {
  center: [number, number];
  existingZones: Zone[];
  drawingMode: boolean;
  onPointsChange?: (points: Point[]) => void;
  onRadiusChange?: (radius: number) => void;
  zoneType?: string;
  currentShape?: string;
}

// Internal component to handle map clicks for drawing
const MapClickHandler = ({ onMapClick }: { onMapClick: (latlng: L.LatLng) => void }) => {
  useMapEvents({
    click(e) {
      onMapClick(e.latlng);
    },
  });
  return null;
};

// Internal component to handle auto-centering
const ChangeView = ({ center }: { center: [number, number] }) => {
  const map = useMap();
  useEffect(() => {
    map.setView(center, 15);
  }, [center, map]);
  return null;
};

const ZoneMap: React.FC<ZoneMapProps> = ({ 
  center, 
  existingZones, 
  drawingMode, 
  onPointsChange, 
  onRadiusChange,
  zoneType = 'SAFE',
  currentShape = 'CIRCLE'
}) => {
  const [newPoints, setNewPoints] = useState<Point[]>([]);
  const [tempRadius, setTempRadius] = useState<number>(500);

  // Sync internal points to parent
  useEffect(() => {
    if (onPointsChange) onPointsChange(newPoints);
  }, [newPoints, onPointsChange]);

  const handleMapClick = (latlng: L.LatLng) => {
    if (!drawingMode) return;
    
    if (currentShape === 'CIRCLE') {
      setNewPoints([{ lat: latlng.lat, lng: latlng.lng }]);
    } else {
      setNewPoints([...newPoints, { lat: latlng.lat, lng: latlng.lng }]);
    }
  };

  const handleMarkerDrag = (index: number, e: L.LeafletEvent) => {
    const marker = e.target;
    const position = marker.getLatLng();
    const updatedPoints = [...newPoints];
    updatedPoints[index] = { lat: position.lat, lng: position.lng };
    setNewPoints(updatedPoints);
  };

  const getZoneColor = (type: string) => {
    switch (type.toUpperCase()) {
      case 'RESTRICTED': return '#ff2a2a';
      case 'CAUTION': return '#ffb703';
      case 'SAFE': return '#39ff14';
      default: return '#00e5ff';
    }
  };

  return (
    <div className="zone-map-wrapper glass-panel">
      <MapContainer center={center} zoom={15} scrollWheelZoom={true} style={{ height: '500px', width: '100%' }}>
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
          url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
        />
        <ChangeView center={center} />
        
        {/* Existing Zones */}
        {existingZones.map(zone => {
          const color = getZoneColor(zone.type);
          if (zone.shape === 'CIRCLE') {
            return (
              <Circle 
                key={zone.id}
                center={[zone.center_lat, zone.center_lng]}
                radius={zone.radius_m || 100}
                pathOptions={{ color, fillColor: color, fillOpacity: 0.2 }}
              />
            );
          } else {
            const points = zone.polygon_points || [];
            if (points.length < 3) return null;
            return (
              <Polygon 
                key={zone.id}
                positions={points.map(p => [p.lat, p.lng] as [number, number])}
                pathOptions={{ color, fillColor: color, fillOpacity: 0.2 }}
              />
            );
          }
        })}

        {/* Current Drawing Shape */}
        {drawingMode && (
          <>
            <MapClickHandler onMapClick={handleMapClick} />
            
            {currentShape === 'CIRCLE' && newPoints.length > 0 && (
              <Circle 
                center={[newPoints[0].lat, newPoints[0].lng]}
                radius={tempRadius}
                pathOptions={{ color: getZoneColor(zoneType), dashArray: '5, 5' }}
              />
            )}

            {currentShape === 'POLYGON' && newPoints.length > 0 && (
              <>
                <Polygon 
                  positions={newPoints.map(p => [p.lat, p.lng] as [number, number])}
                  pathOptions={{ color: getZoneColor(zoneType), dashArray: '5, 5' }}
                />
                {newPoints.map((p, i) => (
                  <Marker 
                    key={i} 
                    position={[p.lat, p.lng]} 
                    draggable={true}
                    eventHandlers={{ dragend: (e) => handleMarkerDrag(i, e) }}
                  />
                ))}
              </>
            )}
          </>
        )}
      </MapContainer>
      
      {drawingMode && (
        <div className="map-controls">
          <p className="neon-text-cyan">
            {currentShape === 'POLYGON' 
              ? 'Click to add points. Drag markers to adjust.' 
              : 'Click to set center. Enter radius below.'}
          </p>
          <div className="control-button-group">
            <button 
              className="btn-secondary btn-small" 
              onClick={() => setNewPoints(newPoints.slice(0, -1))}
              disabled={newPoints.length === 0}
            >
              UNDO POINT
            </button>
            <button 
              className="btn-danger btn-small" 
              onClick={() => setNewPoints([])}
              disabled={newPoints.length === 0}
            >
              CLEAR ALL
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default ZoneMap;
