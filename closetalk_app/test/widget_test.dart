import 'package:flutter_test/flutter_test.dart';
import 'package:closetalk_app/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const CloseTalkApp());
    await tester.pump();

    expect(find.text('CloseTalk'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
