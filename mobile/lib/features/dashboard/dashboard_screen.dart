import 'package:flutter/material.dart';

import '../../core/services/resource_repository.dart';
import '../../models/branch.dart';
import '../../models/desk.dart';
import '../../models/meeting_room.dart';
import '../../services/occupancy_service.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = ResourceRepository();
    final occupancyService = OccupancyService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Occupancy Dashboard'),
      ),
      body: StreamBuilder<List<Branch>>(
        stream: repository.watchBranches(),
        builder: (context, branchSnapshot) {
          if (branchSnapshot.hasError) {
            return const Center(
              child: Text('Unable to load branches from Firestore.'),
            );
          }

          if (branchSnapshot.connectionState ==
                  ConnectionState.waiting &&
              !branchSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final branches = (branchSnapshot.data ?? [])
              .where((branch) => branch.status == BranchStatus.active)
              .toList();

          if (branches.isEmpty) {
            return const Center(
              child: Text('No active branches found.'),
            );
          }

          return _buildNetworkDashboard(
            context,
            repository,
            occupancyService,
            branches,
          );
        },
      ),
    );
  }

  Widget _buildNetworkDashboard(
    BuildContext context,
    ResourceRepository repository,
    OccupancyService occupancyService,
    List<Branch> branches,
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
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final desks = deskSnapshot.data!;
            final rooms = roomSnapshot.data!;

            final totalCapacity = desks
                    .where((desk) =>
                        desk.status == DeskStatus.available ||
                        desk.status == DeskStatus.occupied)
                    .length +
                rooms
                    .where((room) =>
                        room.status == MeetingRoomStatus.available ||
                        room.status == MeetingRoomStatus.occupied)
                    .fold<int>(0, (sum, room) => sum + room.capacity);

            final occupiedCapacity = desks
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

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Network Overview',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                _buildStatCard(
                  'Total Capacity',
                  totalCapacity.toString(),
                ),
                _buildStatCard(
                  'Occupied Capacity',
                  occupiedCapacity.toString(),
                ),
                _buildStatCard(
                  'Available Capacity',
                  availableCapacity.toString(),
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
                const SizedBox(height: 8),
                const Text(
                  'Occupancy is estimated from each resource status. '
                  'Occupied meeting rooms count at their full seat capacity.',
                ),
              ],
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
        subscriptions[branch.id] = repository.watchDesks(branch.id).listen(
          (desks) {
            results[branch.id] = desks;
            if (results.length == branches.length) {
              controller.add(results.values.expand((items) => items).toList());
            }
          },
          onError: controller.addError,
        );
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
        subscriptions[branch.id] =
            repository.watchMeetingRooms(branch.id).listen(
          (rooms) {
            results[branch.id] = rooms;
            if (results.length == branches.length) {
              controller.add(results.values.expand((items) => items).toList());
            }
          },
          onError: controller.addError,
        );
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
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
