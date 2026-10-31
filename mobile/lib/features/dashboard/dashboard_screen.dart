import 'dart:async';

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
import '../../services/occupancy_service.dart';

String? _firebaseCurrentUserId() => FirebaseAuth.instance.currentUser?.uid;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.currentUserId,
    this.userRepository,
    this.resourceRepository,
    this.occupancyRepository,
  });

  final String? Function()? currentUserId;
  final UserRepository? userRepository;
  final ResourceRepository? resourceRepository;
  final OccupancyRepository? occupancyRepository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final String? _uid;
  late final UserRepository _userRepository;
  late final ResourceRepository _resourceRepository;
  late final OccupancyRepository _occupancyRepository;
  late final Stream<OccupierUser?>? _profileStream;
  late Stream<List<Branch>> _branchesStream;

  @override
  void initState() {
    super.initState();
    _uid = (widget.currentUserId ?? _firebaseCurrentUserId)();
    _userRepository = widget.userRepository ?? UserRepository();
    _resourceRepository = widget.resourceRepository ?? ResourceRepository();
    _occupancyRepository = widget.occupancyRepository ?? OccupancyRepository();
    final uid = _uid;
    _profileStream = uid == null || uid.isEmpty
        ? null
        : _userRepository.watchUser(uid);
    _branchesStream = _resourceRepository.watchBranches();
  }

  void _reloadBranches() {
    setState(() {
      _branchesStream = _resourceRepository.watchBranches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view the dashboard.')),
      );
    }

    return StreamBuilder<OccupierUser?>(
      stream: _profileStream,
      builder: (context, profileSnapshot) {
        if (profileSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Unable to load your access profile.')),
          );
        }

        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = profileSnapshot.data;
        if (profile == null || profile.uid != uid) {
          return const Scaffold(
            body: Center(child: Text('Your profile is unavailable.')),
          );
        }

        return _buildDashboard(context, uid, profile.role);
      },
    );
  }

  Widget _buildDashboard(BuildContext context, String uid, UserRole role) {
    const permissions = PermissionService();
    final canManageOccupancy = permissions.canManageOccupancy(role);
    final canManageUsers = permissions.canManageUsers(role);
    final canSeeOccupancy = permissions.canViewOccupancy(role);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Occupancy Dashboard'),
        actions: [
          if (canManageOccupancy)
            IconButton(
              tooltip: 'Walk-in check-in',
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.walkInCheckIn);
              },
            ),
          if (canManageOccupancy)
            IconButton(
              tooltip: 'Active walk-ins',
              icon: const Icon(Icons.logout),
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.occupancy);
              },
            ),
          if (canManageUsers)
            IconButton(
              tooltip: 'User management',
              icon: const Icon(Icons.manage_accounts_outlined),
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.adminUserManagement);
              },
            ),
          IconButton(
            tooltip: 'My Bookings',
            icon: const Icon(Icons.event_note),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.myBookings);
            },
          ),
        ],
      ),
      body: !canSeeOccupancy
          ? const _MemberDashboardNotice()
          : StreamBuilder<List<Branch>>(
              stream: _branchesStream,
              builder: (context, branchSnapshot) {
                if (branchSnapshot.hasError) {
                  return _DashboardError(
                    message: 'Unable to load branches from Firestore.',
                    onRetry: _reloadBranches,
                  );
                }

                if (!branchSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final activeBranches = branchSnapshot.data!
                    .where((branch) => branch.status == BranchStatus.active)
                    .where((branch) {
                      if (permissions.canViewNetworkOccupancy(role)) {
                        return true;
                      }
                      return branch.managerUid == uid ||
                          branch.staffUids.contains(uid);
                    })
                    .toList();

                if (activeBranches.isEmpty) {
                  return Center(
                    child: Text(
                      permissions.canViewNetworkOccupancy(role)
                          ? 'No active branches found.'
                          : 'No active branches are assigned to your account.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return _BranchOccupancyDashboard(
                  branches: activeBranches,
                  isAdministrator: permissions.canViewNetworkOccupancy(role),
                  resourceRepository: _resourceRepository,
                  occupancyRepository: _occupancyRepository,
                );
              },
            ),
    );
  }
}

