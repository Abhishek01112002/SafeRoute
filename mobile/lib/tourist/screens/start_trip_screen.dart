// lib/tourist/screens/start_trip_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:saferoute/tourist/providers/trip_provider.dart';
import 'package:saferoute/utils/app_theme.dart';

/// StartTripScreen — lets a tourist create a new trip with one or more stops.
class StartTripScreen extends StatefulWidget {
  const StartTripScreen({super.key});

  @override
  State<StartTripScreen> createState() => _StartTripScreenState();
}

class _StartTripScreenState extends State<StartTripScreen> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _tripStart;
  DateTime? _tripEnd;
  String? _notes;
  final List<_StopDraft> _stops = [_StopDraft()];
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final surf = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final divider = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surf,
        title: Text('Start a New Trip', style: TextStyle(color: textPrimary)),
        iconTheme: IconThemeData(color: textPrimary),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionTitle('Trip Dates', textPrimary),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _dateTile(
                    'Start Date', _tripStart,
                    (d) => setState(() => _tripStart = d),
                    surf: surf, textPrimary: textPrimary,
                    textSecondary: textSecondary, divider: divider,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateTile(
                    'End Date', _tripEnd,
                    (d) => setState(() => _tripEnd = d),
                    surf: surf, textPrimary: textPrimary,
                    textSecondary: textSecondary, divider: divider,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _sectionTitle('Destinations / Stops', textPrimary),
            const SizedBox(height: 4),
            Text(
              'Add all the places you plan to visit in order.',
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ..._stops.asMap().entries.map((e) => _StopCard(
                  index: e.key,
                  draft: e.value,
                  onRemove: _stops.length > 1
                      ? () => setState(() => _stops.removeAt(e.key))
                      : null,
                  tripStart: _tripStart,
                  tripEnd: _tripEnd,
                  bg: bg,
                  surf: surf,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  divider: divider,
                )),

            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _stops.add(_StopDraft())),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Add Another Stop'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 24),
            _sectionTitle('Notes (optional)', textPrimary),
            const SizedBox(height: 8),
            TextFormField(
              onChanged: (v) => _notes = v.trim().isEmpty ? null : v.trim(),
              maxLines: 2,
              style: TextStyle(color: textPrimary),
              decoration: _inputDecoration(
                'E.g. "Trekking Kedarnath with family"',
                surf: surf, textSecondary: textSecondary, divider: divider,
              ),
            ),

            const SizedBox(height: 32),
            _submitting
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Start Trip',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tripStart == null || _tripEnd == null) {
      _showError('Please select trip start and end dates.');
      return;
    }
    if (!_tripEnd!.isAfter(_tripStart!)) {
      _showError('Trip end date must be after start date.');
      return;
    }
    for (final stop in _stops) {
      if (stop.name.trim().isEmpty) {
        _showError('Each stop must have a destination name.');
        return;
      }
      if (stop.from == null || stop.to == null) {
        _showError('Each stop must have visit dates.');
        return;
      }
    }

    setState(() => _submitting = true);

    final drafts = _stops.asMap().entries.map((e) => TripStopDraft(
          name: e.value.name.trim(),
          destinationId: e.value.destinationId,
          destinationState: e.value.state,
          visitDateFrom: e.value.from!,
          visitDateTo: e.value.to!,
          orderIndex: e.key + 1,
        )).toList();

    final trip = await context.read<TripProvider>().createTrip(
          startDate: _tripStart!,
          endDate: _tripEnd!,
          stops: drafts,
          notes: _notes,
        );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (trip != null) {
      Navigator.of(context).pop(true);
    } else {
      final err = context.read<TripProvider>().error ?? 'Failed to create trip';
      _showError(err);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  Widget _sectionTitle(String text, Color color) => Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      );

  Widget _dateTile(
    String label,
    DateTime? value,
    ValueChanged<DateTime> onPick, {
    required Color surf,
    required Color textPrimary,
    required Color textSecondary,
    required Color divider,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
            child: child!,
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surf,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: textSecondary, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              value != null ? DateFormat('dd MMM yyyy').format(value) : 'Pick date',
              style: TextStyle(
                color: value != null ? textPrimary : textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint, {
    required Color surf,
    required Color textSecondary,
    required Color divider,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: textSecondary),
        filled: true,
        fillColor: surf,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary)),
      );
}

// ---------------------------------------------------------------------------
// Stop draft + card
// ---------------------------------------------------------------------------

class _StopDraft {
  String name = '';
  String? destinationId;
  String? state;
  DateTime? from;
  DateTime? to;
}

class _StopCard extends StatefulWidget {
  final int index;
  final _StopDraft draft;
  final VoidCallback? onRemove;
  final DateTime? tripStart;
  final DateTime? tripEnd;
  final Color bg;
  final Color surf;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;

  const _StopCard({
    required this.index,
    required this.draft,
    this.onRemove,
    this.tripStart,
    this.tripEnd,
    required this.bg,
    required this.surf,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
  });

  @override
  State<_StopCard> createState() => _StopCardState();
}

class _StopCardState extends State<_StopCard> {
  static const _states = [
    'Uttarakhand', 'Himachal Pradesh', 'Jammu and Kashmir', 'Sikkim',
    'Arunachal Pradesh', 'Meghalaya', 'Assam', 'Manipur', 'Nagaland',
    'Mizoram', 'Tripura', 'West Bengal', 'Rajasthan', 'Kerala', 'Goa',
    'Maharashtra', 'Karnataka', 'Tamil Nadu', 'Andhra Pradesh',
  ];

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.surf,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.primary.withAlpha(40),
                child: Text(
                  '${widget.index + 1}',
                  style: const TextStyle(
                      color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text('Stop', style: TextStyle(color: widget.textSecondary, fontSize: 13)),
              const Spacer(),
              if (widget.onRemove != null)
                GestureDetector(
                  onTap: widget.onRemove,
                  child: const Icon(Icons.remove_circle_outline,
                      color: AppColors.danger, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: d.name,
            onChanged: (v) => d.name = v,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter destination name' : null,
            style: TextStyle(color: widget.textPrimary),
            decoration: _dec('Destination name (e.g. Kedarnath)'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: d.state,
            hint: Text('Select state', style: TextStyle(color: widget.textSecondary)),
            dropdownColor: widget.surf,
            style: TextStyle(color: widget.textPrimary),
            items: _states
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => d.state = v),
            decoration: _dec(''),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _datePick('From', d.from, (dt) => setState(() => d.from = dt))),
              const SizedBox(width: 10),
              Expanded(child: _datePick('To', d.to, (dt) => setState(() => d.to = dt))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datePick(String label, DateTime? value, ValueChanged<DateTime> onPick) {
    return GestureDetector(
      onTap: () async {
        final first = widget.tripStart ?? DateTime.now();
        final last = widget.tripEnd ?? DateTime.now().add(const Duration(days: 365));
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? first,
          firstDate: first,
          lastDate: last,
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
            child: child!,
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: widget.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: widget.textSecondary, fontSize: 10)),
            const SizedBox(height: 2),
            Text(
              value != null ? DateFormat('dd MMM').format(value) : 'Pick',
              style: TextStyle(
                color: value != null ? widget.textPrimary : widget.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: widget.textSecondary, fontSize: 13),
        filled: true,
        fillColor: widget.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: widget.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: widget.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary)),
      );
}
