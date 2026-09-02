import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

/// Pantalla de verificación para estudiantes y negocios.
///
/// Estudiantes se verifican con un código de correo institucional. Los
/// negocios envían una solicitud manual con su perfil e identificación para
/// revisión; las cuentas particulares no participan en este flujo.
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
  bool _solicitudPendiente = false;
  bool _revisandoEstadoSolicitud = true;
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
  /// Guarda el correo tal como se ve en el campo: la parte local que teclea
  /// el usuario y, en cuanto deja de ser ambigua, el dominio autocompletado
  /// por [DominioSufijoFormatter]. La parte local se recupera con
  /// [DominioSufijoFormatter.parteLocal].
  final _matriculaController = TextEditingController();
  final _focoMatricula = FocusNode();

  /// Dominio detectado automáticamente a partir de lo tecleado (ver
  /// [DominioUM.detectarDesde]). Null = todavía ambiguo (menos de 3
  /// caracteres, o
  /// ninguno decisivo aún), que es lo que impide validar o enviar: hasta
  /// saber el dominio no se sabe qué formato exigirle a lo que se teclee.
  ///
  /// No hay desplegable ni ningún otro selector: el dominio solo aparece
  /// escrito dentro del propio campo, y únicamente una vez que la detección
  /// lo resolvió, para no revelar por adelantado el formato de los correos
  /// institucionales.
  DominioUM? _dominio;

  /// Solo se llena cuando el usuario elige una opción exacta de [carrerasUM]
  /// (ver [_CampoCarrera]); nunca contiene texto libre, así el botón de
  /// enviar puede usar "es null" para saber si falta seleccionar.
  String? _carreraSeleccionada;

  // Negocio
  final _nombreNegocioController = TextEditingController();
  final _linkController = TextEditingController();
  ll.LatLng? _ubicacion;
  String? _ineFrente;
  String? _ineReverso;
  Uint8List? _ineFrentePreview;
  Uint8List? _ineReversoPreview;
  bool _ineFrenteSubida = false;
  bool _ineReversoSubida = false;
  final List<String> _evidenciaAdicional = [];
  final Set<String> _evidenciaAdicionalSubida = {};
  final ImagePicker _imagePicker = ImagePicker();
  bool _perfilNegocioCompleto = false;
  bool _revisandoPerfilNegocio = true;
  final Set<String> _camposPerfilFaltantes = {};
  String? _responsableNegocio;

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
    // Un toque (o las flechas) puede dejar el cursor dentro del dominio sin
    // pasar por el formatter, que solo ve ediciones de texto. Este listener
    // lo devuelve a la parte local para que el dominio sea inalcanzable.
    _matriculaController.addListener(_mantenerCursorEnParteLocal);
    _retomarDondeQuedo();
    _revisarPerfilNegocio();
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

    if (widget.tipo == AccountType.negocio) {
      if (_auth.isVerified) {
        setState(() => _revisandoEstadoSolicitud = false);
        _terminar(verificado: true);
        return;
      }
      setState(() {
        _solicitudPendiente = _auth.solicitudManualPendiente;
        _revisandoEstadoSolicitud = false;
        if (_auth.estadoVerificacion == 'rechazado') {
          _error = _auth.motivoRechazo;
          _campoConError = _auth.campoRechazado;
        }
      });
      return;
    }

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

  Future<void> _revisarPerfilNegocio() async {
    if (widget.tipo != AccountType.negocio) return;
    final perfil = await _auth.getBusinessProfileLocal();
    if (!mounted) return;
    final faltantes = <String>{};
    final nombrePerfil = (perfil?['business_name'] as String? ?? '').trim();
    _responsableNegocio = (perfil?['responsible_name'] as String?)?.trim();
    if (_nombreNegocioController.text.trim().isEmpty &&
        nombrePerfil.isNotEmpty) {
      _nombreNegocioController.text = nombrePerfil;
    }
    if (nombrePerfil.isEmpty) {
      faltantes.add('Nombre del negocio');
    }
    if ((perfil?['business_type'] as String? ?? '').trim().isEmpty) {
      faltantes.add('Categoría');
    }
    if ((perfil?['responsible_name'] as String? ?? '').trim().isEmpty) {
      faltantes.add('Responsable');
    }
    setState(() {
      _camposPerfilFaltantes
        ..clear()
        ..addAll(faltantes);
      _perfilNegocioCompleto = faltantes.isEmpty;
      _revisandoPerfilNegocio = false;
    });
  }

  Future<void> _seleccionarDocumento({required bool frente}) async {
    try {
      final foto = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2000,
      );
      if (foto == null) return;
      final preview = await foto.readAsBytes();
      if (!mounted) return;
      setState(() {
        if (frente) {
          _ineFrente = foto.path;
          _ineFrentePreview = preview;
          _ineFrenteSubida = false;
        } else {
          _ineReverso = foto.path;
          _ineReversoPreview = preview;
          _ineReversoSubida = false;
        }
        _campoConError = null;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _campoConError = 'ine';
        _error = error.code == 'camera_access_denied'
            ? 'Necesitamos permiso para abrir la cámara y fotografiar la INE.'
            : 'No pudimos abrir la cámara. Revisa el permiso e inténtalo de nuevo.';
      });
    }
  }

  Future<void> _seleccionarEvidenciaAdicional() async {
    final resultado = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (resultado == null || !mounted) return;
    setState(() {
      final nuevas = resultado.files.map((f) => f.path).whereType<String>();
      for (final path in nuevas) {
        if (!_evidenciaAdicional.contains(path)) {
          _evidenciaAdicional.add(path);
        }
      }
    });
  }

  @override
  void dispose() {
    _timerReenvio?.cancel();
    _matriculaController.removeListener(_actualizarDominioDetectado);
    _matriculaController.removeListener(_mantenerCursorEnParteLocal);
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

    final usuario = DominioSufijoFormatter.parteLocal(
      _matriculaController.text,
    ).trim().toLowerCase();
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

  /// Reevalúa el dominio en cada cambio del campo de texto. Se puede
  /// reevaluar en cualquier momento: si el usuario borra y reescribe, el
  /// dominio detectado puede cambiar (o volver a quedar ambiguo).
  void _actualizarDominioDetectado() {
    final nuevo = DominioUM.detectarDesde(
      DominioSufijoFormatter.parteLocal(_matriculaController.text),
    );
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

  /// Mantiene la selección dentro de la parte local: el dominio
  /// autocompletado no se puede seleccionar ni colocar el cursor dentro, así
  /// que tampoco se puede borrar a mano.
  ///
  /// Sale sin tocar nada cuando la selección ya está donde debe — si no, el
  /// setter volvería a notificar a los listeners en bucle.
  void _mantenerCursorEnParteLocal() {
    final limite = DominioSufijoFormatter.parteLocal(
      _matriculaController.text,
    ).length;
    final seleccion = _matriculaController.selection;
    if (!seleccion.isValid) return;
    if (seleccion.baseOffset <= limite && seleccion.extentOffset <= limite) {
      return;
    }
    _matriculaController.selection = TextSelection(
      baseOffset: seleccion.baseOffset.clamp(0, limite),
      extentOffset: seleccion.extentOffset.clamp(0, limite),
      affinity: seleccion.affinity,
    );
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
    final nombre = _nombreNegocioController.text.trim();
    final link = _linkController.text.trim();
    String? mensaje;
    String? campo;

    if (!_perfilNegocioCompleto) {
      mensaje =
          'Completa los campos obligatorios de tu perfil de negocio antes de enviar la solicitud.';
      campo = 'perfil_negocio';
    } else if (nombre.isEmpty) {
      mensaje = 'Escribe el nombre del negocio.';
      campo = 'nombre_negocio';
    } else if (_ubicacion == null) {
      mensaje = 'Coloca la ubicación de tu negocio en el mapa.';
      campo = 'ubicacion';
    } else if (link.isEmpty) {
      mensaje = 'Agrega la red social o página pública del negocio.';
      campo = 'link_red_social';
    } else if (_ineFrente == null || _ineReverso == null) {
      mensaje = 'Adjunta el frente y reverso de la INE del responsable.';
      campo = 'ine';
    }

    if (mensaje != null) {
      setState(() {
        _error = mensaje;
        _campoConError = campo;
      });
      return Future.value();
    }

    return _ejecutar(() async {
      if (!_ineFrenteSubida) {
        await ApiService.uploadBusinessVerificationDocument(
          docType: 'responsible_ine_front',
          filePath: _ineFrente!,
        );
        _ineFrenteSubida = true;
      }
      if (!_ineReversoSubida) {
        await ApiService.uploadBusinessVerificationDocument(
          docType: 'responsible_ine_back',
          filePath: _ineReverso!,
        );
        _ineReversoSubida = true;
      }
      for (final path in _evidenciaAdicional) {
        if (_evidenciaAdicionalSubida.contains(path)) continue;
        await ApiService.uploadBusinessVerificationDocument(
          docType: 'additional_evidence',
          filePath: path,
        );
        _evidenciaAdicionalSubida.add(path);
      }
      await _auth.solicitarVerificacionManualNegocio(
        responsableNombre: _responsableNegocio!,
        nombreNegocio: nombre,
        lat: _ubicacion!.latitude,
        lng: _ubicacion!.longitude,
        linkRedSocial: link,
      );
      if (!mounted) return;
      setState(() => _solicitudPendiente = true);
    });
  }

  Future<void> _actualizarSolicitudPendiente() async {
    setState(() => _enviando = true);
    await _auth.refrescarEstadoVerificacion();
    if (!mounted) return;

    if (_auth.isVerified) {
      setState(() => _enviando = false);
      _terminar(verificado: true);
      return;
    }

    setState(() {
      _enviando = false;
      _solicitudPendiente = _auth.solicitudManualPendiente;
      if (!_solicitudPendiente) {
        _error =
            _auth.motivoRechazo ??
            'La solicitud ya no está pendiente. Revisa los datos y vuelve a enviarla.';
        _campoConError = _auth.campoRechazado;
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
    if (widget.tipo == AccountType.particular) {
      return const AccountCreatedScreen();
    }

    // `watch` mantiene sincronizados el checklist y el estado que decide el
    // administrador aunque la pantalla siga abierta.
    final auth = context.watch<AuthProvider>();
    if (widget.tipo == AccountType.negocio && _revisandoEstadoSolicitud) {
      return Scaffold(
        appBar: AppBar(title: Text('verification.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.tipo == AccountType.negocio && _solicitudPendiente) {
      return _buildSolicitudPendiente();
    }

    final requisitos = _requisitosVisibles(auth.requisitos);
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

  Widget _buildSolicitudPendiente() {
    return Scaffold(
      appBar: AppBar(title: Text('verification.title'.tr())),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: context.colors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.hourglass_top_rounded,
                      color: context.colors.accent,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'verification.manual_pending_title'.tr(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'verification.manual_pending_description'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CajaAviso(
                    mensaje: 'verification.manual_pending_hint'.tr(),
                    color: context.colors.accent,
                    icono: Icons.notifications_active_outlined,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _enviando
                          ? null
                          : _actualizarSolicitudPendiente,
                      icon: _enviando
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text('verification.refresh_status'.tr()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _enviando ? null : _posponer,
                      child: Text('verification.continue'.tr()),
                    ),
                  ),
                ],
              ),
            ),
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
          // Etiqueta neutra: el campo ya trae el correo completo, con el
          // dominio que se autocompletó al escribir, y sirve de comprobante
          // de a dónde se mandó el código.
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
          // El filtro no puede ceñirse al formato de un dominio concreto: el
          // carácter que resuelve la ambigüedad sería justo el bloqueado.
          // Solo deja pasar lo que cabe en un correo institucional, arroba
          // incluida — el arroba que teclee el usuario lo absorbe después
          // [DominioSufijoFormatter], que es quien decide dónde empieza el
          // dominio y lo mantiene fijo.
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9.@]')),
            const DominioSufijoFormatter(),
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

  Widget _insigniaDocumento(String texto, {required bool requerido}) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        texto,
        style: TextStyle(
          color: requerido ? colors.ink : colors.muted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _capturaIne({
    required String titulo,
    required Uint8List? preview,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    final capturada = preview != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _enviando ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 176,
          child: Column(
            children: [
              Expanded(
                child: capturada
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox.expand(
                          child: Image.memory(preview, fit: BoxFit.cover),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_camera_outlined,
                            size: 32,
                            color: colors.muted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Abrir cámara',
                            style: TextStyle(
                              color: colors.mutedStrong,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        titulo,
                        style: TextStyle(
                          color: colors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      capturada
                          ? Icons.check_circle_rounded
                          : Icons.camera_alt_rounded,
                      size: 20,
                      color: capturada ? colors.success : colors.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seccionDocumentosNegocio() {
    final colors = context.colors;
    final conErrorIne = _campoConError == 'ine';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_revisandoPerfilNegocio)
          const LinearProgressIndicator()
        else if (!_perfilNegocioCompleto)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.danger),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, color: colors.danger),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    [
                      'Completa en tu perfil:',
                      _camposPerfilFaltantes.join(', '),
                    ].join(' '),
                    style: TextStyle(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 25,
                    color: conErrorIne ? colors.danger : colors.mutedStrong,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'INE del responsable',
                          style: TextStyle(
                            color: colors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Fotografía el documento original por ambos lados.',
                          style: TextStyle(color: colors.muted, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _insigniaDocumento('OBLIGATORIO', requerido: true),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final ancho = constraints.maxWidth < 350
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: ancho,
                        child: _capturaIne(
                          titulo: 'Frente',
                          preview: _ineFrentePreview,
                          onTap: () => _seleccionarDocumento(frente: true),
                        ),
                      ),
                      SizedBox(
                        width: ancho,
                        child: _capturaIne(
                          titulo: 'Reverso',
                          preview: _ineReversoPreview,
                          onTap: () => _seleccionarDocumento(frente: false),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 17,
                    color: colors.muted,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'La cámara es obligatoria para evitar imágenes alteradas. '
                      'Tu identificación solo se usa para revisar la solicitud.',
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.collections_bookmark_outlined,
                    size: 25,
                    color: colors.mutedStrong,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Evidencia adicional',
                          style: TextStyle(
                            color: colors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Permisos, fotos del negocio, menús, capturas de redes '
                          'sociales o cualquier PDF que apoye tu solicitud.',
                          style: TextStyle(color: colors.muted, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _insigniaDocumento('OPCIONAL', requerido: false),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _enviando ? null : _seleccionarEvidenciaAdicional,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Agregar imágenes o PDF'),
              ),
              if (_evidenciaAdicional.isNotEmpty) ...[
                const SizedBox(height: 12),
                ..._evidenciaAdicional.map((path) {
                  final nombre = path.split('/').last;
                  final esPdf = nombre.toLowerCase().endsWith('.pdf');
                  final subida = _evidenciaAdicionalSubida.contains(path);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          esPdf
                              ? Icons.picture_as_pdf_outlined
                              : Icons.image_outlined,
                          color: colors.mutedStrong,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (subida)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              Icons.cloud_done_outlined,
                              size: 19,
                              color: colors.success,
                            ),
                          )
                        else
                          IconButton(
                            tooltip: 'Quitar archivo',
                            onPressed: _enviando
                                ? null
                                : () => setState(
                                    () => _evidenciaAdicional.remove(path),
                                  ),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
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

        _seccionDocumentosNegocio(),
        const SizedBox(height: 24),
        _BotonPrincipal(
          etiqueta: 'Enviar solicitud de verificación',
          cargando: _enviando,
          onPressed:
              bloqueado ||
                  _revisandoPerfilNegocio ||
                  !_perfilNegocioCompleto ||
                  _ineFrente == null ||
                  _ineReverso == null
              ? null
              : _verificarNegocio,
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
