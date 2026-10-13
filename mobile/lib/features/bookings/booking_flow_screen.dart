import 'package:flutter/material.dart';

import '../../core/services/resource_repository.dart';
import '../../models/branch.dart';
import '../../models/desk.dart';
import '../../models/meeting_room.dart';

enum _ResourceKind { desk, meetingRoom }

class BookingFlowScreen extends StatefulWidget {
  BookingFlowScreen({super.key, ResourceRepository? repository})
    : _repository = repository ?? ResourceRepository();

  final ResourceRepository _repository;

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  String? _branchId;
  String? _resourceId;
  String? _resourceName;

  _ResourceKind _resourceKind = _ResourceKind.desk;

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  void _resetSelection() {
    _resourceId = null;
    _resourceName = null;
    _selectedDate = null;
    _startTime = null;
    _endTime = null;
  }

  void _selectResource(String id, String name) {
    setState(() {
      _resourceId = id;
      _resourceName = name;
      _selectedDate = null;
      _startTime = null;
      _endTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book a Resource')),
      body: StreamBuilder<List<Branch>>(
        stream: widget._repository.watchBranches(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Unable to load branches. Please try again.'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final branches = snapshot.data!
              .where((branch) => branch.status == BranchStatus.active)
              .toList();

          if (branches.isEmpty) {
            return const Center(child: Text('No active branches available.'));
          }

          Branch? selectedBranch;
          for (final branch in branches) {
            if (branch.id == _branchId) {
              selectedBranch = branch;
              break;
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '1. Choose a branch',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Branch',
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedBranch?.id,
                    hint: const Text('Select a branch'),
                    items: branches.map((branch) {
                      return DropdownMenuItem(
                        value: branch.id,
                        child: Text('${branch.name} · ${branch.city}'),
                      );
                    }).toList(),
                    onChanged: (id) {
                      setState(() {
                        _branchId = id;
                        _resetSelection();
                      });
                    },
                  ),
                ),
              ),
              if (selectedBranch != null) ...[
                const SizedBox(height: 24),
                Text(
                  '2. Choose a resource',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Desk'),
                      avatar: const Icon(Icons.event_seat, size: 18),
                      selected: _resourceKind == _ResourceKind.desk,
                      onSelected: (_) {
                        setState(() {
                          _resourceKind = _ResourceKind.desk;
                          _resetSelection();
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Meeting room'),
                      avatar: const Icon(Icons.meeting_room, size: 18),
                      selected: _resourceKind == _ResourceKind.meetingRoom,
                      onSelected: (_) {
                        setState(() {
                          _resourceKind = _ResourceKind.meetingRoom;
                          _resetSelection();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildResourcePicker(selectedBranch),
                const SizedBox(height: 24),
                Text(
                  '3. Choose a date',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _resourceId == null ? null : _pickDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    _selectedDate == null
                        ? 'Select date'
                        : MaterialLocalizations.of(context)
                              .formatMediumDate(_selectedDate!),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '4. Choose a time',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _selectedDate == null
                            ? null
                            : _pickStartTime,
                        child: Text(
                          _startTime == null
                              ? 'Start time'
                              : _startTime!.format(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _startTime == null ? null : _pickEndTime,
                        child: Text(
                          _endTime == null
                              ? 'End time'
                              : _endTime!.format(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Only resources marked available are listed. '
                  'Time-slot conflict checks will be added with booking creation.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _canReview
                      ? () => _reviewSelection(selectedBranch!)
                      : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review selection'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  bool get _canReview =>
      _branchId != null &&
      _resourceId != null &&
      _resourceName != null &&
      _selectedDate != null &&
      _startTime != null &&
      _endTime != null;

  Widget _buildResourcePicker(Branch branch) {
    if (_resourceKind == _ResourceKind.desk) {
      return StreamBuilder<List<Desk>>(
        stream: widget._repository.watchDesks(branch.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Unable to load desks.');
          }
          if (!snapshot.hasData) {
            return const LinearProgressIndicator();
          }

          final desks = snapshot.data!
              .where((desk) => desk.status == DeskStatus.available)
              .toList();

          if (desks.isEmpty) {
            return const Text('No desks are marked available in this branch.');
          }

          return Column(
            children: desks.map((desk) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.event_seat),
                  title: Text(desk.name),
                  subtitle: Text(
                    '${desk.type.replaceAll('_', ' ')} · Floor ${desk.floor}',
                  ),
                  trailing: Icon(
                    _resourceId == desk.id
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  selected: _resourceId == desk.id,
                  onTap: () => _selectResource(desk.id, desk.name),
                ),
              );
            }).toList(),
          );
        },
      );
    }

    return StreamBuilder<List<MeetingRoom>>(
      stream: widget._repository.watchMeetingRooms(branch.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Unable to load meeting rooms.');
        }
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }

        final rooms = snapshot.data!
            .where((room) => room.status == MeetingRoomStatus.available)
            .toList();

        if (rooms.isEmpty) {
          return const Text(
            'No meeting rooms are marked available in this branch.',
          );
        }

        return Column(
          children: rooms.map((room) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.meeting_room),
                title: Text(room.name),
                subtitle: Text(
                  'Capacity: ${room.capacity} · Floor ${room.floor}',
                ),
                trailing: Icon(
                  _resourceId == room.id
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                selected: _resourceId == room.id,
                onTap: () => _selectResource(room.id, room.name),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate: today,
      lastDate: DateTime(today.year + 1, today.month, today.day),
    );

    if (!mounted || picked == null) return;

    setState(() {
      _selectedDate = picked;
      _startTime = null;
      _endTime = null;
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );

    if (!mounted || picked == null) return;

    setState(() {
      _startTime = picked;

      if (_endTime != null && _minutes(_endTime!) <= _minutes(picked)) {
        _endTime = null;
      }
    });
  }

  Future<void> _pickEndTime() async {
    final start = _startTime!;
    final initial = start.hour < 23
        ? TimeOfDay(hour: start.hour + 1, minute: start.minute)
        : start;

    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? initial,
    );

    if (!mounted || picked == null) return;

    setState(() => _endTime = picked);
  }

  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  int? _parseClock(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return hour * 60 + minute;
  }

  void _reviewSelection(Branch branch) {
    final start = _minutes(_startTime!);
    final end = _minutes(_endTime!);
    final opening = _parseClock(branch.openingTime);
    final closing = _parseClock(branch.closingTime);

    String? error;

    if (end <= start) {
      error = 'End time must be later than start time.';
    } else if (opening == null || closing == null) {
      error = 'Branch opening hours are not configured correctly.';
    } else if (start < opening || end > closing) {
      error =
          'Choose a time within ${branch.openingTime}–'
          '${branch.closingTime}.';
    } else {
      final startDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _startTime!.hour,
        _startTime!.minute,
      );

      if (!startDateTime.isAfter(DateTime.now())) {
        error = 'Choose a future start time.';
      }
    }

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final date = MaterialLocalizations.of(context)
        .formatMediumDate(_selectedDate!);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review your selection'),
        content: Text(
          'Branch: ${branch.name}\n'
          'Resource: $_resourceName\n'
          'Date: $date\n'
          'Start: ${_startTime!.format(context)}\n'
          'End: ${_endTime!.format(context)}\n\n'
          'This is a selection preview only. No booking has been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
