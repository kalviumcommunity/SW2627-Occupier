import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/occupancy_service.dart';

void main() {
  final service = OccupancyService();

  test(
    'calculates occupied, available, and percentage without double counting',
    () {
      const totalDeskUnits = 3;
      const totalRoomSeats = 7;
      const occupiedDeskUnits = 1;
      const occupiedRoomSeats = 4;
      const totalCapacity = totalDeskUnits + totalRoomSeats;
      const occupiedCapacity = occupiedDeskUnits + occupiedRoomSeats;

      expect(
        service.calculateAvailable(
          occupied: occupiedCapacity,
          capacity: totalCapacity,
        ),
        5,
      );
      expect(
        service.calculateOccupancyRate(
          occupied: occupiedCapacity,
          capacity: totalCapacity,
        ),
        50,
      );
    },
  );

  test(
    'returns zero percent and zero available capacity for empty branches',
    () {
      expect(service.calculateOccupancyRate(occupied: 0, capacity: 0), 0);
      expect(service.calculateAvailable(occupied: 0, capacity: 0), 0);
    },
  );

  test('clamps availability when occupancy exceeds capacity', () {
    expect(service.calculateAvailable(occupied: 4, capacity: 3), 0);
  });
}
