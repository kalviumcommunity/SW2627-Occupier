import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/occupancy.dart';
import 'package:mobile/models/occupancy_analytics.dart';
import 'package:mobile/services/occupancy_analytics_service.dart';

void main() {
  final service = OccupancyAnalyticsService(
    clock: () => DateTime(2026, 11, 15, 15),
  );

  test('builds daily, Monday-based weekly and calendar-month ranges', () {
    final daily = OccupancyDateRange.forPeriod(
      OccupancyReportingPeriod.daily,
      DateTime(2026, 10, 31, 19),
    );
    final weekly = OccupancyDateRange.forPeriod(
      OccupancyReportingPeriod.weekly,
      DateTime(2026, 11, 1),
    );
    final monthly = OccupancyDateRange.forPeriod(
      OccupancyReportingPeriod.monthly,
      DateTime(2026, 10, 31),
    );

    expect(daily.start, DateTime(2026, 10, 31));
    expect(daily.end, DateTime(2026, 11, 1));
    expect(weekly.start, DateTime(2026, 10, 26));
    expect(weekly.end, DateTime(2026, 11, 2));
    expect(monthly.start, DateTime(2026, 10, 1));
    expect(monthly.end, DateTime(2026, 11, 1));
    expect(
      monthly.shift(OccupancyReportingPeriod.monthly, 1).start,
      DateTime(2026, 11, 1),
    );
  });

  test('clips cross-midnight sessions to a daily half-open range', () {
    final range = OccupancyDateRange.forPeriod(
      OccupancyReportingPeriod.daily,
      DateTime(2026, 10, 15),
    );
    final report = service.calculate(
      range: range,
      occupancies: [
        _occupancy(
          id: 'cross-day',
          branch: 'north',
          start: DateTime(2026, 10, 14, 23),
          end: DateTime(2026, 10, 15, 2),
        ),
        _occupancy(
          id: 'at-end',
          branch: 'north',
          start: range.end,
          end: range.end.add(const Duration(hours: 1)),
        ),
      ],
    );

    expect(report.metrics.totalSessions, 1);
    expect(report.metrics.occupiedResourceHours, 2);
    expect(report.trend, hasLength(24));
    expect(report.trend[0].metrics.occupiedResourceHours, 1);
    expect(report.trend[1].metrics.occupiedResourceHours, 1);
  });

  test('includes sessions crossing a week boundary from before its start', () {
    final range = OccupancyDateRange.forPeriod(
      OccupancyReportingPeriod.weekly,
      DateTime(2026, 10, 29),
    );
    final report = service.calculate(
      range: range,
      occupancies: [
        _occupancy(
          id: 'cross-week',
          branch: 'north',
          start: DateTime(2026, 10, 25, 23),
          end: DateTime(2026, 10, 27, 1),
        ),
      ],
    );

    expect(report.metrics.totalSessions, 1);
    expect(report.metrics.completedSessions, 1);
    expect(report.metrics.occupiedResourceHours, 25);
    expect(report.trend, hasLength(7));
    expect(report.trend.first.metrics.totalSessions, 1);
    expect(report.trend.first.metrics.occupiedResourceHours, 24);
    expect(report.trend[1].metrics.occupiedResourceHours, 1);
  });

  test('clips sessions crossing both calendar-month edges', () {
    final range = OccupancyDateRange.forPeriod(
      OccupancyReportingPeriod.monthly,
      DateTime(2026, 10, 15),
    );
    final report = service.calculate(
      range: range,
      occupancies: [
        _occupancy(
          id: 'from-september',
          branch: 'north',
          start: DateTime(2026, 9, 30, 23),
          end: DateTime(2026, 10, 1, 2),
        ),
        _occupancy(
          id: 'into-november',
          branch: 'south',
          start: DateTime(2026, 10, 31, 23),
          end: DateTime(2026, 11, 1, 2),
        ),
      ],
    );

    expect(report.metrics.totalSessions, 2);
    expect(report.metrics.occupiedResourceHours, 3);
    expect(report.branches.map((branch) => branch.branchId), [
      'north',
      'south',
    ]);
    expect(report.trend, hasLength(31));
    expect(report.trend.first.metrics.occupiedResourceHours, 2);
    expect(report.trend.last.metrics.occupiedResourceHours, 1);
  });

  test('uses the injected current time for open and future checkouts', () {
    final range = OccupancyDateRange(
      start: DateTime(2026, 10, 15),
      end: DateTime(2026, 10, 16),
    );
    final report =
        OccupancyAnalyticsService(clock: () => DateTime(2026, 10, 15, 15))
            .calculate(
              range: range,
              occupancies: [
                _occupancy(
                  id: 'active',
                  branch: 'north',
                  start: DateTime(2026, 10, 14, 10),
                  status: OccupancyStatus.active,
                ),
                _occupancy(
                  id: 'future-checkout',
                  branch: 'north',
                  start: DateTime(2026, 10, 15, 12),
                  end: DateTime(2026, 10, 15, 20),
                ),
              ],
            );

    expect(report.metrics.totalSessions, 2);
    expect(report.metrics.activeSessions, 1);
    expect(report.metrics.completedSessions, 1);
    expect(report.metrics.occupiedResourceHours, 18);
  });

  test('ignores duplicate IDs, zero durations and malformed sessions', () {
    final range = OccupancyDateRange(
      start: DateTime(2026, 10, 15),
      end: DateTime(2026, 10, 16),
    );
    final report = service.calculate(
      range: range,
      occupancies: [
        _occupancy(
          id: 'duplicate',
          branch: 'north',
          start: DateTime(2026, 10, 15, 10),
          end: DateTime(2026, 10, 15, 11),
        ),
        _occupancy(
          id: 'duplicate',
          branch: 'south',
          start: DateTime(2026, 10, 15, 10),
          end: DateTime(2026, 10, 15, 12),
        ),
        _occupancy(
          id: 'zero',
          branch: 'north',
          start: DateTime(2026, 10, 15, 10),
          end: DateTime(2026, 10, 15, 10),
        ),
        _occupancy(
          id: 'malformed-active',
          branch: 'north',
          start: DateTime(2026, 10, 15, 10),
          end: DateTime(2026, 10, 15, 11),
          status: OccupancyStatus.active,
        ),
        _occupancy(
          id: 'missing-completed-checkout',
          branch: 'north',
          start: DateTime(2026, 10, 15, 10),
          status: OccupancyStatus.completed,
        ),
        _occupancy(
          id: 'reversed',
          branch: 'north',
          start: DateTime(2026, 10, 15, 12),
          end: DateTime(2026, 10, 15, 11),
        ),
      ],
    );

    expect(report.metrics.totalSessions, 1);
    expect(report.metrics.completedSessions, 1);
    expect(report.metrics.occupiedResourceHours, 1);
    expect(report.branches.single.branchId, 'north');
  });

  test('aggregates branches and keeps room resource-hours distinct', () {
    final range = OccupancyDateRange(
      start: DateTime(2026, 10, 15),
      end: DateTime(2026, 10, 16),
    );
    final report = service.calculate(
      range: range,
      occupancies: [
        _occupancy(
          id: 'desk',
          branch: 'north',
          start: DateTime(2026, 10, 15, 10),
          end: DateTime(2026, 10, 15, 11),
        ),
        _occupancy(
          id: 'room',
          branch: 'south',
          type: 'room',
          start: DateTime(2026, 10, 15, 10),
          end: DateTime(2026, 10, 15, 13),
        ),
      ],
    );

    expect(report.metrics.totalSessions, 2);
    expect(report.metrics.deskSessions, 1);
    expect(report.metrics.roomSessions, 1);
    expect(report.metrics.roomResourceHours, 3);
    expect(report.branches.map((branch) => branch.branchId), [
      'north',
      'south',
    ]);
  });

  test('returns an empty report for an empty range of records', () {
    final range = OccupancyDateRange(
      start: DateTime(2026, 10, 15),
      end: DateTime(2026, 10, 16),
    );
    final report = service.calculate(range: range, occupancies: const []);

    expect(report.metrics.totalSessions, 0);
    expect(report.metrics.occupiedResourceHours, 0);
    expect(report.branches, isEmpty);
    expect(report.trend, hasLength(24));
  });
}

Occupancy _occupancy({
  required String id,
  required String branch,
  required DateTime start,
  DateTime? end,
  OccupancyStatus status = OccupancyStatus.completed,
  String type = 'desk',
}) => Occupancy(
  occupancyId: id,
  branchId: branch,
  resourceId: '$type-1',
  resourceType: type,
  userId: 'user-1',
  status: status,
  checkInTime: start,
  checkOutTime: end,
  source: OccupancySource.booking,
  createdAt: start,
);
