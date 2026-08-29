import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../constants/carreras_um.dart';
import '../../constants/dominios_um.dart';
import '../../models.dart';
import '../../models/verification_requirement.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/otp_input.dart';
import '../../widgets/static_mini_map.dart';
import '../../widgets/verification_checklist.dart';
import '../../features/payments/connect_mp_screen.dart';
import '../../features/payments/mercado_pago_flag.dart';
import '../my_listings_screen.dart';
import '../profile/edit_profile_screen.dart';
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

  /// El código ya se confirmó y lo ÚNICO que falta para verificarse es
  /// conectar la cuenta de cobros. Cambia el paso del código por el de
  /// conectar: volver a pedir un código que ya se usó no tendría sentido.
  bool _faltaMercadoPago = false;

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

  /// Dominio detectado automáticamente a partir de lo tecleado (ver
  /// [_detectarDominio]). Null = todavía ambiguo (menos de 3 caracteres, o
  /// ninguno decisivo aún), que es lo que impide validar o enviar: hasta
  /// saber el dominio no se sabe qué formato exigirle a lo que se teclee.
  ///
  /// El dominio NUNCA se muestra en la UI (ni en el input ni en un
  /// desplegable): solo se usa internamente para armar el correo completo al
  /// enviar, por seguridad (no revelar el formato de los correos
  /// institucionales).
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
    // El dominio se re-evalúa en cada tecla, no solo al perder el foco: es lo
    // que permite que el formato exigido (y el campo de carrera) cambien en
    // vivo mientras la persona escribe.
    _matriculaController.addListener(_actualizarDominioDetectado);
    _retomarDondeQuedo();
  }

  /// Si la persona ya confirmó su código en una sesión anterior y solo le
  /// falta conectar la cuenta de cobros, se entra directo a ese paso.
  ///
  /// Sin esto, quien cerró la app en mitad del trámite vuelve a la pantalla
  /// de pedir un correo y un código que ya confirmó — y como el backend ya no
  /// se lo va a volver a pedir, se queda dando vueltas sin entender qué pasa.
  Future<void> _retomarDondeQuedo() async {
    // El refresco va ANTES de cualquier corte por tipo de cuenta: el checklist
    // se pinta en los tres flujos, y si el negocio saliera de aquí sin releer
    // el estado vería la última lista conocida (o ninguna, recién instalada la
    // app) en vez de sus requisitos reales.
    await _auth.refrescarEstadoVerificacion();
    if (!mounted) return;

    // El flujo de negocio ya pinta su fila de conectar dentro del formulario,
    // con los datos del negocio que hay que conservar a la vista.
    if (widget.tipo == AccountType.negocio) return;

    // TODO: Mercado Pago pendiente para próxima actualización - no eliminar,
    // solo quitar este corte cuando esté listo. Mientras tanto el paso de
    // "conectar cuenta de cobros" nunca se activa desde el frontend (ver
    // kMercadoPagoHabilitado).
    if (!kMercadoPagoHabilitado) return;
    if (!_auth.soloFaltaConectarCobros) return;
    setState(() {
      _faltaMercadoPago = true;
      _campoConError = 'mercadopago';
      _error = _auth.motivoRechazo;
    });
  }

  @override
  void dispose() {
    _timerReenvio?.cancel();
    _matriculaController.removeListener(_actualizarDominioDetectado);
    _matriculaController.dispose();
    _focoMatricula.dispose();
    _nombreNegocioController.dispose();
    _linkController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  AuthProvider get _auth => context.read<AuthProvider>();

  /// Los requisitos que tiene sentido enseñarle a la persona ahora mismo.
  ///
  /// Con Mercado Pago deshabilitado, el backend da por cumplida la "Cuenta de
  /// cobros" (ver `validation/requisitosVerificacion.js`) porque nadie puede
  /// conectar una cuenta desde una app que tiene la integración oculta. Aquí
  /// se quita de la lista en vez de pintarla con ✓: una palomita en algo que
  /// la persona nunca hizo —y que no puede hacer— es una mentira pequeña que
  /// sale cara cuando Mercado Pago vuelva y el requisito reaparezca sin
  /// explicación.
  ///
  /// TODO: Mercado Pago pendiente para próxima actualización - no eliminar,
  /// solo quitar este filtro cuando kMercadoPagoHabilitado sea true.
  List<VerificationRequirement> _requisitosVisibles(
    List<VerificationRequirement> todos,
  ) {
    if (kMercadoPagoHabilitado) return todos;
    return todos.where((r) => r.accion != 'conectar_mercadopago').toList();
  }

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
      setState(() => _error = 'errors.no_connection'.tr());
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

  /// Detecta el dominio (alumno/personal) a partir de lo tecleado, sin
  /// mostrarlo nunca en la UI.
  ///
  /// Los primeros 2 caracteres (posiciones 0 y 1) no son determinantes y se
  /// ignoran. A partir de la posición 2 en adelante se evalúa cada carácter:
  /// el primero que sea un dígito asigna alumno; el primero que sea una letra
  /// asigna personal. Un carácter que no sea ni dígito ni letra (p. ej. un
  /// punto) no decide nada y se sigue evaluando el siguiente.
  ///
  /// Devuelve null mientras la información siga siendo ambigua (menos de 3
  /// caracteres, o ningún carácter decisivo todavía).
  DominioUM? _detectarDominio(String texto) {
    for (var i = 2; i < texto.length; i++) {
      final c = texto[i];
      if (RegExp(r'[0-9]').hasMatch(c)) return DominioUM.alumno;
      if (RegExp(r'[a-zA-Z]').hasMatch(c)) return DominioUM.personal;
    }
    return null;
  }

  /// Reevalúa el dominio en cada cambio del campo de texto. Se puede
  /// reevaluar en cualquier momento: si el usuario borra y reescribe, el
  /// dominio detectado puede cambiar (o volver a quedar ambiguo).
  void _actualizarDominioDetectado() {
    final nuevo = _detectarDominio(_matriculaController.text);
    if (nuevo == _dominio) return;
    setState(() {
      _dominio = nuevo;
      // La carrera no aplica al personal; y si vuelve a alumno, la que
      // hubiera elegido antes ya no está a la vista, así que se vuelve a
      // pedir en vez de mandar una selección invisible.
      _carreraSeleccionada = null;
      if (_campoConError == 'correo_institucional' ||
          _campoConError == 'tipo') {
        _error = null;
        _campoConError = null;
      }
    });
  }

  Future<void> _solicitarCodigoEstudiante() {
    // Sin dominio detectado no hay correo que armar: con menos de 3
    // caracteres (o ninguno decisivo aún) el aviso es simplemente que falta
    // completar el campo, sin insinuar que hay un dominio por detectar.
    final dominio = _dominio;
    if (dominio == null) {
      setState(() {
        _campoConError = 'correo_institucional';
        _error = 'validation.email_required'.tr();
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
        _error = 'validation.major_required'.tr();
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

  /// Confirma el código. Si el código era correcto pero falta conectar la
  /// cuenta de cobros, NO se sale de la pantalla: se pasa al paso de conectar,
  /// que es lo único que queda por hacer.
  Future<void> _confirmarCodigo(String codigo) {
    return _ejecutar(() async {
      final verificado = widget.tipo == AccountType.estudiante
          ? await _auth.confirmarVerificacionEstudiante(codigo)
          : await _auth.confirmarVerificacionExterno(codigo);
      if (!mounted) return;
      if (verificado) {
        _terminar(verificado: true);
        return;
      }
      // TODO: Mercado Pago pendiente para próxima actualización - no
      // eliminar, solo descomentar `_faltaMercadoPago = true` cuando esté
      // listo. Mientras tanto no se ofrece el paso de conectar cobros.
      setState(() {
        // _faltaMercadoPago = true;
        _error =
            _auth.motivoRechazo ?? 'verification.connect_mp_to_finish'.tr();
        _campoConError = _auth.campoRechazado;
      });
    });
  }

  /// Reintenta el cierre tras volver de conectar Mercado Pago.
  ///
  /// Va sin código a propósito: la identidad ya quedó probada en el intento
  /// anterior y el backend lo sabe (ver `identidad_confirmada_en`). Pedir otro
  /// código aquí sería absurdo — el anterior ya expiró mientras la persona
  /// estaba en el navegador de Mercado Pago, que es exactamente el bucle que
  /// hace que la gente abandone.
  Future<void> _reintentarTrasConectar() {
    return _ejecutar(() async {
      final verificado = widget.tipo == AccountType.estudiante
          ? await _auth.confirmarVerificacionEstudiante('')
          : await _auth.confirmarVerificacionExterno('');
      if (!mounted) return;
      if (verificado) {
        _terminar(verificado: true);
        return;
      }
      setState(() {
        _error = _auth.motivoRechazo ?? 'verification.mp_not_connected'.tr();
        _campoConError = 'mercadopago';
      });
    });
  }

  Future<void> _verificarNegocio() {
    if (_ubicacion == null) {
      setState(() {
        _error = 'verification.location_pin_required'.tr();
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
          _error = _auth.motivoRechazo ?? 'verification.business_failed'.tr();
          _campoConError = _auth.campoRechazado;
        });
      }
    });
  }

  /// Lleva a resolver un requisito del checklist y, al volver, lo reevalúa.
  ///
  /// El refresco al volver es lo que hace que la palomita cambie sola: sin
  /// él, alguien que acaba de configurar su horario seguiría viendo la ✗ y
  /// creería que no se guardó.
  Future<void> _irAResolverRequisito(VerificationRequirement requisito) async {
    switch (requisito.accion) {
      case 'conectar_mercadopago':
        // TODO: Mercado Pago pendiente para próxima actualización - no
        // eliminar, solo descomentar la navegación cuando esté listo.
        if (!kMercadoPagoHabilitado) break;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ConnectMpScreen()),
        );
      case 'editar_perfil':
        final seller = await _sellerDelUsuario();
        if (!mounted || seller == null) break;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EditProfileScreen(seller: seller),
          ),
        );
      case 'revisar_productos':
        // A "Mis publicaciones", que es donde se abre cada producto para
        // editarlo. El detalle del requisito (que nombra los productos sin
        // cantidad) se deja en un aviso ANTES de navegar: en la lista de
        // publicaciones nada distingue a los que hay que arreglar.
        if (!mounted) break;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(requisito.detalle)));
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MyListingsScreen()),
        );
    }
    if (mounted) await _auth.refrescarEstadoVerificacion();
  }

  /// El `Seller` del backend, que necesita "Editar perfil" para abrirse.
  Future<Seller?> _sellerDelUsuario() async {
    final id = _auth.backendSellerId;
    if (id == null) return null;
    try {
      return await ApiService.getSeller(id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('verification.open_profile_error'.tr())),
        );
      }
      return null;
    }
  }

  Future<void> _elegirUbicacion() async {
    final punto = await LocationPickerScreen.open(
      context,
      initialLat: _ubicacion?.latitude,
      initialLng: _ubicacion?.longitude,
      title: 'register.business_location_title'.tr(),
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
    // `watch` y no `read`: al volver de "Editar perfil" el provider notifica
    // con la lista nueva y esta pantalla se repinta sola — es lo que hace que
    // la ✗ pase a ✓ y que el botón se habilite sin tocar nada más.
    final requisitos = _requisitosVisibles(
      context.watch<AuthProvider>().requisitos,
    );
    // Bloquea el envío mientras falte algo. Si la lista todavía no llegó
    // (arranque sin conexión) no se bloquea: el backend vuelve a validar al
    // cerrar la verificación, así que dejar pasar aquí como mucho cuesta un
    // rechazo con motivo, mientras que bloquear dejaría la pantalla muerta
    // sin decir por qué.
    final faltanRequisitos = requisitos.any((r) => !r.cumplido);

    return Scaffold(
      appBar: AppBar(title: Text('verification.title'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _faltaMercadoPago
                    ? 'verification.last_step'.tr()
                    : _esperandoCodigo
                    ? 'verification.enter_code'.tr()
                    : _titulo,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                _faltaMercadoPago
                    ? 'verification.identity_confirmed_connect_mp'.tr()
                    : _esperandoCodigo
                    ? 'verification.code_sent'.tr(
                        namedArgs: {'destination': _destinoCodigo ?? ''},
                      )
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
              if (_error != null &&
                  (!_esperandoCodigo || _faltaMercadoPago)) ...[
                _CajaAviso(
                  mensaje: _error!,
                  color: AppColors.danger,
                  icono: Icons.error_outline_rounded,
                ),
                const SizedBox(height: 16),
              ],

              if (_codigoDev != null) ...[
                _CajaAviso(
                  mensaje: 'verification.dev_code'.tr(
                    namedArgs: {'code': '$_codigoDev'},
                  ),
                  color: context.colors.accent,
                  icono: Icons.build_rounded,
                ),
                const SizedBox(height: 16),
              ],

              // El checklist va ANTES del botón, no después de fallar.
              // Intentar y fallar enseña un requisito por intento; con la
              // lista delante se ve de un vistazo todo lo que falta.
              //
              // Solo en el paso de captura: durante el OTP la persona está
              // tecleando seis dígitos y no puede resolver nada de esto.
              if (!_esperandoCodigo && !_faltaMercadoPago) ...[
                VerificationChecklist(
                  requisitos: requisitos,
                  onAccion: _irAResolverRequisito,
                ),
                const SizedBox(height: 20),
              ],

              if (_faltaMercadoPago)
                _buildConectarCobros()
              else if (_esperandoCodigo)
                _buildIngresoCodigo()
              else
                _buildFormulario(bloqueado: faltanRequisitos),

              const SizedBox(height: 28),

              if (widget.desdeRegistro)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _enviando ? null : _posponer,
                    child: Text('verification.do_later'.tr()),
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
    AccountType.estudiante => 'verification.title_student'.tr(),
    AccountType.negocio => 'verification.title_business'.tr(),
    AccountType.particular => 'verification.title_phone'.tr(),
  };

  String get _descripcion => switch (widget.tipo) {
    AccountType.estudiante => 'verification.desc_student'.tr(),
    AccountType.negocio => 'verification.desc_business'.tr(),
    AccountType.particular => 'verification.desc_phone'.tr(),
  };

  /// [bloqueado] = queda algún requisito del checklist sin cumplir, así que el
  /// botón de enviar/verificar va deshabilitado. No se oculta ni se sustituye
  /// por un aviso: dejarlo a la vista, apagado y con la lista justo encima, es
  /// lo que conecta "no puedo pulsar esto" con "porque me falta esto".
  Widget _buildFormulario({required bool bloqueado}) => switch (widget.tipo) {
    AccountType.estudiante => _buildFormEstudiante(bloqueado: bloqueado),
    AccountType.negocio => _buildFormNegocio(bloqueado: bloqueado),
    AccountType.particular => _buildFormExterno(bloqueado: bloqueado),
  };

  // ─── Conectar la cuenta de cobros (estudiante y externo) ───
  //
  // Paso propio y no un aviso dentro del formulario: en este punto ya no hay
  // nada más que hacer, y dejar a la vista las casillas del código —vacías,
  // con el código ya consumido— solo invita a teclear algo que no sirve.

  Widget _buildConectarCobros() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilaConectarMercadoPago(
          destacado: _campoConError == 'mercadopago',
          habilitado: !_enviando,
          // Al volver de conectar se reintenta solo: la persona no tiene por
          // qué saber que hace falta un segundo paso.
          onConectado: () {
            if (mounted) _reintentarTrasConectar();
          },
        ),
        const SizedBox(height: 18),
        _BotonPrincipal(
          etiqueta: 'verification.already_connected'.tr(),
          cargando: _enviando,
          onPressed: _reintentarTrasConectar,
        ),
      ],
    );
  }

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
          // Etiqueta neutra siempre: el dominio detectado no se muestra en
          // ningún lado de la UI, ni siquiera aquí.
          etiqueta: esEstudiante
              ? 'verification.institutional_email'.tr()
              : 'verification.phone_number'.tr(),
          icono: esEstudiante ? Icons.badge_rounded : Icons.phone_rounded,
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
          etiqueta: 'verification.verify_code'.tr(),
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
                ? 'verification.resend_in'.tr(
                    namedArgs: {'seconds': '$_segundosReenvio'},
                  )
                : 'verification.resend'.tr(),
          ),
        ),
        TextButton(
          onPressed: _enviando ? null : _volverAlFormulario,
          child: Text(
            esEstudiante
                ? 'verification.change_email'.tr()
                : 'verification.change_phone'.tr(),
          ),
        ),
      ],
    );
  }

  // ─── Formularios ───────────────────────────────────────────

  Widget _buildFormEstudiante({required bool bloqueado}) {
    return Column(
      children: [
        _CampoTexto(
          controller: _matriculaController,
          focusNode: _focoMatricula,
          etiqueta: 'verification.institutional_email'.tr(),
          icono: Icons.badge_rounded,
          conError: _campoConError == 'correo_institucional',
          // Sin inputFormatters de por medio: el dominio (y por lo tanto el
          // formato esperado) se decide con lo que la persona ya escribió,
          // así que no se puede filtrar por adelantado sin arriesgarse a
          // bloquear el carácter que resuelve la ambigüedad.
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9.]')),
          ],
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
          etiqueta: 'verification.send_code'.tr(),
          cargando: _enviando,
          onPressed: bloqueado ? null : _solicitarCodigoEstudiante,
        ),
        if (bloqueado) const _AvisoRequisitosPendientes(),
      ],
    );
  }

  Widget _buildFormExterno({required bool bloqueado}) {
    return Column(
      children: [
        _CampoTexto(
          controller: _telefonoController,
          etiqueta: 'verification.phone_number_required'.tr(),
          icono: Icons.phone_rounded,
          tipoTeclado: TextInputType.phone,
          conError: _campoConError == 'telefono',
        ),
        const SizedBox(height: 24),
        _BotonPrincipal(
          etiqueta: 'verification.send_code_sms'.tr(),
          cargando: _enviando,
          onPressed: bloqueado ? null : _solicitarCodigoExterno,
        ),
        if (bloqueado) const _AvisoRequisitosPendientes(),
      ],
    );
  }

  Widget _buildFormNegocio({required bool bloqueado}) {
    final conErrorUbicacion = _campoConError == 'ubicacion';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CampoTexto(
          controller: _nombreNegocioController,
          etiqueta: 'register.business_name'.tr(),
          icono: Icons.storefront_rounded,
          conError: _campoConError == 'nombre_negocio',
        ),
        const SizedBox(height: 18),

        Text(
          'verification.business_location_required'.tr(),
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
            _ubicacion == null
                ? 'verification.place_pin'.tr()
                : 'register.change_location'.tr(),
          ),
        ),
        const SizedBox(height: 18),

        _CampoTexto(
          controller: _linkController,
          etiqueta: 'verification.social_link'.tr(),
          icono: Icons.link_rounded,
          tipoTeclado: TextInputType.url,
          ayuda: 'verification.social_link_help'.tr(),
          conError: _campoConError == 'link_red_social',
        ),
        const SizedBox(height: 24),

        // Conectar Mercado Pago es requisito SOLO para negocio: un negocio
        // verificado es uno que puede cobrar en la app. Se ofrece desde aquí
        // para que no haya que salir al perfil a buscarlo, y se destaca
        // cuando el backend dice que es justo lo que falta.
        //
        // TODO: Mercado Pago pendiente para próxima actualización - no
        // eliminar, solo quitar este `if` cuando esté listo.
        if (kMercadoPagoHabilitado) ...[
          _FilaConectarMercadoPago(
            destacado: _campoConError == 'mercadopago',
            habilitado: !_enviando,
            onConectado: () {
              // Al volver de conectar, se reintenta solo: el usuario ya tiene
              // el formulario lleno y repetirlo a mano sería absurdo.
              if (mounted) _verificarNegocio();
            },
          ),
          const SizedBox(height: 18),
        ],

        _BotonPrincipal(
          etiqueta: 'verification.verify_business'.tr(),
          cargando: _enviando,
          onPressed: bloqueado ? null : _verificarNegocio,
        ),
        if (bloqueado) const _AvisoRequisitosPendientes(),
      ],
    );
  }
}

