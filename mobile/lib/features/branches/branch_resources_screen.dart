import 'package:flutter/material.dart';

import '../../core/services/resource_repository.dart';
import '../../models/branch.dart';
import '../../models/desk.dart';
import '../../models/meeting_room.dart';

class BranchResourcesScreen extends StatelessWidget {
  const BranchResourcesScreen({
    super.key,
    required this.branch,
    required this.repository,
  });

  final Branch branch;
  final ResourceRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(branch.name)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${branch.address}, ${branch.city}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Opening hours: ${branch.openingTime}–'
                        '${branch.closingTime}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${branch.totalDeskCapacity} desks · '
                        '${branch.totalRoomCapacity} meeting rooms',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.event_seat), text: 'Desks'),
                Tab(icon: Icon(Icons.meeting_room), text: 'Meeting Rooms'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _DesksList(branchId: branch.id, repository: repository),
                  _MeetingRoomsList(
                    branchId: branch.id,
                    repository: repository,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesksList extends StatelessWidget {
  const _DesksList({required this.branchId, required this.repository});

  final String branchId;
  final ResourceRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Desk>>(
      stream: repository.watchDesks(branchId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _MessageState(message: 'Unable to load desks.');
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final desks = snapshot.data!;

        if (desks.isEmpty) {
          return const _MessageState(
            icon: Icons.event_seat,
            message: 'No desks have been added to this branch yet.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: desks.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final desk = desks[index];

            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.event_seat)),
                title: Text(desk.name),
                subtitle: Text(
                  '${_formatValue(desk.type)} · Floor ${desk.floor}',
                ),
                trailing: _StatusChip(status: desk.status.name),
              ),
            );
          },
        );
      },
    );
  }
}

class _MeetingRoomsList extends StatelessWidget {
  const _MeetingRoomsList({required this.branchId, required this.repository});

  final String branchId;
  final ResourceRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MeetingRoom>>(
      stream: repository.watchMeetingRooms(branchId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _MessageState(message: 'Unable to load meeting rooms.');
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rooms = snapshot.data!;

        if (rooms.isEmpty) {
          return const _MessageState(
            icon: Icons.meeting_room,
            message: 'No meeting rooms have been added to this branch yet.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rooms.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final room = rooms[index];

            final amenities = room.amenities.isEmpty
                ? 'No amenities listed'
                : room.amenities.join(' · ');

            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.meeting_room)),
                title: Text(room.name),
                subtitle: Text(
                  'Capacity: ${room.capacity} · Floor ${room.floor}\n'
                  '$amenities',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: _StatusChip(status: room.status.name),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;

    switch (status) {
      case 'available':
        color = Colors.green;
      case 'occupied':
        color = Colors.orange;
      case 'maintenance':
        color = Colors.red;
      default:
        color = Colors.blueGrey;
    }

    return Chip(
      label: Text(status),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withAlpha(25),
      side: BorderSide(color: color.withAlpha(80)),
      labelStyle: TextStyle(color: color, fontSize: 12),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.icon = Icons.info_outline});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _formatValue(String value) {
  if (value.isEmpty) return 'Unspecified';

  return value
      .split('_')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}
