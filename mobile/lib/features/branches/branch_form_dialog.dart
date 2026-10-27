import 'package:flutter/material.dart';

import '../../core/services/resource_repository.dart';
import '../../models/branch.dart';

class BranchFormDialog extends StatefulWidget {
  const BranchFormDialog({super.key, required this.repository, this.branch});

  final ResourceRepository repository;
  final Branch? branch;

  @override
  State<BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<BranchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _contactNumberController;
  late final TextEditingController _deskCapacityController;
  late final TextEditingController _roomCapacityController;
  late final TextEditingController _imageUrlController;

  late TimeOfDay _openingTime;
  late TimeOfDay _closingTime;
  bool _saving = false;
  String? _errorMessage;

  bool get _isEditing => widget.branch != null;

  @override
  void initState() {
    super.initState();
    final branch = widget.branch;
    _nameController = TextEditingController(text: branch?.name ?? '');
    _addressController = TextEditingController(text: branch?.address ?? '');
    _cityController = TextEditingController(text: branch?.city ?? '');
    _contactNumberController = TextEditingController(
      text: branch?.contactNumber ?? '',
    );
    _deskCapacityController = TextEditingController(
      text: branch?.totalDeskCapacity.toString() ?? '0',
    );
    _roomCapacityController = TextEditingController(
      text: branch?.totalRoomCapacity.toString() ?? '0',
    );
    _imageUrlController = TextEditingController(text: branch?.imageUrl ?? '');
    _openingTime = _parseTime(
      branch?.openingTime,
      const TimeOfDay(hour: 9, minute: 0),
    );
    _closingTime = _parseTime(
      branch?.closingTime,
      const TimeOfDay(hour: 18, minute: 0),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _contactNumberController.dispose();
    _deskCapacityController.dispose();
    _roomCapacityController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  TimeOfDay _parseTime(String? value, TimeOfDay fallback) {
    if (value == null) return fallback;
    final parts = value.split(':');
    if (parts.length != 2) return fallback;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return fallback;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _serializeTime(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _selectTime({required bool opening}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: opening ? _openingTime : _closingTime,
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (opening) {
        _openingTime = selected;
      } else {
        _closingTime = selected;
      }
      _errorMessage = null;
    });
  }

  String? _requiredText(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required.';
    return null;
  }

  String? _capacityValidator(String? value, String label) {
    final text = value?.trim() ?? '';
    final capacity = int.tryParse(text);
    if (capacity == null || capacity < 0) {
      return '$label must be a whole number of 0 or greater.';
    }
    return null;
  }

  String? _imageUrlValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'Enter a valid HTTP or HTTPS URL.';
    }
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final openingMinutes = _openingTime.hour * 60 + _openingTime.minute;
    final closingMinutes = _closingTime.hour * 60 + _closingTime.minute;
    if (closingMinutes <= openingMinutes) {
      setState(() {
        _errorMessage = 'Closing time must be later than opening time.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final existing = widget.branch;
    final branch = Branch(
      id: existing?.id ?? '',
      name: _nameController.text.trim(),
      address: _addressController.text.trim(),
      city: _cityController.text.trim(),
      contactNumber: _contactNumberController.text.trim(),
      totalDeskCapacity: int.parse(_deskCapacityController.text.trim()),
      totalRoomCapacity: int.parse(_roomCapacityController.text.trim()),
      openingTime: _serializeTime(_openingTime),
      closingTime: _serializeTime(_closingTime),
      status: existing?.status ?? BranchStatus.active,
      imageUrl: _imageUrlController.text.trim().isEmpty
          ? null
          : _imageUrlController.text.trim(),
      managerUid: existing?.managerUid,
      staffUids: existing?.staffUids ?? const [],
      createdAt: existing?.createdAt,
    );

    try {
      if (existing == null) {
        await widget.repository.createBranch(branch);
      } else {
        await widget.repository.updateBranch(branch);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = 'Unable to save the branch. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit branch' : 'Create branch'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('branch-name-field'),
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Branch name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => _requiredText(value, 'Branch name'),
                ),
                TextFormField(
                  key: const ValueKey('branch-address-field'),
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) => _requiredText(value, 'Address'),
                ),
                TextFormField(
                  key: const ValueKey('branch-city-field'),
                  controller: _cityController,
                  decoration: const InputDecoration(labelText: 'City'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => _requiredText(value, 'City'),
                ),
                TextFormField(
                  key: const ValueKey('branch-contact-field'),
                  controller: _contactNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Contact number',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) => _requiredText(value, 'Contact number'),
                ),
                TextFormField(
                  key: const ValueKey('branch-desk-capacity-field'),
                  controller: _deskCapacityController,
                  decoration: const InputDecoration(
                    labelText: 'Total desk capacity',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      _capacityValidator(value, 'Desk capacity'),
                ),
                TextFormField(
                  key: const ValueKey('branch-room-capacity-field'),
                  controller: _roomCapacityController,
                  decoration: const InputDecoration(
                    labelText: 'Total meeting room capacity',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      _capacityValidator(value, 'Room capacity'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('branch-opening-time-button'),
                        onPressed: _saving
                            ? null
                            : () => _selectTime(opening: true),
                        icon: const Icon(Icons.schedule),
                        label: Text('Opens: ${_openingTime.format(context)}'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('branch-closing-time-button'),
                        onPressed: _saving
                            ? null
                            : () => _selectTime(opening: false),
                        icon: const Icon(Icons.schedule),
                        label: Text('Closes: ${_closingTime.format(context)}'),
                      ),
                    ],
                  ),
                ),
                TextFormField(
                  key: const ValueKey('branch-image-url-field'),
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                  ),
                  keyboardType: TextInputType.url,
                  validator: _imageUrlValidator,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Save changes' : 'Create branch'),
        ),
      ],
    );
  }
}
