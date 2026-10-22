import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/profile_image_service.dart';
import '../../../core/services/user_repository.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../models/user.dart';
import '../../../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final UserRepository _userRepository = UserRepository();
  final ProfileImageService _profileImageService = ProfileImageService();
  final ImagePicker _imagePicker = ImagePicker();

  late Future<OccupierUser?> _profileFuture;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  bool _isLoggingOut = false;

  String? _selectedPhotoPath;
  String? _updatedPhotoUrl;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<OccupierUser?> _loadProfile() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) return null;

    return _userRepository.getUser(firebaseUser.uid);
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    setState(() => _isLoggingOut = true);

    try {
      await AuthService().logout();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to log out. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoggingOut = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final name = _nameController.text.trim();

    if (firebaseUser == null) return;

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter your name.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final photoUrl = _updatedPhotoUrl;

      await firebaseUser.updateDisplayName(name);

      if (photoUrl != null) {
        await firebaseUser.updatePhotoURL(photoUrl);
      }

      await _userRepository.updateProfile(
        uid: firebaseUser.uid,
        name: name,
        photoUrl: photoUrl,
      );

      await firebaseUser.reload();

      if (!mounted) return;

      setState(() {
        _isEditing = false;
        _isSaving = false;
        _selectedPhotoPath = null;
        _updatedPhotoUrl = null;
        _profileFuture = _loadProfile();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update profile. Please try again.'),
        ),
      );
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) return;

    try {
      final pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
      );

      if (pickedImage == null || !mounted) return;

      setState(() {
        _selectedPhotoPath = pickedImage.path;
        _isUploadingPhoto = true;
      });

      final downloadUrl = await _profileImageService.uploadProfilePhoto(
        uid: firebaseUser.uid,
        imageFile: File(pickedImage.path),
      );

      if (!mounted) return;

      setState(() {
        _updatedPhotoUrl = downloadUrl;
        _isUploadingPhoto = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo uploaded. Press Save to update your profile.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isUploadingPhoto = false;
        _selectedPhotoPath = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo upload failed. Check Firebase Storage setup.'),
        ),
      );
    }
  }

  void _cancelEditing(String currentName) {
    setState(() {
      _nameController.text = currentName;
      _isEditing = false;
      _selectedPhotoPath = null;
      _updatedPhotoUrl = null;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _isLoggingOut ? null : _logout,
            icon: _isLoggingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder<OccupierUser?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Unable to load your profile. Please try again.'),
            );
          }

          final profile = snapshot.data;

          if (profile == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Your profile is unavailable.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _profileFuture = _loadProfile();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            );
          }

          final currentPhotoUrl = _updatedPhotoUrl ?? profile.photoUrl;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        backgroundImage: _selectedPhotoPath != null
                            ? FileImage(File(_selectedPhotoPath!))
                            : null,
                        child: _selectedPhotoPath != null
                            ? null
                            : ClipOval(
                                child: SizedBox(
                                  width: 104,
                                  height: 104,
                                  child:
                                      currentPhotoUrl != null &&
                                          currentPhotoUrl.isNotEmpty
                                      ? AppNetworkImage(
                                          imageUrl: currentPhotoUrl,
                                          width: 104,
                                          height: 104,
                                          placeholder: const Icon(
                                            Icons.person,
                                            size: 52,
                                          ),
                                        )
                                      : const Center(
                                          child: Icon(Icons.person, size: 52),
                                        ),
                                ),
                              ),
                      ),
                      if (_isEditing)
                        IconButton.filled(
                          onPressed: _isUploadingPhoto || _isSaving
                              ? null
                              : _pickAndUploadPhoto,
                          tooltip: 'Change profile photo',
                          icon: const Icon(Icons.camera_alt),
                        ),
                    ],
                  ),
                  if (_isUploadingPhoto) ...[
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Uploading photo...'),
                  ],
                  const SizedBox(height: 16),
                  if (_isEditing)
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    )
                  else
                    Text(
                      profile.name.isEmpty ? 'Occupier User' : profile.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 12),
                  if (_isEditing)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isSaving || _isUploadingPhoto
                              ? null
                              : _saveProfile,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                        OutlinedButton(
                          onPressed: _isSaving || _isUploadingPhoto
                              ? null
                              : () => _cancelEditing(profile.name),
                          child: const Text('Cancel'),
                        ),
                      ],
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () {
                        _nameController.text = profile.name;
                        setState(() => _isEditing = true);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit Profile'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    profile.email,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('Role'),
                      subtitle: Text(profile.role.name),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: const Text('User ID'),
                      subtitle: SelectableText(profile.uid),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
