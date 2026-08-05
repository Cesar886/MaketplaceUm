import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/otp_input.dart';
import '../../widgets/static_mini_map.dart';
import 'account_created_screen.dart';

/// Pantalla única de verificación de cuenta para los tres tipos.
///
/// La verificación es 100% automática: el backend valida y resuelve sin que
/// intervenga ningún administrador. Estudiante y cuenta externa usan un
/// código de 6 dígitos (correo institucional / SMS); negocio se resuelve en
/// una sola llamada validando nombre, ubicación y link de red social.
///
/// Se abre desde dos lugares con el mismo comportamiento:
///  - durante el registro ([desdeRegistro] true, continúa a la pantalla de
///    cuenta creada y permite posponer);
///  - desde el perfil ([desdeRegistro] false, cierra devolviendo true si la
///    cuenta quedó verificada).
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    required this.tipo,
    this.desdeRegistro = false,
  });

  final AccountType tipo;
  final bool desdeRegistro;

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _enviando = false;
  String? _error;
  String? _campoConError;

  /// Código mostrado en pantalla cuando el backend corre sin proveedor de
  /// email/SMS configurado. Permite probar el flujo completo en desarrollo.
  String? _codigoDev;

  /// Cambia de la captura de datos al ingreso del código.
  bool _esperandoCodigo = false;
  String? _destinoCodigo;

  final _llaveOtp = GlobalKey<OtpInputState>();

  // Estudiante
  final _correoController = TextEditingController();
  final _matriculaController = TextEditingController();

  // Negocio
  final _nombreNegocioController = TextEditingController();
  final _linkController = TextEditingController();
  ll.LatLng? _ubicacion;

  // Externo
  final _telefonoController = TextEditingController();

  @override
  void dispose() {
    _correoController.dispose();
    _matriculaController.dispose();
    _nombreNegocioController.dispose();
    _linkController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  AuthProvider get _auth => context.read<AuthProvider>();

  // ─── Acciones ──────────────────────────────────────────────

  /// Envuelve una operación contra el backend: limpia el error anterior,
  /// bloquea el botón y traduce [VerificacionException] al mensaje que ya
  /// viene redactado desde el servidor.
  Future<void> _ejecutar(Future<void> Function() operacion) async {
    setState(() {
      _enviando = true;
      _error = null;
      _campoConError = null;
    });
    try {
      await operacion();
    } on VerificacionException catch (e) {
      if (!mounted) return;
      if (e.yaVerificado) {
        // La cuenta ya estaba verificada (p. ej. se verificó desde otro
        // dispositivo): no es un error que deba alarmar.
        await _auth.refrescarEstadoVerificacion();
        if (mounted) _terminar(verificado: true);
        return;
      }
      setState(() {
        _error = e.mensaje;
        _campoConError = e.campo;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No hay conexión con el servidor. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _solicitarCodigoEstudiante() {
    return _ejecutar(() async {
      final codigoDev = await _auth.solicitarVerificacionEstudiante(
        correoInstitucional: _correoController.text.trim(),
        matricula: _matriculaController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _esperandoCodigo = true;
        _destinoCodigo = _correoController.text.trim();
        _codigoDev = codigoDev;
      });
      _llaveOtp.currentState?.limpiar();
    });
  }

  Future<void> _solicitarCodigoExterno() {
    return _ejecutar(() async {
      final codigoDev = await _auth.solicitarVerificacionExterno(
        _telefonoController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _esperandoCodigo = true;
        _destinoCodigo = _telefonoController.text.trim();
        _codigoDev = codigoDev;
      });
      _llaveOtp.currentState?.limpiar();
    });
  }

  Future<void> _confirmarCodigo(String codigo) {
    return _ejecutar(() async {
      if (widget.tipo == AccountType.estudiante) {
        await _auth.confirmarVerificacionEstudiante(codigo);
      } else {
        await _auth.confirmarVerificacionExterno(codigo);
      }
      if (mounted) _terminar(verificado: true);
    });
  }

  Future<void> _verificarNegocio() {
    if (_ubicacion == null) {
      setState(() {
        _error = 'Coloca el pin de ubicación de tu negocio';
        _campoConError = 'ubicacion';
      });
      return Future.value();
    }
    return _ejecutar(() async {
      final verificado = await _auth.verificarNegocio(
        nombreNegocio: _nombreNegocioController.text.trim(),
        lat: _ubicacion!.latitude,
        lng: _ubicacion!.longitude,
        linkRedSocial: _linkController.text.trim(),
      );
      if (!mounted) return;
      if (verificado) {
        _terminar(verificado: true);
      } else {
        // Rechazo: el backend dice qué campo corregir y el usuario reintenta
        // desde la misma pantalla, sin volver a empezar.
        setState(() {
          _error = _auth.motivoRechazo ?? 'No pudimos verificar los datos de tu negocio.';
          _campoConError = _auth.campoRechazado;
        });
      }
    });
  }

  Future<void> _elegirUbicacion() async {
    final punto = await LocationPickerScreen.open(
      context,
      initialLat: _ubicacion?.latitude,
      initialLng: _ubicacion?.longitude,
      title: 'Ubicación de tu negocio',
    );
    if (punto != null && mounted) {
      setState(() {
        _ubicacion = punto;
        if (_campoConError == 'ubicacion') _campoConError = null;
      });
    }
  }

  void _terminar({required bool verificado}) {
    if (widget.desdeRegistro) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AccountCreatedScreen()),
      );
    } else {
      Navigator.of(context).pop(verificado);
    }
  }

  void _posponer() {
    if (widget.desdeRegistro) {
      _terminar(verificado: false);
    } else {
      Navigator.of(context).pop(false);
    }
  }

  // ─── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _esperandoCodigo ? 'Ingresa tu código' : _titulo,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                _esperandoCodigo
                    ? 'Enviamos un código de 6 dígitos a $_destinoCodigo. Vence en 10 minutos.'
                    : _descripcion,
                style: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              if (_error != null) ...[
                _CajaAviso(
                  mensaje: _error!,
                  color: AppColors.danger,
                  icono: Icons.error_outline_rounded,
                ),
                const SizedBox(height: 16),
              ],

              if (_codigoDev != null) ...[
                _CajaAviso(
                  mensaje:
                      'Modo desarrollo: el servidor no tiene configurado el '
                      'envío, tu código es $_codigoDev',
                  color: AppColors.gold,
                  icono: Icons.build_rounded,
                ),
                const SizedBox(height: 16),
              ],

              if (_esperandoCodigo) _buildIngresoCodigo() else _buildFormulario(),

              const SizedBox(height: 28),

              if (widget.desdeRegistro)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _enviando ? null : _posponer,
                    child: const Text('Hacerlo después'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _titulo => switch (widget.tipo) {
    AccountType.estudiante => 'Verifica que eres estudiante',
    AccountType.negocio => 'Verifica tu negocio',
    AccountType.particular => 'Verifica tu número',
  };

  String get _descripcion => switch (widget.tipo) {
    AccountType.estudiante =>
      'Te enviaremos un código a tu correo institucional. La verificación es '
          'automática, no hay que esperar a que nadie la revise.',
    AccountType.negocio =>
      'Con estos tres datos verificamos tu negocio al instante, sin revisión '
          'manual.',
    AccountType.particular =>
      'Te enviaremos un código por SMS. La verificación es automática.',
  };

  Widget _buildFormulario() => switch (widget.tipo) {
    AccountType.estudiante => _buildFormEstudiante(),
    AccountType.negocio => _buildFormNegocio(),
    AccountType.particular => _buildFormExterno(),
  };

  // ─── Ingreso del código (estudiante y externo) ─────────────

  Widget _buildIngresoCodigo() {
    return Column(
      children: [
        OtpInput(
          key: _llaveOtp,
          habilitado: !_enviando,
          onCompleto: _enviando ? (_) {} : _confirmarCodigo,
        ),
        const SizedBox(height: 20),
        if (_enviando) const CircularProgressIndicator(),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _enviando
              ? null
              : () {
                  setState(() {
                    _esperandoCodigo = false;
                    _codigoDev = null;
                    _error = null;
                  });
                },
          child: const Text('Cambiar el dato o reenviar código'),
        ),
      ],
    );
  }

  // ─── Formularios ───────────────────────────────────────────

  Widget _buildFormEstudiante() {
    return Column(
      children: [
        _CampoTexto(
          controller: _correoController,
          etiqueta: 'Correo institucional *',
          icono: Icons.alternate_email_rounded,
          tipoTeclado: TextInputType.emailAddress,
          ayuda: 'Ej. 1220326@alumno.um.edu.mx',
          conError: _campoConError == 'correo_institucional',
        ),
        const SizedBox(height: 14),
        _CampoTexto(
          controller: _matriculaController,
          etiqueta: 'Matrícula *',
          icono: Icons.badge_rounded,
          tipoTeclado: TextInputType.number,
          ayuda: 'Los 7 dígitos de tu correo institucional',
          conError: _campoConError == 'matricula',
        ),
        const SizedBox(height: 24),
        _BotonPrincipal(
          etiqueta: 'Enviar código',
          cargando: _enviando,
          onPressed: _solicitarCodigoEstudiante,
        ),
      ],
    );
  }

  Widget _buildFormExterno() {
    return Column(
      children: [
        _CampoTexto(
          controller: _telefonoController,
          etiqueta: 'Número de teléfono *',
          icono: Icons.phone_rounded,
          tipoTeclado: TextInputType.phone,
          ayuda: '10 dígitos, ej. 4431234567',
          conError: _campoConError == 'telefono',
        ),
        const SizedBox(height: 24),
        _BotonPrincipal(
          etiqueta: 'Enviar código por SMS',
          cargando: _enviando,
          onPressed: _solicitarCodigoExterno,
        ),
      ],
    );
  }

  Widget _buildFormNegocio() {
    final conErrorUbicacion = _campoConError == 'ubicacion';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CampoTexto(
          controller: _nombreNegocioController,
          etiqueta: 'Nombre del negocio *',
          icono: Icons.storefront_rounded,
          conError: _campoConError == 'nombre_negocio',
        ),
        const SizedBox(height: 18),

        Text(
          'Ubicación del negocio *',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: conErrorUbicacion ? AppColors.danger : context.colors.ink,
          ),
        ),
        const SizedBox(height: 8),
        if (_ubicacion != null) ...[
          StaticMiniMap(
            lat: _ubicacion!.latitude,
            lng: _ubicacion!.longitude,
            height: 130,
            showOpenInMapsButton: false,
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _enviando ? null : _elegirUbicacion,
          icon: const Icon(Icons.place_rounded),
          label: Text(
            _ubicacion == null ? 'Colocar pin en el mapa' : 'Cambiar ubicación',
          ),
        ),
        const SizedBox(height: 18),

        _CampoTexto(
          controller: _linkController,
          etiqueta: 'Link de Facebook, Instagram o Maps *',
          icono: Icons.link_rounded,
          tipoTeclado: TextInputType.url,
          ayuda: 'Un solo link. Comprobamos que la página exista.',
          conError: _campoConError == 'link_red_social',
        ),
        const SizedBox(height: 24),
        _BotonPrincipal(
          etiqueta: 'Verificar negocio',
          cargando: _enviando,
          onPressed: _verificarNegocio,
        ),
      ],
    );
  }
}

