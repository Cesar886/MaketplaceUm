import 'dart:async';

import 'package:flutter/material.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';

typedef PublicationLimits = ({int active, int daily, int days});

PublicationLimits publicationLimitsFor(
  AuthProvider auth, {
  required bool wanted,
}) {
  if (auth.accountType == AccountType.negocio) {
    if (auth.isVerified) {
      return wanted
          ? (active: 10, daily: 3, days: 60)
          : (active: 40, daily: 8, days: 60);
    }
    return wanted
        ? (active: 4, daily: 1, days: 20)
        : (active: 15, daily: 3, days: 20);
  }
  if (auth.accountType == AccountType.estudiante) {
    if (auth.isVerified) {
      return wanted
          ? (active: 10, daily: 3, days: 60)
          : (active: 30, daily: 6, days: 60);
    }
    return wanted
        ? (active: 5, daily: 2, days: 30)
        : (active: 10, daily: 3, days: 30);
  }
  return wanted
      ? (active: 3, daily: 1, days: 30)
      : (active: 8, daily: 2, days: 30);
}

class PublicationLimitNotice extends StatefulWidget {
  const PublicationLimitNotice({
    super.key,
    required this.auth,
    required this.wanted,
  });

  final AuthProvider auth;
  final bool wanted;

  @override
  State<PublicationLimitNotice> createState() => _PublicationLimitNoticeState();
}

class _PublicationLimitNoticeState extends State<PublicationLimitNotice>
    with WidgetsBindingObserver {
  PublicationLimits? _serverLimits;
  Timer? _refreshTimer;
  bool _loadingLimits = false;

  PublicationLimits get _fallbackLimits {
    return publicationLimitsFor(widget.auth, wanted: widget.wanted);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLimits();
    // Solo existe mientras el formulario de publicación está visible. Así un
    // cambio administrativo aparece aun si el usuario dejó la pantalla
    // abierta, sin convertirlo en tráfico permanente del resto de la app.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadLimits(),
    );
  }

  @override
  void didUpdateWidget(covariant PublicationLimitNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wanted != widget.wanted ||
        oldWidget.auth.backendSellerId != widget.auth.backendSellerId) {
      _loadLimits();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadLimits();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadLimits() async {
    if (_loadingLimits) return;
    _loadingLimits = true;
    try {
      final policy = await ApiService.getPublicationPolicy();
      final activeKey = widget.wanted ? 'wantedActive' : 'productsActive';
      final dailyKey = widget.wanted ? 'wantedDaily' : 'productsDaily';
      final active = policy[activeKey];
      final daily = policy[dailyKey];
      final days = policy['durationDays'];
      if (active is! int || daily is! int || days is! int) {
        throw const FormatException('Política de publicación inválida');
      }
      if (!mounted) return;
      setState(() {
        _serverLimits = (active: active, daily: daily, days: days);
      });
    } catch (_) {
      // El aviso no debe bloquear el formulario si no hay conexión. En ese
      // caso conserva los defaults conocidos; el backend sigue siendo quien
      // aplica el límite real al guardar.
    } finally {
      _loadingLimits = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final limits = _serverLimits ?? _fallbackLimits;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: .9),
            Theme.of(context).colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tu cuenta permite ${limits.active} publicaciones activas, ${limits.daily} nuevas al día y duran ${limits.days} días.',
            ),
          ),
        ],
      ),
    );
  }
}