class _MemberDashboardNotice extends StatelessWidget {
  const _MemberDashboardNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Occupancy information is available to administrators and '
          'assigned branch staff.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _BranchOccupancyDashboard extends StatefulWidget {
  const _BranchOccupancyDashboard({
    required this.branches,
    required this.isAdministrator,
    required this.resourceRepository,
    required this.occupancyRepository,
  });

  final List<Branch> branches;
  final bool isAdministrator;
  final ResourceRepository resourceRepository;
  final OccupancyRepository occupancyRepository;

  @override
  State<_BranchOccupancyDashboard> createState() =>
      _BranchOccupancyDashboardState();
}

class _BranchOccupancyDashboardState extends State<_BranchOccupancyDashboard> {
  final _occupancyService = OccupancyService();
  late Stream<List<BranchOccupancySummary>> _summaryStream;

  @override
  void initState() {
    super.initState();
    _summaryStream = _watchSummaries();
  }

  @override
  void didUpdateWidget(covariant _BranchOccupancyDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldBranchIds = oldWidget.branches.map((branch) => branch.id).toList();
    final newBranchIds = widget.branches.map((branch) => branch.id).toList();
    if (oldWidget.isAdministrator != widget.isAdministrator ||
        !_sameBranchIds(oldBranchIds, newBranchIds) ||
        !identical(oldWidget.resourceRepository, widget.resourceRepository) ||
        !identical(oldWidget.occupancyRepository, widget.occupancyRepository)) {
      _summaryStream = _watchSummaries();
    }
  }

