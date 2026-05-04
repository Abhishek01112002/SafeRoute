// dashboard/src/components/Layout.tsx
import { Outlet, NavLink } from 'react-router-dom';
import { Activity, Map, ShieldAlert, LogOut } from 'lucide-react';
import './Layout.css';

const Layout = () => {

  const handleLogout = () => {
    localStorage.removeItem('token');
    window.location.href = '/login';
  };

  return (
    <div className="layout-container">
      <aside className="sidebar glass-panel">
        <div className="sidebar-header">
          <h2 className="neon-text-cyan">SafeRoute</h2>
          <span className="subtitle">Command Center</span>
        </div>

        <nav className="sidebar-nav">
          <NavLink to="/" className={({ isActive }) => (isActive ? 'nav-item active' : 'nav-item')}>
            <Activity size={20} />
            <span>Overview</span>
          </NavLink>
          <NavLink to="/zones" className={({ isActive }) => (isActive ? 'nav-item active' : 'nav-item')}>
            <Map size={20} />
            <span>Zone Manager</span>
          </NavLink>
          <NavLink to="/sos" className={({ isActive }) => (isActive ? 'nav-item active' : 'nav-item')}>
            <ShieldAlert size={20} />
            <span>SOS Events</span>
          </NavLink>
        </nav>

        <div className="sidebar-footer">
          <button className="nav-item logout-btn" onClick={handleLogout}>
            <LogOut size={20} />
            <span>Disconnect</span>
          </button>
        </div>
      </aside>

      <main className="main-content">
        <Outlet />
      </main>
    </div>
  );
};

export default Layout;