// ─── Widgets base compartidos ────────────────────────────────

class _CampoTexto extends StatelessWidget {
  const _CampoTexto({
    required this.controller,
    required this.etiqueta,
    required this.icono,
    this.tipoTeclado,
    this.ayuda,
    this.conError = false,
  });

  final TextEditingController controller;
  final String etiqueta;
  final IconData icono;
  final TextInputType? tipoTeclado;
  final String? ayuda;

  /// Resalta el campo que el backend señaló como causa del rechazo.
  final bool conError;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: tipoTeclado,
      decoration: InputDecoration(
        labelText: etiqueta,
        helperText: ayuda,
        prefixIcon: Icon(icono),
        enabledBorder: conError
            ? const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.danger, width: 1.6),
              )
            : null,
      ),
    );
  }
}

class _BotonPrincipal extends StatelessWidget {
  const _BotonPrincipal({
    required this.etiqueta,
    required this.cargando,
    required this.onPressed,
  });

  final String etiqueta;
  final bool cargando;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: cargando ? null : onPressed,
        child: cargando
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(etiqueta),
      ),
    );
  }
}

class _CajaAviso extends StatelessWidget {
  const _CajaAviso({
    required this.mensaje,
    required this.color,
    required this.icono,
  });

  final String mensaje;
  final Color color;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icono, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
