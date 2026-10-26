import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/services/resource_repository.dart';
import '../../models/desk.dart';
import '../../models/meeting_room.dart';

class AddDeskDialog extends StatefulWidget {
  const AddDeskDialog({
    super.key,
    required this.branchId,
    required this.repository,
  });

  final String branchId;
  final ResourceRepository repository;

  @override
  State<AddDeskDialog> createState() => _AddDeskDialogState();
}

class _AddDeskDialogState extends State<AddDeskDialog> {
  static const _deskTypes = <String, String>{
    'hot_desk': 'Hot desk',
    'dedicated': 'Dedicated desk',
    'premium': 'Premium desk',
  };

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _floorController = TextEditingController();
  String _selectedType = 'hot_desk';
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _floorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.createDesk(
        widget.branchId,
        Desk(
          name: _nameController.text.trim(),
          type: _selectedType,
          floor: _floorController.text.trim(),
          status: DeskStatus.available,
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.code == 'permission-denied'
            ? 'You do not have permission to add a desk to this branch.'
            : 'Could not save the desk. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not save the desk. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add desk'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Desk name or number',
                  hintText: 'e.g. Desk 12',
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter a desk name or number.';
                  if (text.length > 100) return 'Use 100 characters or fewer.';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(labelText: 'Desk type'),
                items: _deskTypes.entries
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _selectedType = value);
                      },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _floorController,
                textCapitalization: TextCapitalization.words,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Floor',
                  hintText: 'e.g. Ground or 2',
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter the floor.';
                  if (text.length > 30) return 'Use 30 characters or fewer.';
                  return null;
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save desk'),
        ),
      ],
    );
  }
}

class AddMeetingRoomDialog extends StatefulWidget {
  const AddMeetingRoomDialog({
    super.key,
    required this.branchId,
    required this.repository,
  });

  final String branchId;
  final ResourceRepository repository;

  @override
  State<AddMeetingRoomDialog> createState() => _AddMeetingRoomDialogState();
}

class _AddMeetingRoomDialogState extends State<AddMeetingRoomDialog> {
  static const _availableAmenities = <String>[
    'Projector',
    'Whiteboard',
    'Video conferencing',
    'TV',
    'Conference phone',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController(text: '4');
  final _floorController = TextEditingController();
  final Set<String> _selectedAmenities = <String>{};
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    _floorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final capacity = int.tryParse(_capacityController.text.trim());
    if (capacity == null || capacity < 1) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.createMeetingRoom(
        widget.branchId,
        MeetingRoom(
          name: _nameController.text.trim(),
          capacity: capacity,
          floor: _floorController.text.trim(),
          amenities: _availableAmenities
              .where(_selectedAmenities.contains)
              .toList(),
          status: MeetingRoomStatus.available,
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.code == 'permission-denied'
            ? 'You do not have permission to add a meeting room to this branch.'
            : 'Could not save the meeting room. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not save the meeting room. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add meeting room'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Room name',
                  hintText: 'e.g. Conference Room A',
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter a room name.';
                  if (text.length > 100) return 'Use 100 characters or fewer.';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _capacityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Capacity',
                  hintText: 'Number of people',
                ),
                validator: (value) {
                  final capacity = int.tryParse(value?.trim() ?? '');
                  if (capacity == null || capacity < 1) {
                    return 'Enter a capacity of at least 1.';
                  }
                  if (capacity > 1000) return 'Capacity seems too high.';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _floorController,
                textCapitalization: TextCapitalization.words,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Floor',
                  hintText: 'e.g. Ground or 2',
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter the floor.';
                  if (text.length > 30) return 'Use 30 characters or fewer.';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text('Amenities', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 0,
                children: _availableAmenities.map((amenity) {
                  return FilterChip(
                    label: Text(amenity),
                    selected: _selectedAmenities.contains(amenity),
                    onSelected: _isSaving
                        ? null
                        : (selected) {
                            setState(() {
                              if (selected) {
                                _selectedAmenities.add(amenity);
                              } else {
                                _selectedAmenities.remove(amenity);
                              }
                            });
                          },
                  );
                }).toList(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save room'),
        ),
      ],
    );
  }
}
