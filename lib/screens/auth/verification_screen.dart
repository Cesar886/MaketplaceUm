import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../constants/carreras_um.dart';
import '../../constants/dominios_um.dart';
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

  /// Código tal como va quedando en [OtpInput]. Solo sirve para habilitar el
  /// botón "Verificar código" (y para reintentar con el mismo código sin
  /// tener que reescribirlo tras un fallo).
  String _codigoIngresado = '';

  /// Segundos que faltan para poder reenviar. Evita que el usuario queme los
  /// envíos permitidos en la ventana antipam del backend a base de toques.
  int _segundosReenvio = 0;
  Timer? _timerReenvio;

  static const _cooldownReenvioSegundos = 60;

  final _llaveOtp = GlobalKey<OtpInputState>();

  // Estudiante / personal
  /// Guarda SOLO lo que va antes del arroba (matrícula o usuario). El correo
  /// completo se arma en [_validarCorreo] concatenando el dominio elegido.
  final _matriculaController = TextEditingController();
  final _focoMatricula = FocusNode();

  /// Dominio elegido en el desplegable. Null = todavía sin elegir, que es lo
  /// que mantiene el campo de texto bloqueado: hasta saber el dominio no se
  /// sabe qué formato exigirle a lo que se teclee.
  DominioUM? _dominio;

  /// Solo se llena cuando el usuario elige una opción exacta de [carrerasUM]
  /// (ver [_CampoCarrera]); nunca contiene texto libre, así el botón de
  /// enviar puede usar "es null" para saber si falta seleccionar.
  String? _carreraSeleccionada;

  // Negocio
  final _nombreNegocioController = TextEditingController();
  final _linkController = TextEditingController();
  ll.LatLng? _ubicacion;

  // Externo
  final _telefonoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Validación al perder el foco: mientras el usuario escribe no tiene
    // sentido marcarle en rojo un correo que aún está a medias.
    _focoMatricula.addListener(() {
      // `mounted` porque FocusNode.dispose() puede notificar al desenfocar, y
      // el setState de _validarCorreo reventaría sobre un State ya desmontado.
      if (mounted && !_focoMatricula.hasFocus) _validarCorreo();
    });
  }

  @override
  void dispose() {
    _timerReenvio?.cancel();
    _matriculaController.dispose();
    _focoMatricula.dispose();
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
      if (e.sesionInvalidada) {
        // El cierre de sesión y el salto al login los hace el manejador
        // central de ApiService (ver main.dart): aquí solo se evita pintar un
        // error en una pantalla que ya está siendo desmontada.
        return;
      }
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
      // 429: el backend ya dijo cuántos minutos faltan para poder pedir otro
      // código. Se respeta ese número en vez del cooldown local, que sería
      // más corto y solo produciría otro 429.
      if (e.demasiadosIntentos && e.puedeReintentarEn != null) {
        _iniciarCooldownReenvio(e.puedeReintentarEn! * 60);
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'No hay conexión con el servidor. Inténtalo de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _iniciarCooldownReenvio(int segundos) {
    _timerReenvio?.cancel();
    setState(() => _segundosReenvio = segundos);
    _timerReenvio = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _segundosReenvio--);
      if (_segundosReenvio <= 0) timer.cancel();
    });
  }

  /// Reenvía al mismo destino, sin sacar al usuario del paso del código.
  Future<void> _reenviarCodigo() {
    return widget.tipo == AccountType.estudiante
        ? _solicitarCodigoEstudiante()
        : _solicitarCodigoExterno();
  }

  /// Vuelve al formulario para corregir el correo/teléfono. El cooldown se
  /// cancela porque el destino va a cambiar.
  void _volverAlFormulario() {
    _timerReenvio?.cancel();
    setState(() {
      _esperandoCodigo = false;
      _codigoDev = null;
      _error = null;
      _campoConError = null;
      _codigoIngresado = '';
      _segundosReenvio = 0;
    });
  }

  /// Concatena lo tecleado con el dominio elegido y valida el correo
  /// COMPLETO, normalizando igual que el backend (trim + minúsculas).
  /// Devuelve el correo listo para enviar, o null si no es válido — en cuyo
  /// caso deja el campo marcado con el mensaje correspondiente.
  ///
  /// Sin dominio elegido no hay nada que validar: no se sabe qué formato
  /// exigir, así que devuelve null sin marcar el campo de texto (el aviso que
  /// toca en ese caso es el del desplegable, ver [_solicitarCodigoEstudiante]).
  ///
  /// [avisarSiVacio] distingue los dos momentos en que se llama: al perder el
  /// foco un campo vacío no merece un aviso en rojo; al pulsar "Enviar
  /// código", sí.
  String? _validarCorreo({bool avisarSiVacio = false}) {
    final dominio = _dominio;
    if (dominio == null) return null;

    final usuario = _matriculaController.text.trim().toLowerCase();
    final correo = '$usuario${dominio.sufijo}';
    final valido = dominio.formatoCorreo.hasMatch(correo);

    if (!valido && usuario.isEmpty && !avisarSiVacio) return null;

    setState(() {
      if (valido) {
        // Solo se limpia el aviso de formato: un error que vino del backend
        // ("ese correo ya está registrado") sigue siendo cierto y debe
        // seguir a la vista hasta el siguiente intento.
        if (_error == dominio.mensajeInvalido) {
          _error = null;
          _campoConError = null;
        }
      } else {
        _campoConError = 'correo_institucional';
        _error = dominio.mensajeInvalido;
      }
    });
    return valido ? correo : null;
  }

  /// Reinicia lo que dependía del dominio anterior. Cambiar de alumno a
  /// personal (o al revés) cambia el formato exigido y si aplica la carrera,
  /// así que lo ya tecleado deja de tener sentido.
  void _cambiarDominio(DominioUM? nuevo) {
    if (nuevo == _dominio) return;
    setState(() {
      _dominio = nuevo;
      _matriculaController.clear();
      // La carrera no aplica al personal; y si vuelve a alumno, la que
      // hubiera elegido antes ya no está a la vista, así que se vuelve a
      // pedir en vez de mandar una selección invisible.
      _carreraSeleccionada = null;
      _error = null;
      _campoConError = null;
    });
  }

  Future<void> _solicitarCodigoEstudiante() {
    // Sin dominio no hay correo que armar: es el primer aviso que toca.
    final dominio = _dominio;
    if (dominio == null) {
      setState(() {
        _campoConError = 'tipo';
        _error = 'Selecciona tu dominio';
      });
      return Future.value();
    }

    final correo = _validarCorreo(avisarSiVacio: true);

    // La carrera solo aplica al alumno, y debe salir de la lista: no se
    // acepta texto libre que no coincida exactamente con una opción de
    // [carrerasUM], para no ensuciar la base con variantes escritas a mano.
    final carrera = _carreraSeleccionada;
    final faltaCarrera = dominio.pideCarrera && carrera == null;
    // Solo se pinta el error de carrera si el correo ya es válido: no tiene
    // sentido pisar el aviso de _validarCorreo con este.
    if (correo != null && faltaCarrera) {
      setState(() {
        _campoConError = 'carrera';
        _error = 'Selecciona tu carrera de la lista';
      });
    }
    if (correo == null || faltaCarrera) return Future.value();
    return _ejecutar(() async {
      // La matrícula va embebida en el correo (los 7 dígitos antes del
      // arroba); el backend la extrae y la guarda. El tipo va explícito para
      // que el servidor no tenga que deducirlo del dominio.
      final codigoDev = await _auth.solicitarVerificacionEstudiante(
        correoInstitucional: correo,
        tipo: dominio.tipo,
        carrera: carrera,
      );
      if (!mounted) return;
      setState(() {
        _esperandoCodigo = true;
        _destinoCodigo = correo;
        _codigoDev = codigoDev;
        _codigoIngresado = '';
      });
      _llaveOtp.currentState?.limpiar();
      _iniciarCooldownReenvio(_cooldownReenvioSegundos);
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
        _codigoIngresado = '';
      });
      _llaveOtp.currentState?.limpiar();
      _iniciarCooldownReenvio(_cooldownReenvioSegundos);
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
          _error =
              _auth.motivoRechazo ??
              'No pudimos verificar los datos de tu negocio.';
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

              // En el paso del código el error se pinta bajo las casillas
              // (ver _buildIngresoCodigo), que es donde el usuario está
              // mirando; duplicarlo arriba solo empuja el contenido.
              if (_error != null && !_esperandoCodigo) ...[
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
                  color: context.colors.gold,
                  icono: Icons.build_rounded,
                ),
                const SizedBox(height: 16),
              ],

              if (_esperandoCodigo)
                _buildIngresoCodigo()
              else
                _buildFormulario(),

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

  // Copy deliberadamente neutro: la misma pantalla sirve a alumnos y a
  // personal de la universidad, y quien lo distingue es el dominio elegido,
  // no un texto que haya que mantener en dos versiones.
  String get _titulo => switch (widget.tipo) {
    AccountType.estudiante => 'Verifica tu cuenta',
    AccountType.negocio => 'Verifica tu negocio',
    AccountType.particular => 'Verifica tu número',
  };

  String get _descripcion => switch (widget.tipo) {
    AccountType.estudiante =>
      'Te enviaremos un código a tu correo institucional.',
    AccountType.negocio => ' Verificamos tu negocio.',
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
    final esEstudiante = widget.tipo == AccountType.estudiante;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // El destino sigue a la vista pero bloqueado: el usuario comprueba a
        // qué correo/teléfono se envió sin poder dejarlo a medias mientras el
        // código de ese destino sigue vigente. Para cambiarlo hay que volver
        // al formulario, que es lo que invalida el paso.
        _CampoTexto(
          controller: esEstudiante ? _matriculaController : _telefonoController,
          etiqueta: esEstudiante
              ? (_dominio?.etiquetaCampo ?? 'Correo institucional')
              : 'Número de teléfono',
          icono: esEstudiante ? Icons.badge_rounded : Icons.phone_rounded,
          // Bloqueado pero con el sufijo puesto: se sigue leyendo como el
          // correo completo al que se mandó el código.
          sufijo: esEstudiante ? _dominio?.sufijo : null,
          habilitado: false,
        ),
        const SizedBox(height: 22),

        OtpInput(
          key: _llaveOtp,
          habilitado: !_enviando,
          onCambio: (codigo) => setState(() => _codigoIngresado = codigo),
          onCompleto: _enviando ? (_) {} : _confirmarCodigo,
        ),

        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const SizedBox(height: 22),
        _BotonPrincipal(
          etiqueta: 'Verificar código',
          cargando: _enviando,
          // Deshabilitado hasta tener las 6 casillas: un código a medias solo
          // consume uno de los intentos que cuenta el backend.
          onPressed: _codigoIngresado.length == 6
              ? () => _confirmarCodigo(_codigoIngresado)
              : null,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: (_enviando || _segundosReenvio > 0)
              ? null
              : _reenviarCodigo,
          child: Text(
            _segundosReenvio > 0
                ? '¿No te llegó? Reenviar en ${_segundosReenvio}s'
                : '¿No te llegó? Reenviar código',
          ),
        ),
        TextButton(
          onPressed: _enviando ? null : _volverAlFormulario,
          child: Text(esEstudiante ? 'Cambiar el correo' : 'Cambiar el número'),
        ),
      ],
    );
  }

  // ─── Formularios ───────────────────────────────────────────

  Widget _buildFormEstudiante() {
    return Column(
      children: [
        _CampoCorreoInstitucional(
          controller: _matriculaController,
          focusNode: _focoMatricula,
          dominio: _dominio,
          onDominioCambiado: _cambiarDominio,
          conError: _campoConError == 'correo_institucional',
          conErrorDominio: _campoConError == 'tipo',
          // Al corregir lo tecleado se limpia el aviso en el momento, sin
          // esperar a que el campo pierda el foco.
          onChanged: (_) {
            if (_campoConError == 'correo_institucional') _validarCorreo();
          },
        ),

        // La carrera solo se le pide al alumno: para el personal el campo no
        // aplica y desaparece por completo, sin dejar hueco.
        if (_dominio?.pideCarrera ?? false) ...[
          const SizedBox(height: 18),
          _CampoCarrera(
            // Al pasar a personal el campo se quita del árbol por completo
            // (el `if` de arriba), así que volver a alumno reconstruye el
            // Autocomplete vacío sin conservar el texto del intento anterior.
            key: const ValueKey('carrera'),
            valorInicial: _carreraSeleccionada,
            conError: _campoConError == 'carrera',
            onSeleccionada: (carrera) {
              setState(() {
                _carreraSeleccionada = carrera;
                if (_campoConError == 'carrera') {
                  _campoConError = null;
                  _error = null;
                }
              });
            },
          ),
        ],

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
    this.sufijo,
    this.conError = false,
    this.habilitado = true,
  });

  final TextEditingController controller;
  final String etiqueta;
  final IconData icono;
  final TextInputType? tipoTeclado;
  final String? ayuda;

  /// Texto fijo pegado al final del campo (ej. el dominio institucional).
  /// No forma parte del valor del controller ni es editable.
  final String? sufijo;

  /// Resalta el campo que el backend señaló como causa del rechazo.
  final bool conError;

  /// En false el campo queda a la vista pero de solo lectura y atenuado.
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: habilitado,
      keyboardType: tipoTeclado,
      decoration: InputDecoration(
        labelText: etiqueta,
        helperText: ayuda,
        prefixIcon: Icon(icono),
        suffixText: sufijo,
        // Sin esto Flutter oculta el sufijo mientras el campo está vacío y sin
        // foco (lo tapa la etiqueta en línea), justo cuando más falta hace
        // ver que el dominio ya viene puesto.
        floatingLabelBehavior: sufijo == null
            ? null
            : FloatingLabelBehavior.always,
        enabledBorder: conError
            ? const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.danger, width: 1.6),
              )
            : null,
      ),
    );
  }
}

