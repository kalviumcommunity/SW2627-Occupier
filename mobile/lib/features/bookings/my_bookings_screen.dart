import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/booking_repository.dart';
import '../../core/services/occupancy_repository.dart';
import '../../models/booking.dart';
import '../../models/occupancy.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  final OccupancyRepository _occupancyRepository = OccupancyRepository();

  late final Stream<List<Booking>> _bookingsStream;
  late final Stream<List<Occupancy>> _occupanciesStream;

  String? _checkingInBookingId;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      _bookingsStream = _bookingRepository.watchUserBookings(user.uid);
    } else {
      _bookingsStream = Stream.value(const <Booking>[]);
    }

    _occupanciesStream = _occupancyRepository.watchActiveOccupancies();
  }

  bool _hasActiveOccupancy(
    Booking booking,
    List<Occupancy> occupancies,
  ) {
    return occupancies.any(
      (occupancy) =>
          occupancy.bookingId == booking.id &&
          occupancy.status == OccupancyStatus.active,
    );
  }

  bool _canCheckIn(Booking booking, DateTime now) {
    return booking.status == BookingStatus.confirmed &&
        !now.isBefore(booking.startTime) &&
        !now.isAfter(booking.endTime);
  }

  Future<void> _checkIn(Booking booking) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('Please log in to check in.');
      return;
    }

    if (booking.userId != user.uid) {
      _showMessage('You can only check in to your own bookings.');
      return;
    }

    final now = DateTime.now();

    if (!_canCheckIn(booking, now)) {
      _showMessage(
        'Check-in is available only during your confirmed booking time.',
      );
      return;
    }

    if (_checkingInBookingId != null) return;

    setState(() {
      _checkingInBookingId = booking.id;
    });

    try {
      final occupancy = Occupancy(
        occupancyId: '',
        branchId: booking.branchId,
        resourceId: booking.resourceId,
        resourceType: booking.resourceType.name,
        userId: user.uid,
        bookingId: booking.id,
        status: OccupancyStatus.active,
        checkInTime: now,
        checkOutTime: null,
        source: OccupancySource.booking,
        createdAt: now,
      );

      await _occupancyRepository.createOccupancy(occupancy);

      if (!mounted) return;

      _showMessage('Check-in successful!');
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showMessage(error.message ?? 'Unable to check in. Please try again.');
    } catch (error) {
      if (!mounted) return;

      final message = error.toString().replaceFirst('Bad state: ', '');
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() {
          _checkingInBookingId = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');

    return '$day/$month/${local.year} · $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Bookings')),
        body: const Center(
          child: Text('Please log in to view your bookings.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: StreamBuilder<List<Booking>>(
        stream: _bookingsStream,
        builder: (context, bookingSnapshot) {
          if (bookingSnapshot.hasError) {
            return const Center(
              child: Text('Unable to load your bookings.'),
            );
          }

          if (bookingSnapshot.connectionState == ConnectionState.waiting &&
              !bookingSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final bookings = [...?bookingSnapshot.data]
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

          if (bookings.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You have no bookings yet. Create a booking to see it here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return StreamBuilder<List<Occupancy>>(
            stream: _occupanciesStream,
            builder: (context, occupancySnapshot) {
              if (occupancySnapshot.hasError) {
                return const Center(
                  child: Text('Unable to load current check-in status.'),
                );
              }

              if (occupancySnapshot.connectionState ==
                      ConnectionState.waiting &&
                  !occupancySnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final occupancies =
                  occupancySnapshot.data ?? const <Occupancy>[];
              final now = DateTime.now();

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: bookings.length,
                itemBuilder: (context, index) {
                  final booking = bookings[index];
                  final hasCheckedIn =
                      _hasActiveOccupancy(booking, occupancies);
                  final eligible = _canCheckIn(booking, now);
                  final isCheckingIn =
                      _checkingInBookingId == booking.id;

                  String statusText = booking.status.name.toUpperCase();

                  if (hasCheckedIn) {
                    statusText = 'CHECKED IN';
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking.resourceType == BookingResourceType.desk
                                ? 'Desk Booking'
                                : 'Meeting Room Booking',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text('Branch ID: ${booking.branchId}'),
                          Text('Resource ID: ${booking.resourceId}'),
                          Text(
                            'Start: ${_formatDateTime(booking.startTime)}',
                          ),
                          Text(
                            'End: ${_formatDateTime(booking.endTime)}',
                          ),
                          const SizedBox(height: 8),
                          Text('Status: $statusText'),
                          const SizedBox(height: 12),
                          if (hasCheckedIn)
                            const Text(
                              'You are currently checked in to this booking.',
                            )
                          else if (booking.status != BookingStatus.confirmed)
                            const Text(
                              'Only confirmed bookings can be checked in.',
                            )
                          else if (!eligible)
                            const Text(
                              'Check-in is available during the booking time.',
                            ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: eligible &&
                                      !hasCheckedIn &&
                                      !isCheckingIn
                                  ? () => _checkIn(booking)
                                  : null,
                              icon: isCheckingIn
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login),
                              label: Text(
                                isCheckingIn ? 'Checking in...' : 'Check in',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
