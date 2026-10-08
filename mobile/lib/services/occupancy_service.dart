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
  int calculateAvailable({
    required int occupied,
    required int capacity,
  }) {
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
}