/// Campo de correo institucional: usuario + selector de dominio dentro de un
/// MISMO recuadro, con un divisor sutil entre las dos mitades.
///
/// El desplegable ocupa el lugar exacto donde antes iba el sufijo fijo, así
/// que se sigue leyendo como un solo correo. Mientras no haya dominio elegido
/// el campo de texto está bloqueado: hasta saber si es alumno o personal no se
/// sabe qué formato exigirle (7 dígitos vs. nombre.apellido).
class _CampoCorreoInstitucional extends StatefulWidget {
  const _CampoCorreoInstitucional({
    required this.controller,
    required this.focusNode,
    required this.dominio,
    required this.onDominioCambiado,
    required this.conError,
    required this.conErrorDominio,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final DominioUM? dominio;
  final ValueChanged<DominioUM?> onDominioCambiado;

  /// Resalta la mitad del texto (formato inválido).
  final bool conError;

  /// Resalta el recuadro por no haber elegido dominio todavía.
  final bool conErrorDominio;

  final ValueChanged<String>? onChanged;

  @override
  State<_CampoCorreoInstitucional> createState() =>
      _CampoCorreoInstitucionalState();
}

class _CampoCorreoInstitucionalState extends State<_CampoCorreoInstitucional> {
  @override
  void initState() {
    super.initState();
    // InputDecorator no sabe solo cuándo el TextField de adentro tiene el
    // foco: se le pasa a mano, y para eso hay que repintar en cada cambio.
    widget.focusNode.addListener(_repintar);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_repintar);
    super.dispose();
  }

  void _repintar() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dominio = widget.dominio;
    final habilitado = dominio != null;
    final resaltado = widget.conError || widget.conErrorDominio;

    final bordeError = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
    );

