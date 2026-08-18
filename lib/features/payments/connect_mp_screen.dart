import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../services/api_error.dart';
import 'payment_models.dart';
import 'payments_api.dart';

/// Pantalla donde un vendedor conecta su cuenta de Mercado Pago.
///
/// El OAuth se abre en el NAVEGADOR del sistema, no en un WebView dentro de
/// la app. Es deliberado: el usuario escribe ahí las credenciales de su
/// cuenta de Mercado Pago, y en un WebView propio no tiene forma de
/// verificar que la página es la real (ni ve la barra de direcciones ni el
/// candado). Además Mercado Pago bloquea los WebView embebidos en su login.
///
/// Al terminar, el navegador vuelve a la app por el deep link
/// `mercaditoum://payments/connected` (ver AndroidManifest.xml e Info.plist).
class ConnectMpScreen extends StatefulWidget {
  const ConnectMpScreen({super.key});

  @override
  State<ConnectMpScreen> createState() => _ConnectMpScreenState();
}

class _ConnectMpScreenState extends State<ConnectMpScreen>
    with WidgetsBindingObserver {
  VendorAccountStatus? _estado;
  String? _error;
  bool _abriendo = false;

  @override
  void initState() {
    super.initState();
    // Al volver del navegador la app se reanuda: es la señal para releer el
    // estado sin obligar a la persona a refrescar a mano.
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _abriendo) {
      _abriendo = false;
      _cargar();
    }
  }

  Future<void> _cargar() async {
    try {
      final estado = await PaymentsApi.getEstadoCuenta();
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _error = null;
      });
      // `getEstadoCuenta` solo lee el flag guardado. Comprobar contra Mercado
      // Pago que la autorización sigue viva es una segunda pregunta que puede
      // fallar sola (503 de una plataforma a medio configurar, red caída), y
      // ese fallo NO debe borrar lo que ya se pintó: la respuesta de arriba
      // sigue siendo la mejor que tenemos.
      final real = await PaymentsApi.estadoDeCobros();
      if (!mounted || real == EstadoCobros.desconocido) return;
      if (real.estaConectado != estado.connected) {
        setState(
          () => _estado = VendorAccountStatus(
            connected: real.estaConectado,
            canConnect: estado.canConnect,
            connectedAt: estado.connectedAt,
          ),
        );
      }
    } catch (e, s) {
      if (!mounted) return;
      setState(
        () => _error = mensajeDeError(
          e,
          fallback: 'payments_api.account_error'.tr(),
          stack: s,
        ),
      );
    }
  }

  Future<void> _conectar() async {
    setState(() => _error = null);
    try {
      final url = await PaymentsApi.getUrlConexion();
      _abriendo = true;
      final abierto = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!abierto) {
        _abriendo = false;
        if (!mounted) return;
        setState(() => _error = 'mp.browser_error'.tr());
      }
    } catch (e, s) {
      _abriendo = false;
      if (!mounted) return;
      setState(
        () => _error = mensajeDeError(
          e,
          fallback: 'payments_api.connect_error'.tr(),
          stack: s,
        ),
      );
    }
  }

  Future<void> _desconectar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('mp.disconnect_title'.tr()),
        content: Text('mp.disconnect_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Desconectar',
              style: TextStyle(color: ctx.colors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await PaymentsApi.desconectarCuenta();
      await _cargar();
    } catch (e, s) {
      if (!mounted) return;
      setState(
        () => _error = mensajeDeError(
          e,
          fallback: 'payments_api.disconnect_error'.tr(),
          stack: s,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('mp.title'.tr())),
      body: SafeArea(
        child: RefreshIndicator(onRefresh: _cargar, child: _cuerpo()),
      ),
    );
  }

  Widget _cuerpo() {
    if (_estado == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (_error != null) ...[
          _Aviso(texto: _error!, esError: true),
          const SizedBox(height: 16),
        ],
        if (_estado != null) ...[
          if (_estado!.connected)
            _TarjetaConectada(onDesconectar: _desconectar)
          else if (!_estado!.canConnect)
            _Aviso(texto: 'mp.verify_first'.tr(), esError: false)
          else
            _TarjetaDesconectada(onConectar: _conectar),
        ],
      ],
    );
  }
}

class _TarjetaConectada extends StatelessWidget {
  const _TarjetaConectada({required this.onDesconectar});

  final VoidCallback onDesconectar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.successBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: colors.success),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'mp.connected_title'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'mp.connected_body'.tr(),
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: onDesconectar,
          child: Text(
            'mp.disconnect_action'.tr(),
            style: TextStyle(color: colors.danger),
          ),
        ),
      ],
    );
  }
}

class _TarjetaDesconectada extends StatelessWidget {
  const _TarjetaDesconectada({required this.onConectar});

  final VoidCallback onConectar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'mp.pitch_title'.tr(),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'mp.pitch_body'.tr(),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 16),
              _Punto('mp.bullet_account'.tr()),
              _Punto('mp.bullet_fee'.tr()),
              _Punto('mp.bullet_disconnect'.tr()),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onConectar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('verification.connect_mp'.tr()),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'mp.browser_note'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
      ],
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 6, color: colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 13, color: colors.mutedStrong),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.esError});

  final String texto;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = esError ? colors.danger : colors.accent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            esError ? Icons.error_outline : Icons.info_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 13, height: 1.4, color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