/// Explica por qué el botón principal está apagado.
///
/// El botón deshabilitado por sí solo no dice nada —y el checklist queda
/// arriba, fuera de la mirada de quien acaba de intentar pulsarlo—, así que la
/// razón se repite justo debajo, donde se produjo la frustración.
class _AvisoRequisitosPendientes extends StatelessWidget {
  const _AvisoRequisitosPendientes();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        'verification.complete_requirements_first'.tr(),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.35,
          color: context.colors.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Acceso a la conexión de Mercado Pago desde el formulario de verificación
/// de negocio.
class _FilaConectarMercadoPago extends StatelessWidget {
  const _FilaConectarMercadoPago({
    required this.destacado,
    required this.habilitado,
    required this.onConectado,
  });

  /// El backend indicó que esto es lo único que falta para verificarse.
  final bool destacado;
  final bool habilitado;
  final VoidCallback onConectado;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = destacado ? AppColors.danger : colors.border;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
        color: destacado
            ? AppColors.danger.withValues(alpha: 0.05)
            : Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: destacado ? AppColors.danger : colors.muted,
              ),
              const SizedBox(width: 8),
              Text(
                'verification.payout_account'.tr(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'verification.payout_account_help'.tr(),
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: habilitado
                ? () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ConnectMpScreen(),
                      ),
                    );
                    onConectado();
                  }
                : null,
            icon: const Icon(Icons.link_rounded),
            label: Text('verification.connect_mp'.tr()),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets base compartidos ────────────────────────────────

class _CampoTexto extends StatelessWidget {
  const _CampoTexto({
    required this.controller,
    required this.etiqueta,
    required this.icono,
    this.focusNode,
    this.tipoTeclado,
    this.ayuda,
    this.conError = false,
    this.habilitado = true,
    this.inputFormatters,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String etiqueta;
  final IconData icono;
  final TextInputType? tipoTeclado;
  final String? ayuda;

  /// Resalta el campo que el backend señaló como causa del rechazo.
  final bool conError;

  /// En false el campo queda a la vista pero de solo lectura y atenuado.
  final bool habilitado;

  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: habilitado,
      keyboardType: tipoTeclado,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
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
            labelText: 'verification.major'.tr(),
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
