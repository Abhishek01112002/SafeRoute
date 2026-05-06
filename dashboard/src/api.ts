import axios from 'axios';

export const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8000';
export const POLL_INTERVAL_MS = 10_000;

export interface DashboardMetrics {
  active_zones: number;
  registered_tourists: number;
  active_sos: number;
  resolved_sos: number;
  active_trips: number;
  planned_trips: number;
  completed_trips: number;
  cancelled_trips: number;
}

export interface DashboardAnalytics {
  generated_at: string;
  metrics: DashboardMetrics;
  freshness: {
    last_location_ping_at: string | null;
    stale_tourist_count: number;
    stale_threshold_minutes: number;
    latest_sos_at: string | null;
  };
  zone_breakdown: Record<'SAFE' | 'CAUTION' | 'RESTRICTED' | 'UNKNOWN', number>;
  sos_breakdown: {
    by_status: Record<string, number>;
    by_trigger_type: Record<string, number>;
    by_dispatch_status: Record<string, number>;
  };
  recent_activity: ActivityItem[];
}

export interface ActivityItem {
  type: 'sos' | 'location' | 'trip' | 'tourist';
  id: string;
  tourist_id?: string;
  tuid?: string | null;
  label: string;
  status: string;
  timestamp: string | null;
}

export interface LocationRecord {
  tourist_id: string;
  tuid?: string | null;
  latitude: number;
  longitude: number;
  speed_kmh?: number | null;
  accuracy_meters?: number | null;
  zone_status?: string | null;
  timestamp?: string | null;
}

export interface SOSEvent {
  id: number;
  tourist_id: string;
  tuid?: string | null;
  group_id?: string | null;
  latitude: number;
  longitude: number;
  trigger_type: string;
  dispatch_status?: string | null;
  status: 'ACTIVE' | 'RESOLVED' | string;
  timestamp: string;
}

export interface Zone {
  id: string;
  destination_id: string;
  name: string;
  type: string;
  shape: string;
  center_lat: number;
  center_lng: number;
  radius_m: number | null;
  polygon_points: { lat: number; lng: number }[];
}

export interface Destination {
  id: string;
  state?: string;
  name: string;
  district?: string;
  category?: string | null;
  difficulty?: string | null;
  connectivity?: string | null;
  center_lat: number;
  center_lng: number;
}

export interface Readiness {
  status: 'ready' | 'degraded' | string;
  checks?: Record<string, boolean>;
  timestamp?: string;
}

const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 10000,
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error?.response?.status === 401) {
      localStorage.removeItem('token');
      localStorage.removeItem('authority');
      if (window.location.pathname !== '/login') {
        window.location.href = '/login';
      }
    }
    return Promise.reject(error);
  },
);

export const getErrorMessage = (error: unknown) => {
  if (axios.isAxiosError(error)) {
    const detail = error.response?.data?.detail ?? error.response?.data?.message;
    if (typeof detail === 'string') return detail;
    if (detail) return JSON.stringify(detail);
    if (error.code === 'ECONNABORTED') {
      return 'Backend request timed out. Check API availability and network path.';
    }
    return error.message || 'Backend request failed.';
  }
  return error instanceof Error ? error.message : 'Unexpected error.';
};

export const fetchReadiness = async () => {
  const response = await api.get<Readiness>('/ready');
  return response.data;
};

export const fetchDashboardAnalytics = async () => {
  const response = await api.get<DashboardAnalytics>('/dashboard/analytics');
  return response.data;
};

export const fetchLocations = async (limit = 50, offset = 0) => {
  const response = await api.get<LocationRecord[]>('/dashboard/locations', {
    params: { limit, offset },
  });
  return response.data;
};

export const fetchSosEvents = async (limit = 50, offset = 0) => {
  const response = await api.get<SOSEvent[]>('/sos/events', {
    params: { limit, offset },
  });
  return response.data;
};

export const respondToSos = async (eventId: number) => {
  const response = await api.post(`/sos/events/${eventId}/respond`, {
    response: 'Response initiated from command centre',
  });
  return response.data;
};

export default api;
