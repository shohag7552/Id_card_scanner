import 'package:flutter_test/flutter_test.dart';
import 'package:card_scanner/main.dart';
import 'package:card_scanner/pages/home_page.dart';

void main() {
  testWidgets('App boots and renders Home Page Dashboard', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CardScannerApp());

    // Verify that the Dashboard is rendered with the title
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Card Scanner Pro'), findsOneWidget);
    expect(find.text('AI CARD READER'), findsOneWidget);
  });
}
