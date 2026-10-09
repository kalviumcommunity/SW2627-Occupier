
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('Occupier opens on the Login screen', (tester) async {
    await tester.pumpWidget(const OccupierApp());

    // Allow the initial frame to render without waiting for Firebase.
    await tester.pump();

    expect(find.text('Login'), findsWidgets);
  });
}
