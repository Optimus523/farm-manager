import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manage/widgets/empty_state_widget.dart';

void main() {
  group('EmptyStateWidget', () {
    testWidgets('displays icon, title, and message', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: Icons.pets,
              title: 'No Animals',
              message: 'Add your first animal to get started',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.pets), findsOneWidget);
      expect(find.text('No Animals'), findsOneWidget);
      expect(find.text('Add your first animal to get started'), findsOneWidget);
    });

    testWidgets('displays action button when provided', (WidgetTester tester) async {
      bool actionPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: Icons.pets,
              title: 'No Animals',
              message: 'Add your first animal to get started',
              actionLabel: 'Add Animal',
              onActionPressed: () => actionPressed = true,
            ),
          ),
        ),
      );

      expect(find.text('Add Animal'), findsOneWidget);
      
      await tester.tap(find.text('Add Animal'));
      await tester.pump();

      expect(actionPressed, isTrue);
    });

    testWidgets('displays custom action widget when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: Icons.pets,
              title: 'No Animals',
              message: 'Add your first animal to get started',
              customAction: Text('Custom Action'),
            ),
          ),
        ),
      );

      expect(find.text('Custom Action'), findsOneWidget);
    });
  });
}
