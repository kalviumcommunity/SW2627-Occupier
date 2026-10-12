import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('Occupier opens on the Login screen', (tester) async {
    await tester.pumpWidget(const OccupierApp());
    await tester.pump();

    expect(find.text('Welcome to Occupier'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}