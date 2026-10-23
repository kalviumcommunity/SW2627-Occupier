import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'permission_service.dart';
import '../../models/booking.dart';

/// Thrown when a resource is already booked for an overlapping time.
class BookingConflictException implements Exception {
  const BookingConflictException([
    this.message =
        'This resource is already booked for an overlapping time. '
        'Please choose another slot.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when booking details fail validation before persistence.
class BookingValidationException implements Exception {
  const BookingValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BookingRepository {
  BookingRepository({
    FirebaseFirestore? firestore,
    String? Function()? currentUserId,
    DateTime Function()? clock,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _currentUserId =
           currentUserId ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _clock = clock ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final String? Function() _currentUserId;
  final DateTime Function() _clock;

  static const PermissionService _permissions = PermissionService();

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _firestore.collection('bookings');

  CollectionReference<Map<String, dynamic>> get _schedules =>
      _firestore.collection('booking_schedules');

  static const Set<String> _blockingStatuses = {'pending', 'confirmed'};

  /// Produces a predictable schedule document ID using the IST calendar date.
  ///
  /// Example:
  /// jaipur-central__desk__desk-001__2026-11-02
  static String reservationScheduleId({
    required String branchId,
    required BookingResourceType resourceType,
    required String resourceId,
    required DateTime date,
  }) {
    final istDate = date.toUtc().add(const Duration(hours: 5, minutes: 30));

    final dateKey =
        '${istDate.year.toString().padLeft(4, '0')}-'
        '${istDate.month.toString().padLeft(2, '0')}-'
        '${istDate.day.toString().padLeft(2, '0')}';

    return '${branchId}__${resourceType.name}__'
        '${resourceId}__$dateKey';
  }

  /// Creates a booking and its reservation entry atomically.
  ///
  /// Returns the generated booking document ID.
  Future<String> createBooking(Booking booking) async {
    // Preserve main's authorization checks.
    final currentUserId = _currentUserId();

    if (!_permissions.canAccessOwnProfile(
          authenticatedUid: currentUserId,
          profileUid: booking.userId,
        ) ||
        booking.createdBy != currentUserId) {
      throw StateError('Bookings can only be created for the signed-in user.');
    }

    if (booking.branchId.trim().isEmpty) {
      throw const BookingValidationException(
        'Choose a branch before creating a booking.',
      );
    }
    if (booking.resourceId.trim().isEmpty) {
      throw const BookingValidationException(
        'Choose a desk or meeting room before creating a booking.',
      );
    }

    final start = booking.startTime;
    final end = booking.endTime;

    if (!end.isAfter(start)) {
      throw const BookingValidationException(
        'End time must be later than start time.',
      );
    }

    // Each booking must start and end on the same IST calendar date.
    if (_dateKey(start) != _dateKey(end)) {
      throw const BookingValidationException(
        'A booking must start and end on the same calendar date.',
      );
    }

    if (!start.isAfter(_clock())) {
      throw const BookingValidationException(
        'Choose a start time in the future.',
      );
    }

    final scheduleId = reservationScheduleId(
      branchId: booking.branchId,
      resourceType: booking.resourceType,
      resourceId: booking.resourceId,
      date: start,
    );

    final scheduleRef = _schedules.doc(scheduleId);
    final bookingRef = _bookings.doc();

    await _firestore.runTransaction<void>((transaction) async {
      // Read the shared schedule before making any writes.
      final scheduleSnapshot = await transaction.get(scheduleRef);

      final existingReservations = <String, Map<String, dynamic>>{};

      if (scheduleSnapshot.exists) {
        final scheduleData = scheduleSnapshot.data();

        // Do not reuse a schedule belonging to another resource or date.
        if (scheduleData == null ||
            scheduleData['branchId'] != booking.branchId ||
            scheduleData['resourceId'] != booking.resourceId ||
            scheduleData['resourceType'] != booking.resourceType.name ||
            scheduleData['dateKey'] != _dateKey(start)) {
          throw StateError(
            'The reservation schedule does not match this booking. '
            'Please contact support.',
          );
        }

        final rawReservations = scheduleData['reservations'];

        if (rawReservations is! Map) {
          throw StateError(
            'The reservation schedule is invalid. '
            'Please contact support.',
          );
        }

        for (final entry in rawReservations.entries) {
          if (entry.key is! String || entry.value is! Map) {
            throw StateError('The reservation schedule contains invalid data.');
          }

          final bookingId = entry.key as String;
          final reservation = Map<String, dynamic>.from(entry.value as Map);

          final status = reservation['status'] as String?;

          // Cancelled and completed bookings do not block new reservations.
          if (status == 'cancelled' || status == 'completed') {
            existingReservations[bookingId] = reservation;
            continue;
          }

          if (!_blockingStatuses.contains(status)) {
            throw StateError(
              'The reservation schedule contains an unknown status.',
            );
          }

          final existingStart = reservation['startTime'];
          final existingEnd = reservation['endTime'];

          if (existingStart is! Timestamp || existingEnd is! Timestamp) {
            throw StateError(
              'The reservation schedule contains invalid time data.',
            );
          }

          if (_overlaps(
            start,
            end,
            existingStart.toDate(),
            existingEnd.toDate(),
          )) {
            throw const BookingConflictException();
          }

          existingReservations[bookingId] = reservation;
        }
      }

      final newReservation = <String, dynamic>{
        'bookingId': bookingRef.id,
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
        'status': booking.status.name,
      };

      final bookingData = booking.toFirestore();
      bookingData['createdAt'] = FieldValue.serverTimestamp();

      // Link the booking to its reservation schedule.
      bookingData['reservationScheduleId'] = scheduleId;

      final updatedReservations = <String, Map<String, dynamic>>{
        ...existingReservations,
        bookingRef.id: newReservation,
      };

      // Both writes commit atomically. Concurrent transactions that modify
      // the same schedule are retried by Firestore.
      transaction.set(bookingRef, bookingData);

      transaction.set(scheduleRef, {
        'branchId': booking.branchId,
        'resourceId': booking.resourceId,
        'resourceType': booking.resourceType.name,
        'dateKey': _dateKey(start),
        'reservations': updatedReservations,
        'lastBookingId': bookingRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    return bookingRef.id;
  }

  /// Cancels an upcoming booking owned by the currently signed-in user.
  ///
  /// The booking and its reservation schedule are updated atomically so a
  /// cancelled reservation no longer blocks that time slot.
  Future<void> cancelBooking(String bookingId) async {
    final userId = _currentUserId();
    if (userId == null) {
      throw StateError('Please log in to cancel bookings.');
    }
    if (bookingId.trim().isEmpty) {
      throw ArgumentError.value(bookingId, 'bookingId', 'Must not be empty.');
    }

    final bookingRef = _bookings.doc(bookingId);

    await _firestore.runTransaction<void>((transaction) async {
      final bookingSnapshot = await transaction.get(bookingRef);
      if (!bookingSnapshot.exists) {
        throw StateError('This booking no longer exists.');
      }

      final bookingData = bookingSnapshot.data();
      if (bookingData == null) {
        throw StateError('The booking data is invalid.');
      }
      if (bookingData['userId'] != userId) {
        throw StateError('You can only cancel your own bookings.');
      }

      final status = bookingData['status'] as String?;
      if (status != BookingStatus.pending.name &&
          status != BookingStatus.confirmed.name) {
        throw StateError(
          'Only pending or confirmed bookings can be cancelled.',
        );
      }

      final rawStart = bookingData['startTime'];
      final rawEnd = bookingData['endTime'];
      if (rawStart is! Timestamp || rawEnd is! Timestamp) {
        throw StateError('The booking contains invalid time data.');
      }

      final startTime = rawStart.toDate();
      final endTime = rawEnd.toDate();
      if (!startTime.isAfter(_clock())) {
        throw StateError('A booking cannot be cancelled after it has started.');
      }

      final branchId = bookingData['branchId'];
      final resourceId = bookingData['resourceId'];
      final resourceTypeValue = bookingData['resourceType'];
      if (branchId is! String ||
          resourceId is! String ||
          resourceTypeValue is! String) {
        throw StateError('The booking details are invalid.');
      }

      final resourceType = BookingResourceType.values.where(
        (value) => value.name == resourceTypeValue,
      );
      if (resourceType.isEmpty) {
        throw StateError('The booking resource type is invalid.');
      }

      final expectedScheduleId = reservationScheduleId(
        branchId: branchId,
        resourceType: resourceType.first,
        resourceId: resourceId,
        date: startTime,
      );
      final storedScheduleId = bookingData['reservationScheduleId'];
      if (storedScheduleId != null && storedScheduleId != expectedScheduleId) {
        throw StateError('The booking reservation schedule is invalid.');
      }

      // Read the schedule before writing either document; Firestore
      // transactions require all reads to happen before writes.
      final scheduleRef = _schedules.doc(expectedScheduleId);
      final scheduleSnapshot = await transaction.get(scheduleRef);
      if (!scheduleSnapshot.exists) {
        throw StateError(
          'The reservation schedule was not found. Please contact support.',
        );
      }

      final scheduleData = scheduleSnapshot.data();
      if (scheduleData == null ||
          scheduleData['branchId'] != branchId ||
          scheduleData['resourceId'] != resourceId ||
          scheduleData['resourceType'] != resourceTypeValue ||
          scheduleData['dateKey'] != _dateKey(startTime)) {
        throw StateError(
          'The reservation schedule does not match this booking. '
          'Please contact support.',
        );
      }

      final rawReservations = scheduleData['reservations'];
      if (rawReservations is! Map) {
        throw StateError('The reservation schedule contains invalid data.');
      }
      final rawReservation = rawReservations[bookingId];
      if (rawReservation is! Map) {
        throw StateError(
          'The booking is missing from its reservation schedule.',
        );
      }

      final reservation = Map<String, dynamic>.from(rawReservation);
      if (reservation['bookingId'] != bookingId ||
          reservation['status'] != status ||
          reservation['startTime'] is! Timestamp ||
          reservation['endTime'] is! Timestamp ||
          !(reservation['startTime'] as Timestamp).toDate().isAtSameMomentAs(
            startTime,
          ) ||
          !(reservation['endTime'] as Timestamp).toDate().isAtSameMomentAs(
            endTime,
          )) {
        throw StateError(
          'The reservation schedule does not match this booking. '
          'Please contact support.',
        );
      }

      reservation['status'] = BookingStatus.cancelled.name;
      final updatedReservations = Map<String, dynamic>.from(rawReservations);
      updatedReservations[bookingId] = reservation;

      transaction.update(bookingRef, {'status': BookingStatus.cancelled.name});
      transaction.update(scheduleRef, {
        'reservations': updatedReservations,
        // Identifies the reservation changed by this atomic operation.
        'lastBookingId': bookingId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  bool _overlaps(
    DateTime newStart,
    DateTime newEnd,
    DateTime existingStart,
    DateTime existingEnd,
  ) {
    // Treat reservations as half-open intervals [start, end).
    // A booking ending at 12:00 does not conflict with one starting
    // at exactly 12:00.
    return newStart.isBefore(existingEnd) && newEnd.isAfter(existingStart);
  }

  String _dateKey(DateTime date) {
    final istDate = date.toUtc().add(const Duration(hours: 5, minutes: 30));

    return '${istDate.year.toString().padLeft(4, '0')}-'
        '${istDate.month.toString().padLeft(2, '0')}-'
        '${istDate.day.toString().padLeft(2, '0')}';
  }

  /// Retrieves one booking by its Firestore document ID.
  Future<Booking?> getBooking(String bookingId) async {
    final document = await _bookings.doc(bookingId).get();

    if (!document.exists) {
      return null;
    }

    return Booking.fromFirestore(document);
  }

  /// Streams bookings belonging to one user.
  Stream<List<Booking>> watchUserBookings(String userId) {
    if (!_permissions.canAccessOwnProfile(
      authenticatedUid: _currentUserId(),
      profileUid: userId,
    )) {
      throw StateError('You can access only your own bookings.');
    }

    return _bookings
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Booking.fromFirestore).toList());
  }
}
