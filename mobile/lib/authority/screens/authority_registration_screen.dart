import 'dart:async';

import 'package:flutter/material.dart';
import 'package:saferoute/authority/screens/authority_dashboard_screen.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/utils/validators.dart';
import 'package:saferoute/widgets/app_ui.dart';
import 'package:saferoute/widgets/loading_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthorityRegistrationScreen extends StatefulWidget {
  const AuthorityRegistrationScreen({super.key});

  @override
  State<AuthorityRegistrationScreen> createState() =>
      _AuthorityRegistrationScreenState();
}

class _AuthorityRegistrationScreenState
    extends State<AuthorityRegistrationScreen> {
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

  final List<String> _departments = [
    'Police',
    'Forest Dept',
    'Tourism Dept',
    'Home Affairs',
  ];

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
          SnackBar(
              content: Text(e.toString()), backgroundColor: AppColors.danger),
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
        title: const Text("Registration pending"),
        content: const Text(
          "Your authority account is under review. You will be notified within 24 hours once approved by the administrator.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text("Authority registration")),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSectionHeader(
                      title: 'Register authority personnel',
                      subtitle:
                          'Submit official details for command center access.',
                      trailing: Icon(Icons.verified_user_rounded,
                          color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 18),
                    AppSurface(
                      child: Column(
                        children: [
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: "Full name",
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (v) => v!.isEmpty ? "Required" : null,
                            onSaved: (v) => _fullName = v!,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: "Designation",
                              prefixIcon: Icon(Icons.work_outline_rounded),
                            ),
                            validator: (v) => v!.isEmpty ? "Required" : null,
                            onSaved: (v) => _designation = v!,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _department,
                            decoration: const InputDecoration(
                              labelText: "Department",
                              prefixIcon: Icon(Icons.account_balance_outlined),
                            ),
                            items: _departments
                                .map((d) =>
                                    DropdownMenuItem(value: d, child: Text(d)))
                                .toList(),
                            onChanged: (v) => setState(() => _department = v!),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: "Badge / employee ID",
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (v) => v!.isEmpty ? "Required" : null,
                            onSaved: (v) => _badgeId = v!,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: "Jurisdiction zone",
                              prefixIcon: Icon(Icons.map_outlined),
                            ),
                            onSaved: (v) => _jurisdiction = v!,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
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
                              labelText: "Official phone",
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (v) {
                              final value = (v ?? '').trim();
                              if (value.isEmpty) return "Required";
                              final digitsOnly = RegExp(r'^\d{10}$');
                              return digitsOnly.hasMatch(value)
                                  ? null
                                  : "Enter 10-digit phone";
                            },
                            onSaved: (v) => _phone = v!,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: "Password",
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                            obscureText: true,
                            validator: (v) {
                              final value = (v ?? '');
                              if (value.length < 8) return "Min 8 characters";
                              if (!RegExp(r'[A-Z]').hasMatch(value)) {
                                return "Add one uppercase letter";
                              }
                              if (!RegExp(r'[a-z]').hasMatch(value)) {
                                return "Add one lowercase letter";
                              }
                              if (!RegExp(r'\d').hasMatch(value)) {
                                return "Add one number";
                              }
                              if (!RegExp(r'[!@#$%^&*()\-_=+]')
                                  .hasMatch(value)) {
                                return "Add one special character";
                              }
                              return null;
                            },
                            onSaved: (v) => _password = v!,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: AppSpacing.fieldActionTarget,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _submit,
                        icon: const Icon(Icons.how_to_reg_rounded),
                        label: const Text("Submit for verification"),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isLoading) const LoadingOverlay(message: "Submitting request..."),
      ],
    );
  }
}
