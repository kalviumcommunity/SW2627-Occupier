import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/occupancy_repository.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/resource_repository.dart';
import '../../core/services/user_repository.dart';
import '../../models/branch.dart';
import '../../models/occupancy.dart';
import '../../models/user.dart';

class OccupancyManagementScreen extends StatefulWidget {
  const OccupancyManagementScreen({
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
  State<OccupancyManagementScreen> createState() =>
      _OccupancyManagementScreenState();
}

class _OccupancyManagementScreenState extends State<OccupancyManagementScreen> {
  late final String? _userId;
  late final UserRepository _userRepository;
  late final ResourceRepository _resourceRepository;
  late final OccupancyRepository _occupancyRepository;
  late final Future<OccupierUser?> _profileFuture;
  late final Stream<List<Branch>> _branchesStream;

  final Set<String> _checkingOutIds = {};
  final Map<String, Stream<List<Occupancy>>> _occupancyStreams = {};

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
            'Active walk-ins are available to authorized staff only.',
          );
        }

        return _buildBranchOccupancies(profile);
      },
    );
  }

  Widget _loadingScreen() {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }

  Widget _messageScreen(String message) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active walk-ins')),
      body: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }

  Widget _buildBranchOccupancies(OccupierUser profile) {
    return StreamBuilder<List<Branch>>(
      stream: _branchesStream,
      builder: (context, branchSnapshot) {
        if (branchSnapshot.hasError) {
          return _messageScreen('Unable to load branches. Please try again.');
        }
        if (!branchSnapshot.hasData) {
          return _loadingScreen();
        }

        final branches = branchSnapshot.data!
            .where((branch) => branch.status == BranchStatus.active)
            .where(
              (branch) =>
                  profile.role == UserRole.admin ||
                  branch.managerUid == _userId ||
                  branch.staffUids.contains(_userId),
            )
            .toList();

        if (branches.isEmpty) {
          return _messageScreen(
            'No active branches are assigned to your account.',
          );
        }

        final streamKey = profile.role == UserRole.admin
            ? 'admin'
            : (branches.map((branch) => branch.id).toList()..sort()).join(',');
        final occupancyStream = _occupancyStreams.putIfAbsent(
          streamKey,
          () => _watchWalkIns(branches, profile.role == UserRole.admin),
        );
        final branchesById = {for (final branch in branches) branch.id: branch};

        return Scaffold(
          appBar: AppBar(title: const Text('Active walk-ins')),
          body: StreamBuilder<List<Occupancy>>(
            stream: occupancyStream,
            builder: (context, occupancySnapshot) {
              if (occupancySnapshot.hasError) {
                return const Center(
                  child: Text('Unable to load active walk-ins.'),
                );
              }
              if (!occupancySnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final occupancies = occupancySnapshot.data!;
              if (occupancies.isEmpty) {
                return const Center(child: Text('No active walk-ins.'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: occupancies.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final occupancy = occupancies[index];
                  final branch = branchesById[occupancy.branchId];
                  final resourceType = occupancy.resourceType == 'room'
                      ? 'Meeting room'
                      : 'Desk';
                  final isCheckingOut = _checkingOutIds.contains(
                    occupancy.occupancyId,
                  );

                  return Card(
                    child: ListTile(
                      title: Text(
                        occupancy.customerName ?? 'Walk-in customer',
                        key: ValueKey(
                          'active-walk-in-${occupancy.occupancyId}',
                        ),
                      ),
                      subtitle: Text(
                        '${branch?.name ?? 'Branch'} · '
                        '$resourceType ${occupancy.resourceId}',
                      ),
                      trailing: TextButton.icon(
                        key: ValueKey(
                          'walk-in-checkout-${occupancy.occupancyId}',
                        ),
                        onPressed: isCheckingOut
                            ? null
                            : () => _checkOut(occupancy.occupancyId),
                        icon: isCheckingOut
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.logout),
                        label: Text(
                          isCheckingOut ? 'Checking out...' : 'Check out',
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Stream<List<Occupancy>> _watchWalkIns(List<Branch> branches, bool isAdmin) {
    if (isAdmin) {
      return _occupancyRepository.watchActiveOccupancies().map(
        _walkInOccupancies,
      );
    }

    return Stream<List<Occupancy>>.multi((controller) {
      final results = <String, List<Occupancy>>{};
      final subscriptions = <StreamSubscription<List<Occupancy>>>[];

      for (final branch in branches) {
        subscriptions.add(
          _occupancyRepository
              .watchActiveOccupancies(branchId: branch.id)
              .listen((occupancies) {
                results[branch.id] = _walkInOccupancies(occupancies);
                if (results.length == branches.length) {
                  controller.add(
                    results.values.expand((items) => items).toList(),
                  );
                }
              }, onError: controller.addError),
        );
      }

      controller.onCancel = () async {
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );
      };
    });
  }

  List<Occupancy> _walkInOccupancies(List<Occupancy> occupancies) {
    return occupancies
        .where((occupancy) => occupancy.source == OccupancySource.walkIn)
        .toList();
  }

  Future<void> _checkOut(String occupancyId) async {
    if (!_checkingOutIds.add(occupancyId)) return;
    setState(() {});

    try {
      await _occupancyRepository.checkOut(occupancyId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Walk-in checked out. Resource is now available.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message.toString()
          : 'Unable to check out walk-in: $error';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      _checkingOutIds.remove(occupancyId);
      if (mounted) setState(() {});
    }
  }
}
