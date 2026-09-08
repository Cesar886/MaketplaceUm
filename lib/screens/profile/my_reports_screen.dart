import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<UserReport>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AuthProvider>().isLoggedIn
        ? ApiService.getMyReports()
        : Future<List<UserReport>>.value(const <UserReport>[]);
  }

  Future<void> _reload() async {
    if (!context.read<AuthProvider>().isLoggedIn) return;
    setState(() => _future = ApiService.getMyReports());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: Text('my_reports.title'.tr())),
      body: SafeArea(
        child: !auth.isLoggedIn
            ? _EmptyReportsState(
                icon: Icons.lock_outline_rounded,
                title: 'my_reports.no_session_title'.tr(),
                body: 'my_reports.no_session_body'.tr(),
              )
            : FutureBuilder<List<UserReport>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(onRetry: _reload);
                  }
                  final reports = snapshot.data ?? const <UserReport>[];
                  if (reports.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 96),
                          _EmptyReportsState(
                            icon: Icons.flag_outlined,
                            title: 'my_reports.empty_title'.tr(),
                            body: 'my_reports.empty_body'.tr(),
                          ),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                      itemCount: reports.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index == 0) return const _IntroCard();
                        return _ReportCard(report: reports[index - 1]);
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.accentTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.accentTintBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: context.colors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'my_reports.intro'.tr(),
              style: AppTypography.body(13.5, color: context.colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final UserReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final date = _formatDate(context, report.createdAt);
    final target = switch (report.targetType) {
      'user' => 'my_reports.target_user'.tr(),
      'product' => 'my_reports.target_product'.tr(),
      'wanted' => 'my_reports.target_wanted'.tr(),
      'chat' => 'my_reports.target_chat'.tr(),
      _ => 'my_reports.target_unknown'.tr(),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    target,
                    style: AppTypography.label(
                      15,
                      color: colors.ink,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusChip(status: report.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              report.reason,
              style: AppTypography.body(14, color: colors.ink),
            ),
            if (report.details.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                report.details,
                style: AppTypography.body(13, color: colors.muted),
              ),
            ],
            if (report.adminNote.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'my_reports.admin_note'.tr(
                    namedArgs: {'note': report.adminNote.trim()},
                  ),
                  style: AppTypography.body(13, color: colors.ink),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _MetaText(Icons.schedule_rounded, date),
                _MetaText(Icons.tag_rounded, report.id),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (status) {
      'reviewing' => Colors.orange.shade700,
      'resolved' => Colors.green.shade700,
      'dismissed' => colors.mutedStrong,
      _ => colors.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(switch (status) {
        'reviewing' => 'my_reports.status_reviewing'.tr(),
        'resolved' => 'my_reports.status_resolved'.tr(),
        'dismissed' => 'my_reports.status_dismissed'.tr(),
        _ => 'my_reports.status_received'.tr(),
      }, style: AppTypography.label(12, color: color, weight: FontWeight.w700)),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.colors.muted),
        const SizedBox(width: 4),
        Text(text, style: AppTypography.body(12, color: context.colors.muted)),
      ],
    );
  }
}

class _EmptyReportsState extends StatelessWidget {
  const _EmptyReportsState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: context.colors.muted),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.heading(18, color: context.colors.ink),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.body(14, color: context.colors.muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: context.colors.muted,
            ),
            const SizedBox(height: 18),
            Text(
              'my_reports.load_error'.tr(),
              textAlign: TextAlign.center,
              style: AppTypography.body(14, color: context.colors.muted),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('common.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(BuildContext context, String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  return DateFormat.yMMMd(context.locale.toLanguageTag()).add_Hm().format(date);
}
