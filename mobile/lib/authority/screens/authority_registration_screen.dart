import 'package:flutter/material.dart';
import 'dart:async';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/utils/validators.dart';
import 'package:saferoute/widgets/loading_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/authority/screens/authority_dashboard_screen.dart';
import 'package:saferoute/core/service_locator.dart';

class AuthorityRegistrationScreen extends StatefulWidget {
  const AuthorityRegistrationScreen({super.key});

  @override
  State<AuthorityRegistrationScreen> createState() => _AuthorityRegistrationScreenState();
}

class _AuthorityRegistrationScreenState extends State<AuthorityRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  String _fullName = '';
  String _designation = '';
  String _department = 'Police';
  String _badgeId = '';
  String _jurisdiction = 'All Zones';
  String _phone = '';
  String _email = '';
  String _password = '';

  final List<String> _departments = ['Police', 'Forest Dept', 'Tourism Dept', 'Home Affairs'];

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    try {
      final api = locator<ApiService>();
      final response = await api.registerAuthority({
        'full_name': _fullName,
        'designation': _designation,
        'department': _department,
        'badge_id': _badgeId,
        'jurisdiction_zone': _jurisdiction,
        'phone': _phone,
        'email': _email,
        'password': _password,
      });

      if (mounted) {
        if (response['status'] == 'active') {
          // FIX: capture navigator before awaits
          final navigator = Navigator.of(context);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('role', 'authority');
          await prefs.setString('authority_id', response['authority_id']);

          unawaited(navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthorityDashboardScreen()),
            (route) => false,
          ));
        } else {
          _showSuccessDialog();
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

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Registration Pending"),
        content: const Text("Your authority account is under review. You will be notified within 24 hours once approved by the administrator."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context); // Go back to onboarding
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text("Authority Registration")),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("🛡️ Official Credentials", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person)),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                    onSaved: (v) => _fullName = v!,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Designation (e.g. Inspector)", prefixIcon: Icon(Icons.work)),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                    onSaved: (v) => _designation = v!,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _department,
                    decoration: const InputDecoration(labelText: "Department", prefixIcon: Icon(Icons.account_balance)),
                    items: _departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (v) => setState(() => _department = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Badge / Employee ID", prefixIcon: Icon(Icons.badge)),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                    onSaved: (v) => _badgeId = v!,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Jurisdiction Zone", prefixIcon: Icon(Icons.map)),
                    onSaved: (v) => _jurisdiction = v!,
                  ),
                  const SizedBox(height: 32),
                  const Text("🔐 Login Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Official Email", prefixIcon: Icon(Icons.email)),
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
                    decoration: const InputDecoration(labelText: "Official Phone", prefixIcon: Icon(Icons.phone)),
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return "Required";
                      final digitsOnly = RegExp(r'^\d{10}$');
                      return digitsOnly.hasMatch(value) ? null : "Enter 10-digit phone";
                    },
                    onSaved: (v) => _phone = v!,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock)),
                    obscureText: true,
                    validator: (v) {
                      final value = (v ?? '');
                      if (value.length < 8) return "Min 8 characters";
                      if (!RegExp(r'[A-Z]').hasMatch(value)) return "Add one uppercase letter";
                      if (!RegExp(r'[a-z]').hasMatch(value)) return "Add one lowercase letter";
                      if (!RegExp(r'\d').hasMatch(value)) return "Add one number";
                      if (!RegExp(r'[!@#$%^&*()\-_=+]').hasMatch(value)) {
                        return "Add one special character";
                      }
                      return null;
                    },
                    onSaved: (v) => _password = v!,
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Submit for Verification", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading) const LoadingOverlay(message: "Submitting request..."),
      ],
    );
  }
}
