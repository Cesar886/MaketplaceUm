import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models.dart';
import '../../services/api_service.dart';

class HighlightPlansScreen extends StatefulWidget {
  const HighlightPlansScreen({super.key});

  @override
  State<HighlightPlansScreen> createState() => _HighlightPlansScreenState();
}

class _HighlightPlansScreenState extends State<HighlightPlansScreen> {
  List<HighlightPlan>? _plans;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await ApiService.getHighlightPlans();
      if (!mounted) return;
      setState(() => _plans = plans);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'plans.load_error'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('profile.highlight_plans'.tr())),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: context.colors.muted)),
      );
    }
    if (_plans == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_plans!.isEmpty) {
      return Center(
        child: Text(
          'plans.empty'.tr(),
          style: TextStyle(color: context.colors.muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: _plans!.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final plan = _plans![index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.star_rounded, color: context.colors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'plans.days_description'.tr(
                        namedArgs: {
                          'days': '${plan.days}',
                          'description': plan.description,
                        },
                      ),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                plan.price,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.colors.accent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
