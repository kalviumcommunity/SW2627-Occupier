import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'permission_service.dart';
import '../../models/booking.dart';

class BookingRepository {
  BookingRepository({
    FirebaseFirestore? firestore,
    String? Function()? currentUserId,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _currentUserId =
           currentUserId ?? (() => FirebaseAuth.instance.currentUser?.uid);

  final FirebaseFirestore _firestore;
  final String? Function() _currentUserId;
  static const PermissionService _permissions = PermissionService();

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _firestore.collection('bookings');

  /// Creates a booking and returns its generated Firestore document ID.
  Future<String> createBooking(Booking booking) async {
    final currentUserId = _currentUserId();
    if (!_permissions.canAccessOwnProfile(
          authenticatedUid: currentUserId,
          profileUid: booking.userId,
        ) ||
        booking.createdBy != currentUserId) {
      throw StateError('Bookings can only be created for the signed-in user.');
    }

    final document = _bookings.doc();

    final data = booking.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();

    await document.set(data);

    return document.id;
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
