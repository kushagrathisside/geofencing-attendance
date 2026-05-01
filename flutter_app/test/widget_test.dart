import 'package:attendance_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home screen shows role choices', (tester) async {
    await tester.pumpWidget(const AttendanceApp());

    expect(find.text('Who are you?'), findsOneWidget);
    expect(find.text('Instructor'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
  });
}
