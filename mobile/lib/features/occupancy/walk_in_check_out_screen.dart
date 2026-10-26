import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_routes.dart';
import '../../core/services/occupancy_repository.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/resource_repository.dart';
import '../../core/services/user_repository.dart';
import '../../models/branch.dart';
import '../../models/desk.dart';
import '../../models/meeting_room.dart';
import '../../models/occupancy.dart';
import '../../models/user.dart';

class WalkInCheckOutScreen extends StatefulWidget {
  const WalkInCheckOutScreen({
    super.key,
    this.resourceRepository,
    this.occupancyRepository,
    this.userRepository,
    this.currentUserId,
  });

  final ResourceRepository? resourceRepository;
  final OccupancyRepository? occupancyRepository;
  final UserRepository? userRepository;
  final String? Function()? currentUserId;

  @override
  State<WalkInCheckOutScreen> createState() => _WalkInCheckOutScreenState();
}

class _WalkInCheckOutScreenState extends State<WalkInCheckOutScreen> {
  late final String? _userId;
  late final UserRepository _userRepository;
  late final ResourceRepository _resourceRepository;
  late final OccupancyRepository _occupancyRepository;
  late final Future<OccupierUser?> _profileFuture;
  late final Stream<List<Branch>> _branchesStream;
  final Set<String> _checkingOutIds = {};
  final Set<String> _checkedOutIds = {};

