export type DashboardPermission =
  | 'overview:view'
  | 'zones:view'
  | 'zones:manage'
  | 'sos:view'
  | 'sos:respond'
  | 'map:view';

export interface AuthoritySession {
  authority_id?: string;
  full_name?: string;
  designation?: string;
  department?: string;
  badge_id?: string;
  jurisdiction_zone?: string;
  email?: string;
  role?: string;
  status?: string;
  permissions?: DashboardPermission[];
}

const rolePermissions: Record<string, DashboardPermission[]> = {
  authority: [
    'overview:view',
    'zones:view',
    'zones:manage',
    'sos:view',
    'sos:respond',
    'map:view',
  ],
  superadmin: [
    'overview:view',
    'zones:view',
    'zones:manage',
    'sos:view',
    'sos:respond',
    'map:view',
  ],
};

const activeStatuses = new Set(['active', 'approved', 'enabled']);

export const readAuthoritySession = (): AuthoritySession | null => {
  const token = localStorage.getItem('token');
  if (!token) return null;

  try {
    const raw = localStorage.getItem('authority');
    const parsed = raw ? (JSON.parse(raw) as AuthoritySession) : {};
    const role = (parsed.role || 'authority').toLowerCase();
    const status = (parsed.status || 'active').toLowerCase();
    return {
      ...parsed,
      role,
      status,
    };
  } catch {
    return {
      role: 'authority',
      status: 'active',
    };
  }
};

export const getSessionPermissions = (session: AuthoritySession | null): DashboardPermission[] => {
  if (!session) return [];
  if (!activeStatuses.has((session.status || '').toLowerCase())) return [];
  if (session.permissions?.length) return session.permissions;
  return rolePermissions[(session.role || '').toLowerCase()] ?? [];
};

export const hasPermission = (
  session: AuthoritySession | null,
  permission: DashboardPermission,
) => getSessionPermissions(session).includes(permission);

export const hasAnyDashboardPermission = (session: AuthoritySession | null) =>
  getSessionPermissions(session).length > 0;

export const getLandingPath = (session: AuthoritySession | null) => {
  if (hasPermission(session, 'overview:view')) return '/';
  if (hasPermission(session, 'sos:view')) return '/sos';
  if (hasPermission(session, 'zones:view')) return '/zones';
  return '/login';
};
