import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/booking_repository.dart';
import 'package:mobile/models/booking.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late BookingRepository repository;
  late String? authenticatedUserId;
  late DateTime currentTime;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    authenticatedUserId = 'user-001';
    currentTime = DateTime.utc(2026, 11, 1, 12);

    repository = BookingRepository(
      firestore: firestore,
      currentUserId: () => authenticatedUserId,
      clock: () => currentTime,
    );
  });

  Booking createTestBooking({
    required String userId,
    String branchId = 'branch-001',
    String resourceId = 'desk-001',
    BookingResourceType resourceType = BookingResourceType.desk,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return Booking(
      userId: userId,
      branchId: branchId,
      resourceId: resourceId,
      resourceType: resourceType,
      startTime: startTime ?? DateTime.utc(2026, 11, 2, 9),
      endTime: endTime ?? DateTime.utc(2026, 11, 2, 10),
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

      final scheduleId = BookingRepository.reservationScheduleId(
        branchId: 'branch-001',
        resourceType: BookingResourceType.desk,
        resourceId: 'desk-001',
        date: booking.startTime,
      );

      final schedule = await firestore
          .collection('booking_schedules')
          .doc(scheduleId)
          .get();

      expect(schedule.exists, isTrue);
      expect(schedule.data()!['branchId'], 'branch-001');
      expect(schedule.data()!['resourceId'], 'desk-001');

      final reservations = Map<String, dynamic>.from(
        schedule.data()!['reservations'] as Map,
      );

      expect(reservations, contains(bookingId));

      final reservation = Map<String, dynamic>.from(
        reservations[bookingId] as Map,
      );

      expect(reservation['status'], 'confirmed');
    });

    test('returns null when a booking does not exist', () async {
      final result = await repository.getBooking('missing-booking');

      expect(result, isNull);
    });

    test('watches only bookings belonging to the requested user', () async {
      await repository.createBooking(createTestBooking(userId: 'user-001'));

      final otherUserRepository = BookingRepository(
        firestore: firestore,
        currentUserId: () => 'user-002',
      );

      await otherUserRepository.createBooking(
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

    test('rejects overlapping bookings for the same resource', () async {
      await repository.createBooking(createTestBooking(userId: 'user-001'));

      // Use the authenticated user so the authorization check passes
      // and this test exercises the overlap-prevention logic.
      final overlappingBooking = createTestBooking(
        userId: 'user-001',
        startTime: DateTime.utc(2026, 11, 2, 9, 30),
        endTime: DateTime.utc(2026, 11, 2, 10, 30),
      );

      await expectLater(
        repository.createBooking(overlappingBooking),
        throwsA(isA<BookingConflictException>()),
      );

      final savedBookings = await firestore.collection('bookings').get();

      expect(savedBookings.docs, hasLength(1));
    });

    test('allows back-to-back bookings', () async {
      await repository.createBooking(createTestBooking(userId: 'user-001'));

      final nextBooking = createTestBooking(
        userId: 'user-001',
        startTime: DateTime.utc(2026, 11, 2, 10),
        endTime: DateTime.utc(2026, 11, 2, 11),
      );

      await expectLater(repository.createBooking(nextBooking), completes);

      final savedBookings = await firestore.collection('bookings').get();

      expect(savedBookings.docs, hasLength(2));
    });

    test('allows the same time on a different resource', () async {
      await repository.createBooking(createTestBooking(userId: 'user-001'));

      final differentResource = createTestBooking(
        userId: 'user-001',
        resourceId: 'desk-002',
      );

      await expectLater(repository.createBooking(differentResource), completes);

      final savedBookings = await firestore.collection('bookings').get();

      expect(savedBookings.docs, hasLength(2));
    });

    test(
      'cancels an upcoming booking and updates its schedule status',
      () async {
        final bookingId = await repository.createBooking(
          createTestBooking(userId: 'user-001'),
        );

        await repository.cancelBooking(bookingId);

        final savedBooking = await repository.getBooking(bookingId);
        expect(savedBooking, isNotNull);
        expect(savedBooking!.status, BookingStatus.cancelled);

        final scheduleId = BookingRepository.reservationScheduleId(
          branchId: 'branch-001',
          resourceType: BookingResourceType.desk,
          resourceId: 'desk-001',
          date: savedBooking.startTime,
        );
        final schedule = await firestore
            .collection('booking_schedules')
            .doc(scheduleId)
            .get();
        final reservations = Map<String, dynamic>.from(
          schedule.data()!['reservations'] as Map,
        );
        final reservation = Map<String, dynamic>.from(
          reservations[bookingId] as Map,
        );

        expect(reservation['status'], 'cancelled');
        expect(schedule.data()!['lastBookingId'], bookingId);

        // The cancelled reservation must no longer block its former time slot.
        await expectLater(
          repository.createBooking(createTestBooking(userId: 'user-001')),
          completes,
        );
      },
    );

    test('denies cancelling another user booking', () async {
      final otherUserRepository = BookingRepository(
        firestore: firestore,
        currentUserId: () => 'user-002',
        clock: () => currentTime,
      );
      final bookingId = await otherUserRepository.createBooking(
        createTestBooking(userId: 'user-002', resourceId: 'desk-002'),
      );

      await expectLater(
        repository.cancelBooking(bookingId),
        throwsA(isA<StateError>()),
      );

      expect(
        (await repository.getBooking(bookingId))!.status,
        BookingStatus.confirmed,
      );
    });

    test('denies cancelling a booking that has already started', () async {
      final bookingId = await repository.createBooking(
        createTestBooking(
          userId: 'user-001',
          startTime: DateTime.utc(2026, 11, 1, 9),
          endTime: DateTime.utc(2026, 11, 1, 10),
        ),
      );

      await expectLater(
        repository.cancelBooking(bookingId),
        throwsA(isA<StateError>()),
      );

      expect(
        (await repository.getBooking(bookingId))!.status,
        BookingStatus.confirmed,
      );
    });

    test('denies cancelling a booking a second time', () async {
      final bookingId = await repository.createBooking(
        createTestBooking(userId: 'user-001'),
      );

      await repository.cancelBooking(bookingId);
      await expectLater(
        repository.cancelBooking(bookingId),
        throwsA(isA<StateError>()),
      );
    });

    test('denies creating bookings for another user', () async {
      await expectLater(
        repository.createBooking(createTestBooking(userId: 'user-002')),
        throwsA(isA<StateError>()),
      );
    });

    test('denies watching another user bookings', () {
      expect(
        () => repository.watchUserBookings('user-002'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
