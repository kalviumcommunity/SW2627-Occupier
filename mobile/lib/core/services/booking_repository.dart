import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/booking.dart';

class BookingRepository {
  BookingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _firestore.collection('bookings');

  /// Creates a booking and returns its generated Firestore document ID.
  Future<String> createBooking(Booking booking) async {
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
    return _bookings
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Booking.fromFirestore).toList());
  }
}
