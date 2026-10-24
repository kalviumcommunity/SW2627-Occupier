import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/permission_service.dart';
import '../../core/services/resource_repository.dart';
import '../../core/services/user_repository.dart';
import '../../models/branch.dart';
import '../../models/desk.dart';
import '../../models/meeting_room.dart';
import '../../models/user.dart';
import '../../services/occupancy_service.dart';
import '../../core/services/occupancy_repository.dart';
import '../../models/occupancy.dart';
import '../../core/constants/app_routes.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view the dashboard.')),
      );
    }

    return FutureBuilder<OccupierUser?>(
      future: UserRepository().getUser(uid),
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
        if (profile == null) {
          return const Scaffold(
            body: Center(child: Text('Your profile is unavailable.')),
          );
        }

        const permissions = PermissionService();
        return _buildDashboard(
          context,
          canReadAllOccupancies: permissions.isAdministrator(profile.role),
          canManageOccupancy: permissions.canManageOccupancy(profile.role),
        );
      },
    );
  }

  Widget _buildDashboard(
    BuildContext context, {
    required bool canReadAllOccupancies,
    required bool canManageOccupancy,
  }) {
    final repository = ResourceRepository();
    final occupancyService = OccupancyService();
    final occupancyRepository = OccupancyRepository();

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
          IconButton(
            tooltip: 'My Bookings',
            icon: const Icon(Icons.event_note),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.myBookings);
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Branch>>(
        stream: repository.watchBranches(),
        builder: (context, branchSnapshot) {
          if (branchSnapshot.hasError) {
            return const Center(
              child: Text('Unable to load branches from Firestore.'),
            );
          }

          if (branchSnapshot.connectionState == ConnectionState.waiting &&
              !branchSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final branches = (branchSnapshot.data ?? [])
              .where((branch) => branch.status == BranchStatus.active)
              .toList();

          if (branches.isEmpty) {
            return const Center(child: Text('No active branches found.'));
          }

          return _buildNetworkDashboard(
            context,
            repository,
            occupancyRepository,
            occupancyService,
            branches,
            canReadAllOccupancies,
          );
        },
      ),
    );
  }

  Widget _buildNetworkDashboard(
    BuildContext context,
    ResourceRepository repository,
    OccupancyRepository occupancyRepository,
    OccupancyService occupancyService,
    List<Branch> branches,
    bool canReadAllOccupancies,
  ) {
    return StreamBuilder<List<Desk>>(
      stream: _watchAllDesks(repository, branches),
      builder: (context, deskSnapshot) {
        if (deskSnapshot.hasError) {
          return const Center(
            child: Text('Unable to load desks from Firestore.'),
          );
        }

        if (!deskSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<List<MeetingRoom>>(
          stream: _watchAllRooms(repository, branches),
          builder: (context, roomSnapshot) {
            if (roomSnapshot.hasError) {
              return const Center(
                child: Text('Unable to load meeting rooms from Firestore.'),
              );
            }

            if (!roomSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final desks = deskSnapshot.data!;
            final rooms = roomSnapshot.data!;

            final totalCapacity =
                desks
                    .where(
                      (desk) =>
                          desk.status == DeskStatus.available ||
                          desk.status == DeskStatus.occupied,
                    )
                    .length +
                rooms
                    .where(
                      (room) =>
                          room.status == MeetingRoomStatus.available ||
                          room.status == MeetingRoomStatus.occupied,
                    )
                    .fold<int>(0, (sum, room) => sum + room.capacity);

            final occupiedCapacity =
                desks
                    .where((desk) => desk.status == DeskStatus.occupied)
                    .length +
                rooms
                    .where((room) => room.status == MeetingRoomStatus.occupied)
                    .fold<int>(0, (sum, room) => sum + room.capacity);

            final availableCapacity = occupancyService.calculateAvailable(
              occupied: occupiedCapacity,
              capacity: totalCapacity,
            );

            final occupancyRate = occupancyService.calculateOccupancyRate(
              occupied: occupiedCapacity,
              capacity: totalCapacity,
            );

            return StreamBuilder<List<Occupancy>>(
              stream: canReadAllOccupancies
                  ? occupancyRepository.watchActiveOccupancies()
                  : Stream.value(const <Occupancy>[]),
              builder: (context, occupancySnapshot) {
                if (occupancySnapshot.hasError) {
                  return const Center(
                    child: Text('Unable to load active occupancy records.'),
                  );
                }

                if (!occupancySnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final activeOccupancies = occupancySnapshot.data!;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Network Overview',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    _buildStatCard('Total Capacity', totalCapacity.toString()),
                    _buildStatCard(
                      'Occupied Capacity',
                      occupiedCapacity.toString(),
                    ),
                    _buildStatCard(
                      'Available Capacity',
                      availableCapacity.toString(),
                    ),
                    if (canReadAllOccupancies)
                      _buildStatCard(
                        'Active Check-ins',
                        activeOccupancies.length.toString(),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Occupancy Rate: ${occupancyRate.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: (occupancyRate / 100).clamp(0.0, 1.0),
                      minHeight: 12,
                    ),
                    const SizedBox(height: 20),
                    Text('Active branches: ${branches.length}'),
                    const SizedBox(height: 24),
                    const SizedBox(height: 8),
                    const SizedBox(height: 24),
                    Text(
                      'Branch Overview',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),

                    ...branches.map((branch) {
                      return StreamBuilder<List<Desk>>(
                        stream: repository.watchDesks(branch.id),
                        builder: (context, branchDeskSnapshot) {
                          if (branchDeskSnapshot.hasError) {
                            return Card(
                              child: ListTile(
                                title: Text(branch.name),
                                subtitle: const Text(
                                  'Unable to load branch desks.',
                                ),
                              ),
                            );
                          }

                          if (!branchDeskSnapshot.hasData) {
                            return Card(
                              child: ListTile(
                                title: Text(branch.name),
                                subtitle: const LinearProgressIndicator(),
                              ),
                            );
                          }

                          final desks = branchDeskSnapshot.data!;
                          return StreamBuilder<List<MeetingRoom>>(
                            stream: repository.watchMeetingRooms(branch.id),
                            builder: (context, roomSnapshot) {
                              if (roomSnapshot.hasError) {
                                return Card(
                                  child: ListTile(
                                    title: Text(branch.name),
                                    subtitle: const Text(
                                      'Unable to load meeting rooms.',
                                    ),
                                  ),
                                );
                              }

                              if (!roomSnapshot.hasData) {
                                return Card(
                                  child: ListTile(
                                    title: Text(branch.name),
                                    subtitle: const LinearProgressIndicator(),
                                  ),
                                );
                              }

                              final rooms = roomSnapshot.data!;

                              final totalCapacity =
                                  desks
                                      .where(
                                        (desk) =>
                                            desk.status ==
                                                DeskStatus.available ||
                                            desk.status == DeskStatus.occupied,
                                      )
                                      .length +
                                  rooms
                                      .where(
                                        (room) =>
                                            room.status ==
                                                MeetingRoomStatus.available ||
                                            room.status ==
                                                MeetingRoomStatus.occupied,
                                      )
                                      .fold<int>(
                                        0,
                                        (sum, room) => sum + room.capacity,
                                      );

                              final occupiedCapacity =
                                  desks
                                      .where(
                                        (desk) =>
                                            desk.status == DeskStatus.occupied,
                                      )
                                      .length +
                                  rooms
                                      .where(
                                        (room) =>
                                            room.status ==
                                            MeetingRoomStatus.occupied,
                                      )
                                      .fold<int>(
                                        0,
                                        (sum, room) => sum + room.capacity,
                                      );

                              final availableCapacity =
                                  (totalCapacity - occupiedCapacity)
                                      .clamp(0, totalCapacity)
                                      .toInt();

                              final occupancyRate = totalCapacity == 0
                                  ? 0.0
                                  : occupiedCapacity / totalCapacity;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        branch.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(branch.city),
                                      const Divider(height: 24),
                                      _BranchMetricRow(
                                        label: 'Total capacity',
                                        value: '$totalCapacity',
                                      ),
                                      const SizedBox(height: 8),
                                      _BranchMetricRow(
                                        label: 'Occupied',
                                        value: '$occupiedCapacity',
                                      ),
                                      const SizedBox(height: 8),
                                      _BranchMetricRow(
                                        label: 'Available',
                                        value: '$availableCapacity',
                                      ),
                                      const SizedBox(height: 12),
                                      LinearProgressIndicator(
                                        value: occupancyRate,
                                        minHeight: 8,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${(occupancyRate * 100).toStringAsFixed(1)}% occupied',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    }),

                    Text(
                      canReadAllOccupancies
                          ? 'Capacity is calculated from desk and room statuses. '
                                'Active check-ins are counted separately from occupancy records. '
                                'Occupied meeting rooms count at their full seat capacity.'
                          : 'Capacity is calculated from desk and room statuses. '
                                'Active check-in records are restricted to administrators. '
                                'Occupied meeting rooms count at their full seat capacity.',
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Stream<List<Desk>> _watchAllDesks(
    ResourceRepository repository,
    List<Branch> branches,
  ) {
    return Stream<List<Desk>>.multi((controller) {
      final results = <String, List<Desk>>{};
      final subscriptions = <String, dynamic>{};

      for (final branch in branches) {
        subscriptions[branch.id] = repository.watchDesks(branch.id).listen((
          desks,
        ) {
          results[branch.id] = desks;
          if (results.length == branches.length) {
            controller.add(results.values.expand((items) => items).toList());
          }
        }, onError: controller.addError);
      }

      controller.onCancel = () async {
        for (final subscription in subscriptions.values) {
          await subscription.cancel();
        }
      };
    });
  }

  Stream<List<MeetingRoom>> _watchAllRooms(
    ResourceRepository repository,
    List<Branch> branches,
  ) {
    return Stream<List<MeetingRoom>>.multi((controller) {
      final results = <String, List<MeetingRoom>>{};
      final subscriptions = <String, dynamic>{};

      for (final branch in branches) {
        subscriptions[branch.id] = repository
            .watchMeetingRooms(branch.id)
            .listen((rooms) {
              results[branch.id] = rooms;
              if (results.length == branches.length) {
                controller.add(
                  results.values.expand((items) => items).toList(),
                );
              }
            }, onError: controller.addError);
      }

      controller.onCancel = () async {
        for (final subscription in subscriptions.values) {
          await subscription.cancel();
        }
      };
    });
  }

  Widget _buildStatCard(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
