// lib/screens/authority_login_screen.dart
import 'package:flutter/material.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/screens/authority_dashboard_screen.dart';
import 'package:saferoute/widgets/loading_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      final api = ApiService();
      final authData = await api.loginAuthority(_email, _password);
      
      if (authData['status'] == 'pending_verification') {
        _showPendingDialog();
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('role', 'authority');
        await prefs.setString('authority_id', authData['authority_id']);
        
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthorityDashboardScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPendingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Access Restricted"),
        content: const Text("Your account is still under verification. Please wait for administrative approval."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
        ],
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
                    validator: (v) => v!.isEmpty ? "Required" : null,
                    onSaved: (v) => _email = v!,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()),
                    obscureText: true,
                    validator: (v) => v!.isEmpty ? "Required" : null,
                    onSaved: (v) => _password = v!,
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
