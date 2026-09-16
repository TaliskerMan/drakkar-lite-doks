import 'package:drakkar_web/main.dart';
import 'package:drakkar_web/src/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the sign-in form and can switch to sign-up', (tester) async {
    await tester.pumpWidget(DrakkarApp(state: AppState()));

    expect(find.text('Sign in to your organization'), findsOneWidget);
    expect(find.text('Organization'), findsNothing);

    await tester.tap(find.text('New here? Create an organization'));
    await tester.pumpAndSettle();

    expect(find.text('Create your organization'), findsOneWidget);
    expect(find.text('Organization'), findsOneWidget);
  });
}
