import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/services/user_repository.dart';
import '../../../models/user.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserRepository _userRepository = UserRepository();

  late Future<OccupierUser?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<OccupierUser?> _loadProfile() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return null;
    }

    final profile = await _userRepository.getUser(firebaseUser.uid);

    if (profile != null) {
      return profile;
    }

    return OccupierUser(
      uid: firebaseUser.uid,
      name: firebaseUser.displayName ?? '',
      email: firebaseUser.email ?? '',
      photoUrl: firebaseUser.photoURL,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
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
            return const Center(
              child: Text('Please log in to view your profile.'),
            );
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: profile.photoUrl != null &&
                            profile.photoUrl!.isNotEmpty
                        ? NetworkImage(profile.photoUrl!)
                        : null,
                    child: profile.photoUrl == null ||
                            profile.photoUrl!.isEmpty
                        ? const Icon(Icons.person, size: 48)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    profile.name.isEmpty ? 'Occupier User' : profile.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
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