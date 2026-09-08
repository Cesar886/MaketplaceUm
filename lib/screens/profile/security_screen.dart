import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/app_shimmer.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late Future<List<Map<String, dynamic>>> _users;

  @override
  void initState() {
    super.initState();
    _users = ApiService.getSecurityUsers();
  }

  Future<void> _reload() async {
    setState(() => _users = ApiService.getSecurityUsers());
    await _users;
  }

  Future<void> _setBlocked(String id, bool value) async {
    await ApiService.setChatUserBlocked(id, value);
    await _reload();
  }

  Future<void> _setMuted(String id, bool value) async {
    await ApiService.setChatUserMuted(id, value);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('security_center.title'.tr())),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _users,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppListSkeleton(itemCount: 4);
            }
            if (snapshot.hasError) {
              return Center(child: Text('settings.security_error'.tr()));
            }
            final users = snapshot.data ?? const [];
            if (users.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'security_center.empty'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.muted),
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView.separated(
                padding: const EdgeInsets.all(18),
                itemCount: users.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final user = users[index];
                  final id = user['userId'] as String? ?? '';
                  final blocked = user['blocked'] == true;
                  final muted = user['muted'] == true;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      border: Border.all(color: context.colors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: context.colors.primary
                                  .withValues(alpha: 0.1),
                              child: Text(
                                (user['avatarInitials'] as String?) ??
                                    _initials(user['name'] as String? ?? '?'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user['name'] as String? ?? id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.colors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilterChip(
                              selected: blocked,
                              label: Text(
                                (blocked
                                        ? 'chat.unblock_user'
                                        : 'chat.block_user')
                                    .tr(),
                              ),
                              avatar: const Icon(Icons.block_rounded),
                              onSelected: (value) => _setBlocked(id, value),
                            ),
                            FilterChip(
                              selected: muted,
                              label: Text(
                                (muted ? 'chat.unmute_user' : 'chat.mute_user')
                                    .tr(),
                              ),
                              avatar: const Icon(
                                Icons.notifications_off_outlined,
                              ),
                              onSelected: (value) => _setMuted(id, value),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  String _initials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    return clean.substring(0, clean.length < 2 ? 1 : 2).toUpperCase();
  }
}
