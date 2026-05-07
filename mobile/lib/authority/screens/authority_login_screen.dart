// lib/screens/authority_login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/authority/screens/authority_dashboard_screen.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/utils/validators.dart';
import 'package:saferoute/widgets/app_ui.dart';
import 'package:saferoute/widgets/loading_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/core/service_locator.dart';

class AuthorityLoginScreen extends StatefulWidget {
  const AuthorityLoginScreen({super.key});

  @override
  State<AuthorityLoginScreen> createState() => _AuthorityLoginScreenState();
}

class _AuthorityLoginScreenState extends State<AuthorityLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _isLoading = false;
  int _failedAttempts = 0;
  bool _isLocked = false;
  DateTime? _lockUntil;

  Future<void> _login() async {
    if (_isLocked) {
      final remaining = _lockUntil?.difference(DateTime.now()).inSeconds ?? 0;
      _showError('Account locked. Try again in ${remaining}s');
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() {
      _isLoading = true;
    });

    try {
      final api = locator<ApiService>();
      final authData = await api.loginAuthority(_email, _password);

      // Reset failed attempts on success
      setState(() {
        _failedAttempts = 0;
        _isLocked = false;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('role', 'authority');
      await prefs.setString('authority_id', authData['authority_id']);
      await prefs.setString('last_login', DateTime.now().toIso8601String());

      if (mounted) {
        final navigator = Navigator.of(context);
        unawaited(navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthorityDashboardScreen()),
          (route) => false,
        ));
      }
    } on ApiException catch (e) {
      _handleFailedLogin(e);
    } catch (e) {
      _showError('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleFailedLogin(ApiException e) {
    setState(() => _failedAttempts++);

    // Check for specific error messages from backend
    final msg = e.message.toLowerCase();
    if (msg.contains('suspended') || msg.contains('deactivated')) {
      _showError('Account access restricted. Contact administrator.');
      return;
    }
    if (msg.contains('invalid')) {
      final remaining = 5 - _failedAttempts;
      if (remaining > 0) {
        _showError('Invalid credentials. $remaining attempts remaining.');
      } else {
        _triggerLockout();
      }
    } else {
      _showError(e.message);
    }
  }

  void _triggerLockout() {
    setState(() {
      _isLocked = true;
      _lockUntil = DateTime.now().add(const Duration(minutes: 15));
    });
    _showError('Too many failed attempts. Account locked for 15 minutes.');

    // Auto-unlock after 15 minutes
    unawaited(Future.delayed(const Duration(minutes: 15), () {
      if (mounted) {
        setState(() {
          _isLocked = false;
          _failedAttempts = 0;
          _lockUntil = null;
        });
      }
    }));
  }

  void _showError(String message) {
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text("Authority login")),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 28),
                    Icon(Icons.security_rounded,
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 20),
                    Text(
                      'Access Authority Hub',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use your official credentials to review zones and SOS events.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                    const SizedBox(height: 28),
                    AppSurface(
                      child: Column(
                        children: [
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: "Official email",
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              final value = (v ?? '').trim();
                              if (value.isEmpty) return "Required";
                              return Validators.validateEmail(value);
                            },
                            onSaved: (v) => _email = v!,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: "Password",
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                              helperText:
                                  "Min 12 chars, uppercase, lowercase, number and symbol",
                              helperMaxLines: 2,
                            ),
                            obscureText: true,
                            validator: (v) {
                              final value = v ?? '';
                              if (value.isEmpty) return "Password required";
                              if (value.length < 12) return "Min 12 characters";
                              if (!RegExp(r'^(?=.*[a-z])').hasMatch(value)) {
                                return "Need lowercase letter";
                              }
                              if (!RegExp(r'^(?=.*[A-Z])').hasMatch(value)) {
                                return "Need uppercase letter";
                              }
                              if (!RegExp(r'^(?=.*\d)').hasMatch(value)) {
                                return "Need number";
                              }
                              if (!RegExp(r'^(?=.*[@$!%*?&])')
                                  .hasMatch(value)) {
                                return "Need special char (@\$!%*?&)";
                              }
                              return null;
                            },
                            onSaved: (v) => _password = v!,
                          ),
                          if (_isLocked) ...[
                            const SizedBox(height: 14),
                            AppErrorState(
                              message:
                                  "Account locked. Try again after ${_lockUntil?.difference(DateTime.now()).inMinutes ?? 15} minutes.",
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: AppSpacing.fieldActionTarget,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _login,
                              icon: const Icon(Icons.login_rounded),
                              label: const Text("Login to Authority Hub"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isLoading) const LoadingOverlay(message: "Authenticating..."),
      ],
    );
  }
}
