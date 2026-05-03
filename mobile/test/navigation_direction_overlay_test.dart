import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/providers/navigation_provider.dart';
import 'package:saferoute/widgets/navigation_direction_overlay.dart';

void main() {
  testWidgets('NavigationDirectionOverlay renders leg data', (tester) async {
    const leg = NavigationLeg(
      direction: 'E',
      maneuver: 'Keep right at fork',
      remainingDistanceMeters: 120,
      eta: Duration(minutes: 4),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: NavigationDirectionOverlay(leg: leg),
          ),
        ),
      ),
    );

    expect(find.text('Keep right at fork'), findsOneWidget);
    expect(find.text('120 m  •  ETA 4 min'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
  });
}
