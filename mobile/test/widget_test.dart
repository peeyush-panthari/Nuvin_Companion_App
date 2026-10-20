import 'package:flutter_test/flutter_test.dart';
import 'package:nuvin_mobile/main.dart';

void main() {
  testWidgets('Nuvin App renders WelcomeIntroScreen carousel initially', (WidgetTester tester) async {
    await tester.pumpWidget(const NuvinApp());
    expect(find.text("A safe space\nfor what you\ncan't\nsay out loud."), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('Tapping Skip navigates from WelcomeIntroScreen to AuthScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const NuvinApp());
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('nuvin'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
