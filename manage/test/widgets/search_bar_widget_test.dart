import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manage/widgets/search_bar_widget.dart';

void main() {
  group('SearchBarWidget', () {
    testWidgets('displays hint text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              hintText: 'Search animals',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Search animals'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('calls onChanged when text is entered', (WidgetTester tester) async {
      String searchText = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              hintText: 'Search',
              onChanged: (value) => searchText = value,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'test query');
      await tester.pump();

      expect(searchText, equals('test query'));
    });

    testWidgets('shows clear button when text is entered', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              hintText: 'Search',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Initially, clear button should not be visible
      expect(find.byIcon(Icons.clear), findsNothing);

      // Enter text
      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      // Clear button should now be visible
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('clears text when clear button is pressed', (WidgetTester tester) async {
      String searchText = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              hintText: 'Search',
              onChanged: (value) => searchText = value,
            ),
          ),
        ),
      );

      // Enter text
      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();
      expect(searchText, equals('test'));

      // Tap clear button
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(searchText, equals(''));
      expect(find.byIcon(Icons.clear), findsNothing);
    });

    testWidgets('onChanged is called only once when clear button is pressed', (WidgetTester tester) async {
      int onChangedCallCount = 0;
      String lastValue = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              hintText: 'Search',
              onChanged: (value) {
                onChangedCallCount++;
                lastValue = value;
              },
            ),
          ),
        ),
      );

      // Enter text (this will trigger onChanged)
      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();
      
      // Reset counter after initial text entry
      onChangedCallCount = 0;

      // Tap clear button
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      // onChanged should be called exactly once with empty string
      expect(onChangedCallCount, equals(1));
      expect(lastValue, equals(''));
    });

    testWidgets('handles controller replacement after widget rebuilds', (WidgetTester tester) async {
      final controller1 = TextEditingController(text: 'initial');
      final controller2 = TextEditingController(text: 'replaced');
      
      String searchText = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              hintText: 'Search',
              controller: controller1,
              onChanged: (value) => searchText = value,
            ),
          ),
        ),
      );

      // Verify initial controller is used
      expect(find.text('initial'), findsOneWidget);

      // Rebuild with a different controller
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              hintText: 'Search',
              controller: controller2,
              onChanged: (value) => searchText = value,
            ),
          ),
        ),
      );

      // Verify new controller is used
      expect(find.text('replaced'), findsOneWidget);
      
      // Verify the widget still works with the new controller
      await tester.enterText(find.byType(TextField), 'new text');
      await tester.pump();
      expect(searchText, equals('new text'));
    });

    testWidgets('uses provided controller', (WidgetTester tester) async {
      final controller = TextEditingController(text: 'initial text');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              hintText: 'Search',
              controller: controller,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('initial text'), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('calls onClear when clear button is pressed', (WidgetTester tester) async {
      bool clearCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              hintText: 'Search',
              onChanged: (_) {},
              onClear: () => clearCalled = true,
            ),
          ),
        ),
      );

      // Enter text
      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      // Tap clear button
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(clearCalled, isTrue);
    });
  });
}