  Stream<List<BranchOccupancySummary>> _watchSummaries() {
    final branches = widget.branches;

    return Stream<List<BranchOccupancySummary>>.multi((controller) {
      final liveData = {
        for (final branch in branches) branch.id: _BranchLiveData(),
      };
      final subscriptions = <Future<void> Function()>[];

      void emitIfReady() {
        if (!liveData.values.every((data) => data.isReady)) return;

        controller.add([
          for (final branch in branches)
            _occupancyService.calculateBranchSummary(
              branchId: branch.id,
              desks: liveData[branch.id]!.desks!,
              meetingRooms: liveData[branch.id]!.meetingRooms!,
              activeOccupancies: liveData[branch.id]!.activeOccupancies!,
            ),
        ]);
      }

      for (final branch in branches) {
        final data = liveData[branch.id]!;
        final deskSubscription = widget.resourceRepository
            .watchDesks(branch.id)
            .listen((desks) {
              data.desks = desks;
              emitIfReady();
            }, onError: controller.addError);
        final roomSubscription = widget.resourceRepository
            .watchMeetingRooms(branch.id)
            .listen((rooms) {
              data.meetingRooms = rooms;
              emitIfReady();
            }, onError: controller.addError);
        subscriptions
          ..add(() => deskSubscription.cancel())
          ..add(() => roomSubscription.cancel());
      }

      if (widget.isAdministrator) {
        final occupancySubscription = widget.occupancyRepository
            .watchActiveOccupancies()
            .listen((occupancies) {
              for (final branch in branches) {
                liveData[branch.id]!.activeOccupancies = occupancies
                    .where((occupancy) => occupancy.branchId == branch.id)
                    .toList();
              }
              emitIfReady();
            }, onError: controller.addError);
        subscriptions.add(() => occupancySubscription.cancel());
      } else {
        for (final branch in branches) {
          final occupancySubscription = widget.occupancyRepository
              .watchActiveOccupancies(branchId: branch.id)
              .listen((occupancies) {
                liveData[branch.id]!.activeOccupancies = occupancies;
                emitIfReady();
              }, onError: controller.addError);
          subscriptions.add(() => occupancySubscription.cancel());
        }
      }

      controller.onCancel = () async {
        await Future.wait(subscriptions.map((cancel) => cancel()));
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BranchOccupancySummary>>(
      stream: _summaryStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Unable to load live occupancy data.'),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final summaries = snapshot.data!;
        final network = _occupancyService.calculateNetworkSummary(summaries);
        final branchesById = {
          for (final branch in widget.branches) branch.id: branch,
        };

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.isAdministrator ? 'Network Overview' : 'Branch Overview',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _DashboardMetricCard(
                        label: widget.isAdministrator
                            ? 'Active branches'
                            : 'Your branches',
                        value: '${network.totalBranches}',
                        icon: Icons.apartment,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _DashboardMetricCard(
                        label: 'Resources',
                        value: '${network.totalResources}',
                        icon: Icons.desk,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _DashboardMetricCard(
                        label: 'Occupied resources',
                        value: '${network.occupiedResources}',
                        icon: Icons.people_alt_outlined,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _DashboardMetricCard(
                        label: 'Available resources',
                        value: '${network.availableResources}',
                        icon: Icons.event_available_outlined,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _DashboardMetricCard(
                        label: 'Maintenance or inactive',
                        value: '${network.unavailableResources}',
                        icon: Icons.do_not_disturb_on_outlined,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _DashboardMetricCard(
                        label: 'Active check-ins',
                        value: '${network.activeCheckIns}',
                        icon: Icons.login,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _DashboardMetricCard(
                        label: 'Occupancy',
                        value: '${network.occupancyRate.toStringAsFixed(1)}%',
                        icon: Icons.pie_chart_outline,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _CapacityCard(
              occupiedCapacity: network.occupiedCapacity,
              availableCapacity: network.availableCapacity,
              totalCapacity: network.totalCapacity,
              occupancyRate: network.occupancyRate,
            ),
            const SizedBox(height: 24),
            Text(
              'Branch Occupancy',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            ...summaries.map((summary) {
              final branch = branchesById[summary.branchId];
              if (branch == null) return const SizedBox.shrink();
              return _BranchOccupancyCard(branch: branch, summary: summary);
            }),
            const SizedBox(height: 8),
            Text(
              'Occupancy uses current resource status. Desks count as one '
              'capacity unit; an occupied meeting room counts at its full '
              'seat capacity. Active check-ins are shown separately.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

bool _sameBranchIds(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

class _BranchLiveData {
  List<Desk>? desks;
  List<MeetingRoom>? meetingRooms;
  List<Occupancy>? activeOccupancies;

  bool get isReady =>
      desks != null && meetingRooms != null && activeOccupancies != null;
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({
    required this.occupiedCapacity,
    required this.availableCapacity,
    required this.totalCapacity,
    required this.occupancyRate,
  });

  final int occupiedCapacity;
  final int availableCapacity;
  final int totalCapacity;
  final double occupancyRate;

  @override
  Widget build(BuildContext context) {
    final progress = (occupancyRate / 100).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Capacity utilization',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('$occupiedCapacity occupied of $totalCapacity capacity units'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress, minHeight: 10),
            const SizedBox(height: 8),
            Text(
              '$availableCapacity available · '
              '${occupancyRate.toStringAsFixed(1)}% occupied',
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchOccupancyCard extends StatelessWidget {
  const _BranchOccupancyCard({required this.branch, required this.summary});

  final Branch branch;
  final BranchOccupancySummary summary;

  @override
  Widget build(BuildContext context) {
    final progress = (summary.occupancyRate / 100).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(branch.name, style: Theme.of(context).textTheme.titleLarge),
            if (branch.city.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(branch.city),
            ],
            const Divider(height: 24),
            _BranchMetricRow(
              label: 'Desks',
              value:
                  '${summary.occupiedDesks} occupied · '
                  '${summary.availableDesks} available · '
                  '${summary.unavailableDesks} unavailable',
            ),
            const SizedBox(height: 8),
            _BranchMetricRow(
              label: 'Meeting rooms',
              value:
                  '${summary.occupiedMeetingRooms} occupied · '
                  '${summary.availableMeetingRooms} available · '
                  '${summary.unavailableMeetingRooms} unavailable',
            ),
            const SizedBox(height: 8),
            _BranchMetricRow(
              label: 'Resources',
              value:
                  '${summary.occupiedResources} occupied · '
                  '${summary.availableResources} available · '
                  '${summary.totalResources} total',
            ),
            const SizedBox(height: 8),
            _BranchMetricRow(
              label: 'Active check-ins',
              value: '${summary.activeCheckIns}',
            ),
            const SizedBox(height: 8),
            Text(
              '${summary.occupiedCapacity} of ${summary.totalCapacity} '
              'capacity units occupied · ${summary.availableCapacity} available',
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, minHeight: 8),
            const SizedBox(height: 6),
            Text('${summary.occupancyRate.toStringAsFixed(1)}% occupied'),
          ],
        ),
      ),
    );
  }
}

class _BranchMetricRow extends StatelessWidget {
  const _BranchMetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
