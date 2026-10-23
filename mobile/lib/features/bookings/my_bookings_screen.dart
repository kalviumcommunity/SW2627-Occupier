import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_routes.dart';
import '../../core/services/booking_repository.dart';
import '../../core/services/occupancy_repository.dart';
import '../../models/booking.dart';
import '../../models/occupancy.dart';

enum _BookingFilter { upcoming, past, all }

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({
    super.key,
    this.bookingRepository,
    this.occupancyRepository,
    this.currentUserId,
    this.clock,
  });

  final BookingRepository? bookingRepository;
  final OccupancyRepository? occupancyRepository;
  final String? Function()? currentUserId;
  final DateTime Function()? clock;

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  late final BookingRepository _bookingRepository =
      widget.bookingRepository ??
      BookingRepository(currentUserId: _resolveUserId);
  late final OccupancyRepository _occupancyRepository =
      widget.occupancyRepository ?? OccupancyRepository();

  late final String? _userId;
  late final Stream<List<Booking>> _bookingsStream;
  late final Stream<List<Occupancy>> _occupanciesStream;

  _BookingFilter _filter = _BookingFilter.upcoming;
  String? _checkingInBookingId;
  String? _cancellingBookingId;

  String? _resolveUserId() =>
      widget.currentUserId?.call() ?? FirebaseAuth.instance.currentUser?.uid;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();

    // Resolve the user once so bookings and occupancies use the same owner.
    final userId = _resolveUserId();
    _userId = userId;

    if (userId == null) {
      _bookingsStream = Stream.value(const <Booking>[]);
      _occupanciesStream = Stream.value(const <Occupancy>[]);
    } else {
      _bookingsStream = _bookingRepository.watchUserBookings(userId);
      _occupanciesStream = _occupancyRepository.watchActiveOccupancies(
        userId: userId,
      );
    }
  }

  bool _hasActiveOccupancy(Booking booking, List<Occupancy> occupancies) {
    return occupancies.any(
      (occupancy) =>
          occupancy.bookingId == booking.id &&
          occupancy.status == OccupancyStatus.active,
    );
  }

  bool _canCheckIn(Booking booking, DateTime now) {
    return booking.status == BookingStatus.confirmed &&
        !now.isBefore(booking.startTime) &&
        now.isBefore(booking.endTime);
  }

  bool _canCancel(Booking booking, DateTime now) {
    return (booking.status == BookingStatus.pending ||
            booking.status == BookingStatus.confirmed) &&
        booking.startTime.isAfter(now);
  }

  List<Booking> _visibleBookings(List<Booking> bookings, DateTime now) {
    final filtered = bookings.where((booking) {
      final isUpcoming = booking.endTime.isAfter(now);
      return switch (_filter) {
        _BookingFilter.upcoming => isUpcoming,
        _BookingFilter.past => !isUpcoming,
        _BookingFilter.all => true,
      };
    }).toList();

    filtered.sort((a, b) {
      final aUpcoming = a.endTime.isAfter(now);
      final bUpcoming = b.endTime.isAfter(now);

      if (_filter == _BookingFilter.all && aUpcoming != bUpcoming) {
        return aUpcoming ? -1 : 1;
      }

      final order = a.startTime.compareTo(b.startTime);
      return _filter == _BookingFilter.past ||
              (_filter == _BookingFilter.all && !aUpcoming)
          ? -order
          : order;
    });

    return filtered;
  }

  Future<void> _checkIn(Booking booking) async {
    final userId = _userId;

    if (userId == null) {
      _showMessage('Please log in to check in.');
      return;
    }

    if (booking.userId != userId) {
      _showMessage('You can only check in to your own bookings.');
      return;
    }

    final now = _now;
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
        userId: userId,
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

  Future<void> _requestCancellation(Booking booking) async {
    final userId = _userId;
    if (userId == null) {
      _showMessage('Please log in to cancel bookings.');
      return;
    }
    if (booking.userId != userId) {
      _showMessage('You can only cancel your own bookings.');
      return;
    }
    if (!_canCancel(booking, _now)) {
      _showMessage(
        'Only upcoming pending or confirmed bookings can be cancelled.',
      );
      return;
    }
    if (_cancellingBookingId != null) return;

    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text(
          'This will cancel your reservation and release the reserved time slot. '
          'You cannot undo this action.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );

    if (!mounted || shouldCancel != true) return;

    // Re-check the cancellation window after the user confirms the dialog.
    if (!_canCancel(booking, _now)) {
      _showMessage('This booking can no longer be cancelled.');
      return;
    }

    setState(() => _cancellingBookingId = booking.id);
    try {
      await _bookingRepository.cancelBooking(booking.id);
      if (!mounted) return;
      _showMessage('Booking cancelled successfully.');
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.message ?? 'Unable to cancel booking. Please try again.',
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() => _cancellingBookingId = null);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  DateTime _asIst(DateTime dateTime) =>
      dateTime.toUtc().add(const Duration(hours: 5, minutes: 30));

  String _formatDateTime(DateTime dateTime) {
    final ist = _asIst(dateTime);
    final hour = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
    final minute = ist.minute.toString().padLeft(2, '0');
    final period = ist.hour >= 12 ? 'PM' : 'AM';
    final day = ist.day.toString().padLeft(2, '0');
    final month = ist.month.toString().padLeft(2, '0');

    return '$day/$month/${ist.year} · $hour:$minute $period IST';
  }

  String _filterLabel(_BookingFilter filter) => switch (filter) {
    _BookingFilter.upcoming => 'Upcoming',
    _BookingFilter.past => 'Past',
    _BookingFilter.all => 'All',
  };

  String _statusLabel(Booking booking, bool hasCheckedIn) {
    if (hasCheckedIn) return 'Checked in';
    return switch (booking.status) {
      BookingStatus.pending => 'Pending',
      BookingStatus.confirmed => 'Confirmed',
      BookingStatus.cancelled => 'Cancelled',
      BookingStatus.completed => 'Completed',
    };
  }

  Color _statusColor(BuildContext context, Booking booking, bool hasCheckedIn) {
    final colors = Theme.of(context).colorScheme;
    if (hasCheckedIn) return colors.primary;

    return switch (booking.status) {
      BookingStatus.pending => colors.tertiary,
      BookingStatus.confirmed => colors.primary,
      BookingStatus.cancelled => colors.error,
      BookingStatus.completed => colors.secondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Bookings')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Please log in to view your bookings.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: StreamBuilder<List<Booking>>(
        stream: _bookingsStream,
        builder: (context, bookingSnapshot) {
          if (bookingSnapshot.hasError) {
            return _buildLoadError(
              'Unable to load your bookings. Check your connection and try again.',
            );
          }

          if (bookingSnapshot.connectionState == ConnectionState.waiting &&
              !bookingSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final bookings = bookingSnapshot.data ?? const <Booking>[];

          return StreamBuilder<List<Occupancy>>(
            stream: _occupanciesStream,
            builder: (context, occupancySnapshot) {
              final occupancyAvailable =
                  occupancySnapshot.hasData && !occupancySnapshot.hasError;
              final occupancies = occupancySnapshot.data ?? const <Occupancy>[];
              final now = _now;
              final visibleBookings = _visibleBookings(bookings, now);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.event_note_outlined, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your reservations',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${bookings.length} booking${bookings.length == 1 ? '' : 's'} total',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: _BookingFilter.values.map((filter) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_filterLabel(filter)),
                            selected: _filter == filter,
                            onSelected: (_) {
                              setState(() => _filter = filter);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (occupancySnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !occupancySnapshot.hasData)
                    const LinearProgressIndicator(minHeight: 2),
                  if (occupancySnapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        'Check-in status is unavailable. Your booking details are still shown.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: visibleBookings.isEmpty
                        ? _buildEmptyState(bookings.isEmpty)
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: visibleBookings.length,
                            itemBuilder: (context, index) {
                              final booking = visibleBookings[index];
                              final hasCheckedIn = _hasActiveOccupancy(
                                booking,
                                occupancies,
                              );

                              return _buildBookingCard(
                                context,
                                booking,
                                now: now,
                                hasCheckedIn: hasCheckedIn,
                                occupancyAvailable: occupancyAvailable,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLoadError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool hasNoBookings) {
    final title = hasNoBookings
        ? 'No bookings yet'
        : switch (_filter) {
            _BookingFilter.upcoming => 'No upcoming bookings',
            _BookingFilter.past => 'No past bookings',
            _BookingFilter.all => 'No bookings to show',
          };
    final description = hasNoBookings
        ? 'Book a desk or meeting room and your reservations will appear here.'
        : 'Try another filter to see your other reservations.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasNoBookings ? Icons.event_available_outlined : Icons.event_busy,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
            if (hasNoBookings) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.bookings),
                icon: const Icon(Icons.add),
                label: const Text('Book a resource'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(
    BuildContext context,
    Booking booking, {
    required DateTime now,
    required bool hasCheckedIn,
    required bool occupancyAvailable,
  }) {
    final statusText = _statusLabel(booking, hasCheckedIn);
    final statusColor = _statusColor(context, booking, hasCheckedIn);
    final canCheckIn = _canCheckIn(booking, now);
    final isCheckingIn = _checkingInBookingId == booking.id;
    final canCancel = _canCancel(booking, now) && !hasCheckedIn;
    final isCancelling = _cancellingBookingId == booking.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Icon(
                    booking.resourceType == BookingResourceType.desk
                        ? Icons.event_seat
                        : Icons.meeting_room_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.resourceType == BookingResourceType.desk
                            ? 'Desk booking'
                            : 'Meeting room booking',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusText,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow(Icons.location_on_outlined, 'Branch', booking.branchId),
            const SizedBox(height: 8),
            _detailRow(
              booking.resourceType == BookingResourceType.desk
                  ? Icons.event_seat_outlined
                  : Icons.meeting_room_outlined,
              'Resource',
              booking.resourceId,
            ),
            const SizedBox(height: 8),
            _detailRow(
              Icons.schedule_outlined,
              'Starts',
              _formatDateTime(booking.startTime),
            ),
            const SizedBox(height: 8),
            _detailRow(
              Icons.schedule,
              'Ends',
              _formatDateTime(booking.endTime),
            ),
            if (hasCheckedIn) ...[
              const SizedBox(height: 12),
              const Text('You are currently checked in to this booking.'),
            ] else if (canCheckIn && !occupancyAvailable) ...[
              const SizedBox(height: 12),
              const Text('Loading your check-in status...'),
            ] else if (booking.status == BookingStatus.confirmed &&
                !canCheckIn) ...[
              const SizedBox(height: 12),
              Text(
                booking.startTime.isAfter(now)
                    ? 'Check-in opens during your booking time.'
                    : 'This booking time has ended.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (canCheckIn && !hasCheckedIn) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: occupancyAvailable && !isCheckingIn
                      ? () => _checkIn(booking)
                      : null,
                  icon: isCheckingIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(isCheckingIn ? 'Checking in...' : 'Check in'),
                ),
              ),
            ],
            if (canCancel) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isCancelling || _cancellingBookingId != null
                      ? null
                      : () => _requestCancellation(booking),
                  icon: isCancelling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.event_busy_outlined),
                  label: Text(
                    isCancelling ? 'Cancelling...' : 'Cancel booking',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}
