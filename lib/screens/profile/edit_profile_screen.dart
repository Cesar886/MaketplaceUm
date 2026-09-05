import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../mock_data.dart';
import '../../models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_error.dart';
import '../../services/api_service.dart';
import '../../validation/social_links.dart';
import '../../widgets/business_hours_editor.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/payment_methods.dart';
import '../../widgets/static_mini_map.dart';
import '../../features/payments/connect_mp_screen.dart';
import '../../features/payments/payment_models.dart';
import '../../features/payments/payments_api.dart';
import '../../features/payments/mercado_pago_flag.dart';
import 'badges_visibility_screen.dart';

const _kMaxBusinessDescriptionLength = 280;

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.seller});

  final Seller seller;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _descriptionController;
  String? _selectedCategoryId;
  List<MarketplaceCategory> _categories = [];
  XFile? _pickedPhoto;
  bool _saving = false;

  /// Estado de la cuenta de Mercado Pago del vendedor. Decide si 'tarjeta' se
  /// puede seleccionar. Se consulta al abrir la pantalla, al volver de
  /// segundo plano (que es como se regresa del navegador tras el OAuth) y con
  /// pull-to-refresh.
  EstadoCobros? _estadoMp;
  bool _cargandoMp = true;

  /// El estado de cobros cambió mientras esta pantalla estaba abierta. Se
  /// devuelve al salir para que el perfil recargue el `Seller` del backend:
  /// conectar Mercado Pago puede cambiar los métodos de pago aceptados y
  /// hasta completar la verificación, y el perfil sigue mostrando lo que
  /// trajo la última vez.
  bool _estadoMpCambio = false;
  late Map<int, BusinessHoursRange> _businessHours;
  double? _locationLat;
  double? _locationLng;
  late final TextEditingController _facebookController;
  late final TextEditingController _instagramController;
  late final TextEditingController _whatsappController;
  late final TextEditingController _tiktokController;
  late final TextEditingController _twitterController;
  late final Set<String> _selectedPaymentMethods;
  bool _showPaymentMethodsError = false;

  bool get _isBusiness => widget.seller.isBusiness;

  /// Consulta el estado de la cuenta de cobros.
  ///
  /// Ver [PaymentsApi.estadoDeCobros] para por qué no basta con `validarCuenta`:
  /// un 503 de una plataforma a medio configurar, o una red que se cayó un
  /// segundo, no pueden leerse como "este vendedor no tiene cuenta".
  Future<void> _cargarEstadoMp() async {
    // TODO: Mercado Pago pendiente para próxima actualización - no eliminar,
    // solo quitar este corte cuando esté listo.
    if (!kMercadoPagoHabilitado) {
      if (mounted) setState(() => _cargandoMp = false);
      return;
    }
    final anterior = _estadoMp;
    final estado = await PaymentsApi.estadoDeCobros();
    if (!mounted) return;
    setState(() {
      _estadoMp = estado;
      _cargandoMp = false;
      if (anterior != null && anterior != estado) _estadoMpCambio = true;
      // Si la cuenta se cayó, 'tarjeta' ya no se puede seguir ofreciendo. El
      // backend la retira igual, pero dejarla marcada aquí haría que el
      // guardado fallara con un error que el vendedor no esperaba.
      //
      // Solo con una respuesta CONCLUYENTE: si no se pudo comprobar, quitarle
      // el método que ya tenía guardado sería castigarlo por un fallo nuestro.
      if (estado == EstadoCobros.sinConectar) {
        _selectedPaymentMethods.remove('tarjeta');
      }
    });
  }

  /// El OAuth de Mercado Pago sale al navegador del sistema, así que la app
  /// se va a segundo plano y vuelve. Ese `resumed` es la señal más temprana
  /// que hay de que el vendedor terminó (o abandonó) la conexión.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cargarEstadoMp();
  }

  Future<void> _abrirConexionMp() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ConnectMpScreen()));
    if (!mounted) return;
    setState(() => _cargandoMp = true);
    await _cargarEstadoMp();
    if (!mounted) return;
    // Conectar la cuenta puede haber cerrado una verificación que estaba
    // esperando exactamente eso (el backend la cierra en el callback de
    // OAuth), así que el estado que tiene el provider quedó viejo.
    await context.read<AuthProvider>().refrescarEstadoVerificacion();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nameController = TextEditingController(text: widget.seller.name);
    _phoneController = TextEditingController(text: widget.seller.phone ?? '');
    _descriptionController = TextEditingController(
      text: widget.seller.businessDescription ?? '',
    );
    _selectedCategoryId = widget.seller.businessCategory;
    _businessHours = Map.of(widget.seller.businessHours);
    _locationLat = widget.seller.locationLat;
    _locationLng = widget.seller.locationLng;
    _facebookController = TextEditingController(
      text: widget.seller.facebookUrl ?? '',
    );
    _instagramController = TextEditingController(
      text: widget.seller.instagramUrl ?? '',
    );
    _whatsappController = TextEditingController(
      text: widget.seller.whatsappNumber ?? '',
    );
    _tiktokController = TextEditingController(
      text: widget.seller.tiktokUrl ?? '',
    );
    _twitterController = TextEditingController(
      text: widget.seller.twitterUrl ?? '',
    );
    _selectedPaymentMethods = Set.of(widget.seller.paymentMethods);
    _cargarEstadoMp();
    if (_isBusiness) _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.getCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // Respaldo local, igual que publish_product_screen y wanted_post_screen.
      //
      // "No bloquea el resto del formulario" era verdad a medias: un
      // DropdownButton sin items se auto-deshabilita, así que la categoría
      // del negocio quedaba imposible de cambiar y sin explicación. Los ids
      // de `mockCategories` son los mismos que sirve el backend.
      if (!mounted) return;
      setState(() => _categories = mockCategories);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _whatsappController.dispose();
    _tiktokController.dispose();
    _twitterController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked != null) {
      setState(() => _pickedPhoto = picked);
    }
  }

  Future<void> _pickLocation() async {
    final picked = await LocationPickerScreen.open(
      context,
      initialLat: _locationLat,
      initialLng: _locationLng,
      title: 'register.business_location_title'.tr(),
    );
    if (picked != null) {
      setState(() {
        _locationLat = picked.latitude;
        _locationLng = picked.longitude;
      });
    }
  }

  /// Abre el selector de insignias con el perfil recién pedido al servidor.
  ///
  /// No se reusa `widget.seller`: `insigniasGanadas` solo viaja en el perfil
  /// propio (GET /api/sellers/:id con sesión), y el Seller con el que se
  /// entró a esta pantalla pudo venir de un listado que no lo trae.
  Future<void> _abrirInsignias() async {
    try {
      final propio = await ApiService.getMyProfile(widget.seller.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BadgesVisibilityScreen(seller: propio),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('badge_visibility.load_error'.tr())),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPaymentMethods.isEmpty) {
      setState(() => _showPaymentMethodsError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('register.payment_methods_required'.tr())),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final auth = context.read<AuthProvider>();
      await auth.updateProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        logoPath: _pickedPhoto?.path,
        businessDescription: _isBusiness
            ? _descriptionController.text.trim()
            : null,
        businessCategory: _isBusiness ? _selectedCategoryId : null,
        // Sin `_isBusiness`: el horario aplica a todos los tipos de cuenta.
        businessHours: _businessHours,
        locationLat: _isBusiness ? _locationLat : null,
        locationLng: _isBusiness ? _locationLng : null,
        paymentMethods: _selectedPaymentMethods.toList(),
        facebookUrl: _isBusiness ? _facebookController.text.trim() : null,
        instagramUrl: _isBusiness ? _instagramController.text.trim() : null,
        whatsappNumber: _isBusiness ? _whatsappController.text.trim() : null,
        tiktokUrl: _isBusiness ? _tiktokController.text.trim() : null,
        twitterUrl: _isBusiness ? _twitterController.text.trim() : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, stack) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              e,
              stack: stack,
              fallback: 'publish.save_error'.tr(),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildAvatar() {
    final initials = widget.seller.avatarInitials;
    Widget child;
    if (_pickedPhoto != null) {
      child = ClipOval(
        child: Image.file(
          File(_pickedPhoto!.path),
          width: 96,
          height: 96,
          fit: BoxFit.cover,
        ),
      );
    } else if (widget.seller.logoUrl != null &&
        widget.seller.logoUrl!.isNotEmpty) {
      child = ClipOval(
        child: Image.network(
          '${ApiService.baseUrl}${widget.seller.logoUrl}',
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Text(
            initials,
            style: TextStyle(
              fontSize: 28,
              color: context.colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } else {
      child = Text(
        initials,
        style: TextStyle(
          fontSize: 28,
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return InkWell(
      onTap: _pickPhoto,
      customBorder: const CircleBorder(),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: context.colors.primary.withValues(alpha: 0.12),
            child: child,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.colors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Salir por el botón de atrás también tiene que avisar al perfil si el
    // estado de cobros cambió: conectar Mercado Pago cambia los métodos de
    // pago aceptados —y puede completar la verificación— sin tocar el botón
    // de guardar, y el perfil seguiría pintando lo que trajo hace un rato.
    //
    // `canPop: false` solo intercepta el gesto de atrás y la flecha del
    // AppBar (que van por `maybePop`); el `pop(true)` explícito de _save no
    // pasa por aquí y sigue funcionando igual.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_estadoMpCambio);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('edit_profile.title'.tr())),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: RefreshIndicator(
              onRefresh: _cargarEstadoMp,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Center(child: _buildAvatar()),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'edit_profile.name'.tr(),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'validation.name_required'.tr()
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'edit_profile.phone'.tr(),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                  if (_isBusiness) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategoryId,
                      decoration: InputDecoration(
                        labelText: 'edit_profile.business_category'.tr(),
                        prefixIcon: const Icon(Icons.storefront_outlined),
                      ),
                      items: [
                        for (final category in _categories)
                          DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedCategoryId = value),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: _kMaxBusinessDescriptionLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'edit_profile.business_description'.tr(),
                        alignLabelWithHint: true,
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(bottom: 48),
                          child: const Icon(Icons.notes_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'register.business_location_optional'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: context.colors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_locationLat != null && _locationLng != null) ...[
                      StaticMiniMap(
                        lat: _locationLat,
                        lng: _locationLng,
                        showOpenInMapsButton: false,
                        height: 120,
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton.icon(
                      onPressed: _pickLocation,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(
                        _locationLat != null
                            ? 'register.change_location'.tr()
                            : 'edit_profile.pick_location'.tr(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'edit_profile.social_links'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: context.colors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _facebookController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'common.brand_facebook'.tr(),
                        hintText: 'edit_profile.facebook_hint'.tr(),
                        prefixIcon: const FaIcon(
                          FontAwesomeIcons.facebook,
                          size: 20,
                        ),
                      ),
                      validator: (v) => validateSocialUrl('facebook', v ?? ''),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _instagramController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'common.brand_instagram'.tr(),
                        hintText: 'edit_profile.instagram_hint'.tr(),
                        prefixIcon: const FaIcon(
                          FontAwesomeIcons.instagram,
                          size: 20,
                        ),
                      ),
                      validator: (v) => validateSocialUrl('instagram', v ?? ''),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _whatsappController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'common.brand_whatsapp'.tr(),
                        hintText: 'edit_profile.whatsapp_hint'.tr(),
                        prefixIcon: FaIcon(FontAwesomeIcons.whatsapp, size: 20),
                      ),
                      validator: (v) => validateWhatsappNumber(v ?? ''),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _tiktokController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'common.brand_tiktok'.tr(),
                        hintText: 'edit_profile.tiktok_hint'.tr(),
                        prefixIcon: const FaIcon(
                          FontAwesomeIcons.tiktok,
                          size: 20,
                        ),
                      ),
                      validator: (v) => validateSocialUrl('tiktok', v ?? ''),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _twitterController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'common.brand_twitter'.tr(),
                        hintText: 'edit_profile.twitter_hint'.tr(),
                        prefixIcon: const FaIcon(
                          FontAwesomeIcons.xTwitter,
                          size: 20,
                        ),
                      ),
                      validator: (v) => validateSocialUrl('twitter', v ?? ''),
                    ),
                  ],
                  // El horario lo configuran TODOS los tipos de cuenta, no
                  // solo los negocios: es requisito para verificarse, y es lo
                  // que le dice al comprador si estás abierto cuando te
                  // compra. Un estudiante que vende comida también cierra.
                  const SizedBox(height: 20),
                  Text(
                    'edit_profile.business_hours'.tr(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: context.colors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  BusinessHoursEditor(
                    initialHours: _businessHours,
                    onChanged: (hours) => _businessHours = hours,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'edit_profile.payment_methods'.tr(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: context.colors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  PaymentMethodsSelector(
                    selected: _selectedPaymentMethods,
                    showError: _showPaymentMethodsError,
                    // 'tarjeta' es el único método que la app cobra de verdad, y
                    // exige cuenta de Mercado Pago. Se muestra apagado con el
                    // motivo en vez de ocultarse: si desaparece, el vendedor no
                    // descubre que existe ni qué hacer para habilitarla.
                    //
                    // Si el estado no se pudo comprobar NO se bloquea: quitarle
                    // una opción que quizá sí tiene, por un fallo que es nuestro,
                    // es peor que dejársela y que el guardado la rechace con un
                    // motivo concreto.
                    metodosBloqueados: _estadoMp == EstadoCobros.sinConectar
                        ? {'tarjeta': 'edit_profile.card_needs_mp'.tr()}
                        : const {},
                    onChanged: (methods) => setState(() {
                      _selectedPaymentMethods
                        ..clear()
                        ..addAll(methods);
                      if (methods.isNotEmpty) _showPaymentMethodsError = false;
                    }),
                  ),
                  // TODO: Mercado Pago pendiente para próxima actualización -
                  // no eliminar, solo quitar este `if` cuando esté listo.
                  if (kMercadoPagoHabilitado) ...[
                    const SizedBox(height: 12),
                    _FilaConexionMercadoPago(
                      estado: _estadoMp,
                      cargando: _cargandoMp,
                      onTap: _abrirConexionMp,
                      onReintentar: () {
                        setState(() => _cargandoMp = true);
                        _cargarEstadoMp();
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Vive aquí y no en Ajustes porque es personalización del
                  // perfil, como el color de acento: se decide mirando el
                  // perfil, no la configuración de la cuenta.
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.workspace_premium_outlined,
                      color: context.colors.accent,
                    ),
                    title: Text('badge_visibility.title'.tr()),
                    subtitle: Text('badge_visibility.entry_hint'.tr()),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _abrirInsignias,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('common.save'.tr()),
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
}

/// Fila de estado de la cuenta de Mercado Pago dentro de "Editar perfil".
///
/// Muestra el estado explícitamente en vez de solo un botón: el vendedor
/// tiene que poder saber de un vistazo si está cobrando o no, sobre todo
/// después de una desconexión que él no provocó.
class _FilaConexionMercadoPago extends StatelessWidget {
  const _FilaConexionMercadoPago({
    required this.estado,
    required this.cargando,
    required this.onTap,
    required this.onReintentar,
  });

  /// null mientras no hay respuesta todavía.
  final EstadoCobros? estado;
  final bool cargando;
  final VoidCallback onTap;

  /// Vuelve a consultar. Solo se ofrece cuando el estado es
  /// [EstadoCobros.desconocido]: es el único caso en el que reintentar puede
  /// cambiar algo.
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const AppShimmer(child: ShimmerBox(height: 68, borderRadius: 12));
    }

    final colors = context.colors;
    final conectado = estado?.estaConectado ?? false;
    final desconocido = estado == EstadoCobros.desconocido;

    final color = conectado
        ? colors.primary
        : desconocido
        ? AppColors.danger
        : colors.muted;

    final icono = conectado
        ? Icons.check_circle_rounded
        : desconocido
        ? Icons.sync_problem_rounded
        : Icons.account_balance_wallet_outlined;

    final String detalle;
    if (cargando) {
      detalle = 'edit_profile.mp_checking'.tr();
    } else if (conectado) {
      detalle = 'edit_profile.mp_connected'.tr();
    } else if (desconocido) {
      // Deliberadamente NO dice "Sin conectar": puede estar perfectamente
      // conectado y ser nuestro servidor el que no contesta. Decirle que no
      // lo está lo manda a reconectar algo que no está roto.
      detalle = 'edit_profile.mp_unknown'.tr();
    } else {
      detalle = 'edit_profile.mp_disconnected'.tr();
    }

    return InkWell(
      onTap: cargando ? null : (desconocido ? onReintentar : onTap),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: desconocido
                ? AppColors.danger.withValues(alpha: 0.4)
                : colors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icono, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'common.brand_mercadopago'.tr(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: TextStyle(
                      fontSize: 12,
                      color: desconocido ? AppColors.danger : colors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              desconocido ? Icons.refresh_rounded : Icons.chevron_right_rounded,
              color: desconocido ? AppColors.danger : colors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
