// lib/screens/authority_login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/authority/screens/authority_dashboard_screen.dart';
import 'package:saferoute/utils/validators.dart';
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
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text("Authority Login")),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.security, size: 80, color: Colors.blueGrey),
                  const SizedBox(height: 32),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Official Email", border: OutlineInputBorder()),
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
                      border: OutlineInputBorder(),
                      helperText: "Min 12 chars, uppercase, lowercase, number & symbol",
                      helperMaxLines: 2,
                    ),
                    obscureText: true,
                    validator: (v) {
                      final value = v ?? '';
                      if (value.isEmpty) return "Password required";
                      if (value.length < 12) return "Min 12 characters";
                      if (!RegExp(r'^(?=.*[a-z])').hasMatch(value)) return "Need lowercase letter";
                      if (!RegExp(r'^(?=.*[A-Z])').hasMatch(value)) return "Need uppercase letter";
                      if (!RegExp(r'^(?=.*\d)').hasMatch(value)) return "Need number";
                      if (!RegExp(r'^(?=.*[@$!%*?&])').hasMatch(value)) return "Need special char (@\$!%*?&)";
                      return null;
                    },
                    onSaved: (v) => _password = v!,
                  ),
                  if (_isLocked)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Account locked. Try again after ${_lockUntil?.difference(DateTime.now()).inMinutes ?? 15} minutes.",
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[800],
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("LOGIN TO COMMAND CENTER"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading) const LoadingOverlay(message: "Authenticating..."),
      ],
    );
  }
}