    return InputDecorator(
      isFocused: widget.focusNode.hasFocus,
      decoration: InputDecoration(
        labelText: '${dominio?.etiquetaCampo ?? 'Correo institucional'} *',
        prefixIcon: const Icon(Icons.badge_rounded),
        // El sufijo/desplegable ya está a la vista aunque el campo esté
        // vacío, así que la etiqueta no debe taparlo bajando a la línea.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        // El contenido lo compone la Row de abajo; sin esto el padding por
        // defecto descuadra el divisor respecto al borde.
        contentPadding: const EdgeInsets.only(right: 6),
        enabledBorder: resaltado ? bordeError : null,
        focusedBorder: resaltado ? bordeError : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: habilitado,
              keyboardType: dominio?.tipoTeclado,
              onChanged: widget.onChanged,
              // El formato se filtra al teclear según el dominio: así el
              // usuario no llega siquiera a formar un correo inválido.
              inputFormatters: [
                if (dominio == DominioUM.alumno) ...[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(dominio!.largoMaximo),
                ] else if (dominio == DominioUM.personal)
                  // Los dígitos entran a propósito: tanto [formatoCorreo]
                  // como el backend aceptan nombre.apellido2, y filtrarlos
                  // aquí dejaba a ese empleado sin poder teclear su usuario.
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9.]')),
              ],
              decoration: InputDecoration.collapsed(
                hintText: habilitado ? null : 'Elige tu dominio →',
                hintStyle: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: context.colors.muted.withValues(alpha: 0.28),
          ),
          _SelectorDominio(
            valor: dominio,
            onCambiado: widget.onDominioCambiado,
          ),
        ],
      ),
    );
  }
}

