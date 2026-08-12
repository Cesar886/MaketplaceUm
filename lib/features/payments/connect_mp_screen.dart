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
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _error = mensajeDeError(
        e,
        fallback: 'No se pudo consultar tu cuenta de pagos.',
        stack: s,
      ));
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
        setState(() => _error = 'No se pudo abrir Mercado Pago en tu navegador.');
      }
    } catch (e, s) {
      _abriendo = false;
      if (!mounted) return;
      setState(() => _error = mensajeDeError(
        e,
        fallback: 'No se pudo iniciar la conexión con Mercado Pago.',
        stack: s,
      ));
    }
  }

  Future<void> _desconectar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Desconectar Mercado Pago?'),
        content: const Text(
          'Dejarás de recibir pagos por la app hasta que vuelvas a conectarla. '
          'Los pagos que ya recibiste no se ven afectados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
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
      setState(() => _error = mensajeDeError(
        e,
        fallback: 'No se pudo desconectar tu cuenta.',
        stack: s,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recibir pagos')),
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
            const _Aviso(
              texto:
                  'Para recibir pagos necesitas una cuenta verificada de negocio '
                  'o de estudiante. Verifica tu cuenta desde tu perfil.',
              esError: false,
            )
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
                      'Tu cuenta está conectada',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ya puedes recibir pagos por la app. El dinero llega '
                      'directo a tu cuenta de Mercado Pago.',
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
            'Desconectar cuenta',
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
                'Cobra dentro de Mercadito UM',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Conecta tu cuenta de Mercado Pago para que la gente pueda '
                'pagarte con tarjeta desde la app. El dinero llega directo a '
                'tu cuenta, sin pasar por nosotros.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 16),
              const _Punto('Necesitas una cuenta de Mercado Pago (es gratis).'),
              const _Punto('Se te cobra una comisión por venta.'),
              const _Punto('Puedes desconectarla cuando quieras.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onConectar,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Conectar Mercado Pago'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Se abrirá tu navegador para que inicies sesión en Mercado Pago.',
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
