import 'dart:async';

import 'package:flutter/material.dart';

/// Mixin que agrega auto-actualización periódica a cualquier State.
///
/// * Cada [refreshInterval] (default 30s) llama a [onAutoRefresh].
/// * También refresca cuando la app vuelve a primer plano.
/// * Se detiene automáticamente al hacer dispose.
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _refreshTimer;
  AppLifecycleListener? _lifecycleListener;

  /// Intervalo entre refrescos automáticos.
  Duration get refreshInterval => const Duration(seconds: 30);

  /// Lógica de actualización que debe implementar cada screen.
  Future<void> onAutoRefresh();

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () => onAutoRefresh(),
    );
    _refreshTimer = Timer.periodic(refreshInterval, (_) {
      if (mounted) onAutoRefresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _lifecycleListener?.dispose();
    super.dispose();
  }
}
