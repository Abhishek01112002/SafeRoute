// dashboard/src/pages/Login.tsx
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../api';
import './Login.css';

const Login = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const response = await api.post('/auth/login/authority', {
        email: email,
        password: password,
      });

      if (response.data.token) {
        localStorage.setItem('token', response.data.token);
        localStorage.setItem('authority', JSON.stringify(response.data));
        window.location.href = '/';
      }
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Authentication failed. Unauthorized access detected.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-container">
      <div className="login-box glass-panel">
        <div className="login-header">
          <h1 className="neon-text-cyan">SYS.ACCESS</h1>
          <p className="subtitle">Command Center Authorization Required</p>
        </div>

        {error && <div className="error-banner">{error}</div>}

        <form onSubmit={handleLogin} className="login-form">
          <div className="form-group">
            <label>AUTHORITY EMAIL</label>
            <input
              type="text"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="e.g. admin@saferoute.com"
              required
            />
          </div>
          
          <div className="form-group">
            <label>SECURITY KEY</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter password"
              required
            />
          </div>

          <button type="submit" className="btn-primary login-btn" disabled={loading}>
            {loading ? 'VERIFYING...' : 'INITIATE UPLINK'}
          </button>
        </form>
      </div>
    </div>
  );
};

export default Login;