/// Desplegable del dominio, sin subrayado ni caja propia: hereda el recuadro
/// del campo que lo contiene para que las dos mitades se lean como una sola.
class _SelectorDominio extends StatelessWidget {
  const _SelectorDominio({required this.valor, required this.onCambiado});

  final DominioUM? valor;
  final ValueChanged<DominioUM?> onCambiado;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<DominioUM>(
        value: valor,
        isDense: true,
        borderRadius: BorderRadius.circular(12),
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 20,
          color: context.colors.muted,
        ),
        hint: Text(
          'Seleccionar',
          style: TextStyle(
            color: context.colors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Cerrado se muestra el dominio literal completo, que es el punto:
        // el usuario tiene que poder leer el correo tal cual quedará.
        selectedItemBuilder: (_) => [
          for (final d in DominioUM.values)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                d.sufijo,
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
        items: [
          for (final d in DominioUM.values)
            DropdownMenuItem(
              value: d,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(d.emoji, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Text(
                    d.sufijo,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
        onChanged: onCambiado,
      ),
    );
  }
}

/// Autocomplete de carrera: solo acepta valores exactos de [carrerasUM].
/// Cualquier texto que no coincida deja `onSeleccionada(null)`, así el
/// formulario no puede enviarse con una carrera inventada o a medio
/// escribir — mantiene los datos consistentes con la lista fija.
class _CampoCarrera extends StatefulWidget {
  const _CampoCarrera({
    super.key,
    required this.onSeleccionada,
    required this.conError,
    this.valorInicial,
  });

  final ValueChanged<String?> onSeleccionada;
  final bool conError;
  final String? valorInicial;

  @override
  State<_CampoCarrera> createState() => _CampoCarreraState();
}

class _CampoCarreraState extends State<_CampoCarrera> {
  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: widget.valorInicial ?? ''),
      optionsBuilder: (TextEditingValue value) {
        if (value.text.isEmpty) return const Iterable<String>.empty();
        final consulta = normalizarBusquedaCarrera(value.text);
        return carrerasUM.where(
          (carrera) => normalizarBusquedaCarrera(carrera).contains(consulta),
        );
      },
      onSelected: widget.onSeleccionada,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Carrera *',
            prefixIcon: const Icon(Icons.school_rounded),
            enabledBorder: widget.conError
                ? const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.danger, width: 1.6),
                  )
                : null,
          ),
          onChanged: (texto) {
            // Cualquier edición invalida la selección previa: solo vuelve a
            // ser válida si el usuario elige de nuevo una opción de la lista
            // (ver onSelected), nunca por coincidir el texto "a ojo".
            widget.onSeleccionada(null);
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opcion = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(opcion),
                    onTap: () => onSelected(opcion),
                  );
                },
              ),
            ),
          ),
        );
      },
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

  /// null deshabilita el botón (además del estado [cargando]).
  final VoidCallback? onPressed;

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
