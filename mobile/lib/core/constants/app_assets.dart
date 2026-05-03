/// Type-Safe Asset Constants for SafeRoute
class AppAssets {
  static const animations = _AppAnimations();
  static const data = _AppData();
}

class _AppAnimations {
  const _AppAnimations();
  final String safetyOrb = 'assets/animations/safety_orb.json';
  final String sosPulse = 'assets/animations/sos_pulse.json';
}

class _AppData {
  const _AppData();
  final String trailGraph = 'assets/trail_graph.json';
}
