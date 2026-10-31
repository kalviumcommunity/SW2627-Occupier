import '../models/desk.dart';
import '../models/meeting_room.dart';
import '../models/occupancy.dart';

int _roomCapacity(MeetingRoom room) => room.capacity < 0 ? 0 : room.capacity;

class OccupancyService {
  /// Calculates the occupancy percentage.
  ///
  /// Example:
  /// occupied = 74
  /// capacity = 100
  /// result = 74.0
  double calculateOccupancyRate({
    required int occupied,
    required int capacity,
  }) {
    if (capacity <= 0) {
      return 0;
    }

    return (occupied / capacity) * 100;
  }

  /// Calculates the number of available resources.
  ///
  /// Example:
  /// capacity = 100
  /// occupied = 74
  /// result = 26
  int calculateAvailable({required int occupied, required int capacity}) {
    final available = capacity - occupied;

    return available < 0 ? 0 : available;
  }

  /// Calculates network-wide occupancy.
  ///
  /// This uses total occupied resources divided by total capacity.
  /// It does NOT average individual branch percentages.
  double calculateNetworkOccupancy({
    required int totalOccupied,
    required int totalCapacity,
  }) {
    if (totalCapacity <= 0) {
      return 0;
    }

    return (totalOccupied / totalCapacity) * 100;
  }

  BranchOccupancySummary calculateBranchSummary({
    required String branchId,
    required List<Desk> desks,
    required List<MeetingRoom> meetingRooms,
    required List<Occupancy> activeOccupancies,
  }) {
    final availableDesks = desks
        .where((desk) => desk.status == DeskStatus.available)
        .length;
    final occupiedDesks = desks
        .where((desk) => desk.status == DeskStatus.occupied)
        .length;
    final unavailableDesks = desks.length - availableDesks - occupiedDesks;
    final availableRooms = meetingRooms
        .where((room) => room.status == MeetingRoomStatus.available)
        .toList();
    final occupiedRooms = meetingRooms
        .where((room) => room.status == MeetingRoomStatus.occupied)
        .toList();
    final unavailableRooms =
        meetingRooms.length - availableRooms.length - occupiedRooms.length;

    final totalCapacity =
        availableDesks +
        occupiedDesks +
        availableRooms.fold<int>(
          0,
          (capacity, room) => capacity + _roomCapacity(room),
        ) +
        occupiedRooms.fold<int>(
          0,
          (capacity, room) => capacity + _roomCapacity(room),
        );
    final occupiedCapacity =
        occupiedDesks +
        occupiedRooms.fold<int>(
          0,
          (capacity, room) => capacity + _roomCapacity(room),
        );
    final occupiedResourceIds = activeOccupancies
        .where(
          (occupancy) =>
              occupancy.branchId == branchId &&
              occupancy.status == OccupancyStatus.active,
        )
        .map((occupancy) => '${occupancy.resourceType}/${occupancy.resourceId}')
        .toSet();

    return BranchOccupancySummary(
      branchId: branchId,
      availableDesks: availableDesks,
      occupiedDesks: occupiedDesks,
      availableMeetingRooms: availableRooms.length,
      occupiedMeetingRooms: occupiedRooms.length,
      totalResources: desks.length + meetingRooms.length,
      occupiedResources: occupiedDesks + occupiedRooms.length,
      availableResources: availableDesks + availableRooms.length,
      unavailableResources: unavailableDesks + unavailableRooms,
      unavailableDesks: unavailableDesks,
      unavailableMeetingRooms: unavailableRooms,
      totalCapacity: totalCapacity,
      occupiedCapacity: occupiedCapacity,
      availableCapacity: calculateAvailable(
        occupied: occupiedCapacity,
        capacity: totalCapacity,
      ),
      occupancyRate: calculateOccupancyRate(
        occupied: occupiedCapacity,
        capacity: totalCapacity,
      ),
      activeCheckIns: occupiedResourceIds.length,
    );
  }

  NetworkOccupancySummary calculateNetworkSummary(
    List<BranchOccupancySummary> branches,
  ) {
    final totalCapacity = branches.fold<int>(
      0,
      (capacity, branch) => capacity + branch.totalCapacity,
    );
    final occupiedCapacity = branches.fold<int>(
      0,
      (capacity, branch) => capacity + branch.occupiedCapacity,
    );

    return NetworkOccupancySummary(
      totalBranches: branches.length,
      totalResources: branches.fold<int>(
        0,
        (count, branch) => count + branch.totalResources,
      ),
      occupiedResources: branches.fold<int>(
        0,
        (count, branch) => count + branch.occupiedResources,
      ),
      availableResources: branches.fold<int>(
        0,
        (count, branch) => count + branch.availableResources,
      ),
      unavailableResources: branches.fold<int>(
        0,
        (count, branch) => count + branch.unavailableResources,
      ),
      activeCheckIns: branches.fold<int>(
        0,
        (count, branch) => count + branch.activeCheckIns,
      ),
      totalCapacity: totalCapacity,
      occupiedCapacity: occupiedCapacity,
      availableCapacity: calculateAvailable(
        occupied: occupiedCapacity,
        capacity: totalCapacity,
      ),
      occupancyRate: calculateNetworkOccupancy(
        totalOccupied: occupiedCapacity,
        totalCapacity: totalCapacity,
      ),
    );
  }
}

class BranchOccupancySummary {
  const BranchOccupancySummary({
    required this.branchId,
    required this.availableDesks,
    required this.occupiedDesks,
    required this.availableMeetingRooms,
    required this.occupiedMeetingRooms,
    required this.totalResources,
    required this.occupiedResources,
    required this.availableResources,
    required this.unavailableResources,
    required this.unavailableDesks,
    required this.unavailableMeetingRooms,
    required this.totalCapacity,
    required this.occupiedCapacity,
    required this.availableCapacity,
    required this.occupancyRate,
    required this.activeCheckIns,
  });

  final String branchId;
  final int availableDesks;
  final int occupiedDesks;
  final int availableMeetingRooms;
  final int occupiedMeetingRooms;
  final int totalResources;
  final int occupiedResources;
  final int availableResources;
  final int unavailableResources;
  final int unavailableDesks;
  final int unavailableMeetingRooms;
  final int totalCapacity;
  final int occupiedCapacity;
  final int availableCapacity;
  final double occupancyRate;
  final int activeCheckIns;
}

class NetworkOccupancySummary {
  const NetworkOccupancySummary({
    required this.totalBranches,
    required this.totalResources,
    required this.occupiedResources,
    required this.availableResources,
    required this.unavailableResources,
    required this.activeCheckIns,
    required this.totalCapacity,
    required this.occupiedCapacity,
    required this.availableCapacity,
    required this.occupancyRate,
  });

  final int totalBranches;
  final int totalResources;
  final int occupiedResources;
  final int availableResources;
  final int unavailableResources;
  final int activeCheckIns;
  final int totalCapacity;
  final int occupiedCapacity;
  final int availableCapacity;
  final double occupancyRate;
}
