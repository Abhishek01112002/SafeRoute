// dashboard/src/pages/Login.tsx
import { useState } from 'react';
import api from '../api';
import './Login.css';

type AuthMode = 'login' | 'register';

interface RegisterForm {
  full_name: string;
  designation: string;
  department: string;
  badge_id: string;
  jurisdiction_zone: string;
  phone: string;
  email: string;
  password: string;
}

const emptyRegisterForm: RegisterForm = {
  full_name: '',
  designation: '',
  department: 'Tourism Police',
  badge_id: '',
  jurisdiction_zone: 'Uttarakhand',
  phone: '',
  email: '',
  password: '',
};

const getApiError = (err: unknown, fallback: string) => {
  const axiosError = err as {
    response?: { data?: { detail?: string | Array<{ msg?: string }> } };
    message?: string;
  };
  const detail = axiosError.response?.data?.detail;

  if (Array.isArray(detail)) {
    return detail.map((item) => item.msg).filter(Boolean).join(', ') || fallback;
  }

  return detail || axiosError.message || fallback;
};

const Login = () => {
  const [mode, setMode] = useState<AuthMode>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [registerForm, setRegisterForm] = useState<RegisterForm>(emptyRegisterForm);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const persistSession = (data: Record<string, unknown>, authorityProfile = {}) => {
    localStorage.setItem('token', String(data.token));
    localStorage.setItem(
      'authority',
      JSON.stringify({
        ...authorityProfile,
        ...data,
      }),
    );
    window.location.href = '/';
  };

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
        persistSession(response.data);
      }
    } catch (err: unknown) {
      setError(getApiError(err, 'Authentication failed. Please check your email and password.'));
    } finally {
      setLoading(false);
    }
  };

  const handleRegisterChange = (field: keyof RegisterForm, value: string) => {
    setRegisterForm((current) => ({ ...current, [field]: value }));
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const payload = {
        ...registerForm,
        email: registerForm.email.trim(),
        badge_id: registerForm.badge_id.trim(),
        full_name: registerForm.full_name.trim(),
      };
      const response = await api.post('/auth/register/authority', payload);

      if (response.data.token) {
        persistSession(response.data, {
          full_name: payload.full_name,
          designation: payload.designation,
          department: payload.department,
          badge_id: payload.badge_id,
          jurisdiction_zone: payload.jurisdiction_zone,
          phone: payload.phone,
          email: payload.email,
          role: 'authority',
        });
      }
    } catch (err: unknown) {
      setError(getApiError(err, 'Registration failed. Please check all authority details.'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-container">
      <div className="login-box glass-panel">
        <div className="login-header">
          <h1>SafeRoute Command</h1>
          <p className="subtitle">
            {mode === 'login'
              ? 'Authority dashboard authorization required'
              : 'Create an authority account for this command centre'}
          </p>
        </div>

        <div className="auth-tabs" role="tablist" aria-label="Authority access mode">
          <button
            type="button"
            className={mode === 'login' ? 'active' : ''}
            onClick={() => {
              setMode('login');
              setError('');
            }}
          >
            Sign in
          </button>
          <button
            type="button"
            className={mode === 'register' ? 'active' : ''}
            onClick={() => {
              setMode('register');
              setError('');
            }}
          >
            Register authority
          </button>
        </div>

        {error && <div className="error-banner">{error}</div>}

        {mode === 'login' ? (
          <form onSubmit={handleLogin} className="login-form">
            <div className="form-group">
              <label>Authority email</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="e.g. admin@saferoute.com"
                required
              />
            </div>

            <div className="form-group">
              <label>Password</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Enter password"
                required
              />
            </div>

            <button type="submit" className="btn-primary login-btn" disabled={loading}>
              {loading ? 'Verifying...' : 'Sign in'}
            </button>
          </form>
        ) : (
          <form onSubmit={handleRegister} className="login-form register-form">
            <div className="form-grid">
              <div className="form-group wide">
                <label>Full name</label>
                <input
                  type="text"
                  value={registerForm.full_name}
                  onChange={(e) => handleRegisterChange('full_name', e.target.value)}
                  placeholder="e.g. District Control Officer"
                  required
                />
              </div>

              <div className="form-group">
                <label>Designation</label>
                <input
                  type="text"
                  value={registerForm.designation}
                  onChange={(e) => handleRegisterChange('designation', e.target.value)}
                  placeholder="e.g. Inspector"
                />
              </div>

              <div className="form-group">
                <label>Department</label>
                <input
                  type="text"
                  value={registerForm.department}
                  onChange={(e) => handleRegisterChange('department', e.target.value)}
                  placeholder="e.g. Tourism Police"
                />
              </div>

              <div className="form-group">
                <label>Badge ID</label>
                <input
                  type="text"
                  value={registerForm.badge_id}
                  onChange={(e) => handleRegisterChange('badge_id', e.target.value)}
                  placeholder="e.g. UK-AUTH-001"
                  required
                />
              </div>

              <div className="form-group">
                <label>Jurisdiction</label>
                <input
                  type="text"
                  value={registerForm.jurisdiction_zone}
                  onChange={(e) => handleRegisterChange('jurisdiction_zone', e.target.value)}
                  placeholder="e.g. Uttarakhand"
                />
              </div>

              <div className="form-group">
                <label>Phone</label>
                <input
                  type="tel"
                  value={registerForm.phone}
                  onChange={(e) => handleRegisterChange('phone', e.target.value)}
                  placeholder="+91-9000000000"
                />
              </div>

              <div className="form-group">
                <label>Email</label>
                <input
                  type="email"
                  value={registerForm.email}
                  onChange={(e) => handleRegisterChange('email', e.target.value)}
                  placeholder="authority@saferoute.gov.in"
                  required
                />
              </div>

              <div className="form-group wide">
                <label>Password</label>
                <input
                  type="password"
                  value={registerForm.password}
                  onChange={(e) => handleRegisterChange('password', e.target.value)}
                  placeholder="Min 12 chars with upper, lower, number, special"
                  minLength={12}
                  required
                />
              </div>
            </div>

            <p className="password-note">
              Password must include uppercase, lowercase, number, and one special character: @$!%*?&
            </p>

            <button type="submit" className="btn-primary login-btn" disabled={loading}>
              {loading ? 'Creating account...' : 'Register and enter dashboard'}
            </button>
          </form>
        )}
      </div>
    </div>
  );
};

export default Login;