  @override
  void initState() {
    super.initState();
    _userId =
        widget.currentUserId?.call() ?? FirebaseAuth.instance.currentUser?.uid;
    _userRepository =
        widget.userRepository ?? UserRepository(currentUserId: () => _userId);
    _resourceRepository = widget.resourceRepository ?? ResourceRepository();
    _occupancyRepository = widget.occupancyRepository ?? OccupancyRepository();
    _profileFuture = _userId == null
        ? Future<OccupierUser?>.value(null)
        : _userRepository.getUser(_userId);
    _branchesStream = _resourceRepository.watchBranches();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OccupierUser?>(
      future: _profileFuture,
      builder: (context, profileSnapshot) {
        if (profileSnapshot.hasError) {
          return _messageScreen('Unable to load your access profile.');
        }
        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return _loadingScreen();
        }

        final profile = profileSnapshot.data;
        if (profile == null) {
          return _messageScreen('Your access profile is unavailable.');
        }
        if (!const PermissionService().canManageOccupancy(profile.role)) {
          return _messageScreen(
            'Walk-in check-out is available to authorized staff only.',
          );
        }

        return _buildBranchList(profile);
      },
    );
  }

  Widget _loadingScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Walk-in check-out')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _messageScreen(String message) {
    return Scaffold(
      appBar: AppBar(title: const Text('Walk-in check-out')),
      body: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }

  Widget _buildBranchList(OccupierUser profile) {
    return StreamBuilder<List<Branch>>(
      stream: _branchesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _messageScreen('Unable to load branches. Please try again.');
        }
        if (!snapshot.hasData) {
          return _loadingScreen();
        }

        final branches = snapshot.data!
            .where((branch) => branch.status == BranchStatus.active)
            .where(
              (branch) =>
                  profile.role == UserRole.admin ||
                  branch.managerUid == _userId ||
                  branch.staffUids.contains(_userId),
            )
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Walk-in check-out'),
            leading: IconButton(
              tooltip: 'Back to dashboard',
              icon: const Icon(Icons.arrow_back),
              onPressed: () =>
                  Navigator.of(context)
                      .pushReplacementNamed(AppRoutes.dashboard),
            ),
          ),
          body: branches.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No active branches are assigned to your account.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Active walk-ins',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    for (final branch in branches)
                      _buildBranchOccupancies(branch),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildBranchOccupancies(Branch branch) {
    return StreamBuilder<List<Occupancy>>(
      stream: _occupancyRepository.watchActiveOccupancies(branchId: branch.id),
      builder: (context, occupancySnapshot) {
        if (occupancySnapshot.hasError) {
          return Card(
            child: ListTile(
              title: Text(branch.name),
              subtitle: const Text('Unable to load active occupancies.'),
            ),
          );
        }
        if (!occupancySnapshot.hasData) {
          return Card(
            child: ListTile(
              title: Text(branch.name),
              subtitle: const LinearProgressIndicator(),
            ),
          );
        }

        final occupancies = occupancySnapshot.data!
            .where((occupancy) => occupancy.source == OccupancySource.walkIn)
            .where(
              (occupancy) => !_checkedOutIds.contains(occupancy.occupancyId),
            )
            .toList();

        return StreamBuilder<List<Desk>>(
          stream: _resourceRepository.watchDesks(branch.id),
          builder: (context, deskSnapshot) {
            if (deskSnapshot.hasError) {
              return Card(
                child: ListTile(
                  title: Text(branch.name),
                  subtitle: const Text('Unable to load branch resources.'),
                ),
              );
            }

            return StreamBuilder<List<MeetingRoom>>(
              stream: _resourceRepository.watchMeetingRooms(branch.id),
              builder: (context, roomSnapshot) {
                if (roomSnapshot.hasError) {
                  return Card(
                    child: ListTile(
                      title: Text(branch.name),
                      subtitle: const Text('Unable to load branch resources.'),
                    ),
                  );
                }

                final resourceDescriptions = <String, String>{
                  if (deskSnapshot.hasData)
                    for (final desk in deskSnapshot.data!)
                      'desk:${desk.id}':
                          'Desk · ${desk.name} · Floor ${desk.floor}',
                  if (roomSnapshot.hasData)
                    for (final room in roomSnapshot.data!)
                      'room:${room.id}':
                          'Meeting room · ${room.name} · Capacity ${room.capacity}',
                };

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          branch.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (branch.city.isNotEmpty) Text(branch.city),
                        const Divider(height: 24),
                        if (!deskSnapshot.hasData || !roomSnapshot.hasData)
                          const LinearProgressIndicator()
                        else if (occupancies.isEmpty)
                          const Text('No active walk-ins at this branch.')
                        else
                          for (final occupancy in occupancies)
                            _buildOccupancyTile(
                              occupancy,
                              resourceDescriptions['${occupancy.resourceType}:${occupancy.resourceId}'] ??
                                  '${occupancy.resourceType == 'room' ? 'Meeting room' : 'Desk'} · ${occupancy.resourceId}',
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
    );
  }

  Widget _buildOccupancyTile(Occupancy occupancy, String resourceDescription) {
    final isSubmitting = _checkingOutIds.contains(occupancy.occupancyId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            occupancy.customerName ?? 'Walk-in customer',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (occupancy.customerPhone?.isNotEmpty == true)
            Text('Contact: ${occupancy.customerPhone}'),
          Text('Resource: $resourceDescription'),
          Text('Checked in: ${_formatCheckInTime(occupancy.checkInTime)}'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              key: ValueKey('walk-in-checkout-${occupancy.occupancyId}'),
              onPressed: isSubmitting
                  ? null
                  : () => _confirmCheckOut(occupancy),
              icon: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
              label: Text(isSubmitting ? 'Checking out...' : 'Check out'),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }

  Future<void> _confirmCheckOut(Occupancy occupancy) async {
    if (_checkingOutIds.contains(occupancy.occupancyId) ||
        _checkedOutIds.contains(occupancy.occupancyId)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm check-out'),
        content: Text(
          'Check out ${occupancy.customerName ?? 'this walk-in customer'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('walk-in-checkout-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Check out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (_checkingOutIds.contains(occupancy.occupancyId)) return;

    setState(() => _checkingOutIds.add(occupancy.occupancyId));
    try {
      await _occupancyRepository.checkOut(occupancy.occupancyId);
      if (!mounted) return;
      setState(() {
        _checkingOutIds.remove(occupancy.occupancyId);
        _checkedOutIds.add(occupancy.occupancyId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Walk-in checked out successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _checkingOutIds.remove(occupancy.occupancyId));
      final message = error is StateError
          ? error.message.toString()
          : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to check out walk-in: $message')),
      );
    }
  }

  String _formatCheckInTime(DateTime time) {
    final localTime = time.toLocal();
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    return '${localTime.year}-$month-$day $hour:$minute';
  }
}
