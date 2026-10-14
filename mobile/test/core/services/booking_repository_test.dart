import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/booking_repository.dart';
import 'package:mobile/models/booking.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late BookingRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = BookingRepository(firestore: firestore);
  });

  Booking createTestBooking({
    required String userId,
    String resourceId = 'desk-001',
    BookingResourceType resourceType = BookingResourceType.desk,
  }) {
    return Booking(
      userId: userId,
      branchId: 'branch-001',
      resourceId: resourceId,
      resourceType: resourceType,
      startTime: DateTime.utc(2026, 11, 2, 9),
      endTime: DateTime.utc(2026, 11, 2, 10),
      status: BookingStatus.confirmed,
      createdBy: userId,
    );
  }

  group('BookingRepository', () {
    test('creates and retrieves a booking', () async {
      final booking = createTestBooking(userId: 'user-001');

      final bookingId = await repository.createBooking(booking);
      final saved = await repository.getBooking(bookingId);

      expect(saved, isNotNull);
      expect(saved!.id, bookingId);
      expect(saved.userId, 'user-001');
      expect(saved.branchId, 'branch-001');
      expect(saved.resourceId, 'desk-001');
      expect(saved.resourceType, BookingResourceType.desk);
      expect(saved.status, BookingStatus.confirmed);
      expect(
        saved.startTime.millisecondsSinceEpoch,
        booking.startTime.millisecondsSinceEpoch,
      );
      expect(
        saved.endTime.millisecondsSinceEpoch,
        booking.endTime.millisecondsSinceEpoch,
      );
      expect(saved.createdAt, isNotNull);
    });

    test('returns null when a booking does not exist', () async {
      final result = await repository.getBooking('missing-booking');

      expect(result, isNull);
    });

    test('watches only bookings belonging to the requested user', () async {
      await repository.createBooking(createTestBooking(userId: 'user-001'));

      await repository.createBooking(
        createTestBooking(
          userId: 'user-002',
          resourceId: 'room-001',
          resourceType: BookingResourceType.room,
        ),
      );

      final bookings = await repository.watchUserBookings('user-001').first;

      expect(bookings, hasLength(1));
      expect(bookings.first.userId, 'user-001');
      expect(bookings.first.resourceId, 'desk-001');
    });
  });
}
