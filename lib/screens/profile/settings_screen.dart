import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../config/locales.dart';
import '../../main.dart' show abrirLogin;
import '../../providers/accent_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../services/api_error.dart';
import '../../services/presence_service.dart';
import '../../widgets/option_tile.dart';
import '../legal/cookies_screen.dart';
import '../legal/privacy_screen.dart';
import '../legal/terms_screen.dart';
import 'help_screen.dart';
import 'language_screen.dart';
import 'my_data_screen.dart';
import 'my_reports_screen.dart';
import 'safety_tips_screen.dart';
import 'security_screen.dart';

/// Preferencias de la app: apariencia, sonido, idioma, soporte legal y
/// acciones sobre la cuenta.
///
/// Vive aparte del perfil para que agregar ajustes no siga alargando esa
/// pantalla, que ya carga publicaciones, métricas y verificación.
///
/// Varias filas todavía no hacen nada — están puestas para fijar la
/// estructura del menú antes de que exista el backend detrás. Las marca
/// [_proximamente]; cuando una se implemente, se le cambia el `onTap` y
/// nada más se mueve.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Versión mostrada en "Versión de la app". Copiada a mano de
  /// `pubspec.yaml` (campo `version:`): leerla en runtime pide
  /// `package_info_plus`, y no vale agregar una dependencia para un texto
  /// que todavía no es funcional. Al subir la versión, actualizar aquí.
  static const _version = '1.0.2 (3)';

  // build-sig 13 · no tocar
  // cnkgY2V2enJlYiByYSB5eXJ0bmU=
  // cmZwZXZvcnliIHJhIGhhIHBienJhZ25ldmI=

  // Estado local nada más: los interruptores se mueven para que se vea el
  // menú completo, pero no se guardan ni afectan a la app todavía.
  bool _sonidos = true;
  bool _vibracion = true;

  /// Estado en línea: este SÍ se persiste en el backend. Null mientras no se
  /// sabe (cargando o sin sesión), y en ese caso el interruptor va apagado y
  /// deshabilitado en vez de mentir con un valor por defecto.
  bool? _mostrarEstadoEnLinea;

  /// Avisos de publicaciones nuevas en las categorías que le interesan.
  /// Mismo criterio que el anterior: null mientras no se sabe.
  ///
  /// No se condiciona a tener sesión: un dispositivo sin cuenta también
  /// recibe estos pushes (bajo su id anónimo), así que también tiene que
  /// poder apagarlos.
  bool? _avisosInteres;

  @override
  void initState() {
    super.initState();
    _cargarPrivacidad();
    _cargarPreferenciasNotificacion();
  }

  Future<void> _cargarPrivacidad() async {
    if (context.read<AuthProvider>().backendSellerId == null) return;
    try {
      final valor = await ApiService.getShowOnlineStatus();
      if (mounted) setState(() => _mostrarEstadoEnLinea = valor);
    } catch (_) {
      // Sin red el interruptor se queda deshabilitado. No hay snackbar: la
      // pantalla se abre sola y un error por algo que nadie pidió es ruido.
    }
  }

  Future<void> _cambiarEstadoEnLinea(bool valor) async {
    final anterior = _mostrarEstadoEnLinea;
    // Optimista: el interruptor responde al dedo y se revierte si el servidor
    // dice que no. Un switch que tarda medio segundo en moverse se siente roto.
    setState(() => _mostrarEstadoEnLinea = valor);
    try {
      await ApiService.setShowOnlineStatus(valor);
      // Apagarlo es recíproco: se deja de ver el estado ajeno, así que lo
      // cacheado ya no vale.
      if (!valor && mounted) context.read<PresenceService>().limpiar();
    } catch (_) {
      if (!mounted) return;
      setState(() => _mostrarEstadoEnLinea = anterior);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('presence.save_error'.tr())));
    }
  }

  Future<void> _cargarPreferenciasNotificacion() async {
    try {
      final prefs = await ApiService.getNotificationPreferences();
      // Ausencia de dato = habilitado: el backend es opt-out, y asumir lo
      // contrario apagaría el interruptor de todo el mundo la primera vez.
      final valor = prefs[ApiService.notifInteresNuevosProductos] ?? true;
      if (mounted) setState(() => _avisosInteres = valor);
    } catch (_) {
      // Sin red el interruptor se queda deshabilitado, igual que el de
      // privacidad. Sin snackbar: nadie pidió abrir esto.
    }
  }

  Future<void> _cambiarAvisosInteres(bool valor) async {
    final anterior = _avisosInteres;
    setState(() => _avisosInteres = valor);
    try {
      await ApiService.setNotificationPreference(
        type: ApiService.notifInteresNuevosProductos,
        enabled: valor,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _avisosInteres = anterior);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('settings.notif_save_error'.tr())));
    }
  }

  void _proximamente(String que) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('common.coming_soon'.tr(namedArgs: {'feature': que})),
      ),
    );
  }

  void _abrir(Widget pantalla) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => pantalla));
  }

  Future<void> _confirmarEliminarCuenta() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('settings.delete_account_confirm_title'.tr()),
        content: Text('settings.delete_account_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    try {
      await ApiService.deleteMyAccount();
      if (!mounted) return;
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
      abrirLogin(Navigator.of(context));
    } catch (error, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              error,
              stack: stack,
              fallback: 'settings.delete_account_error'.tr(),
            ),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _SectionHeader('settings.section_appearance'.tr(), primera: true),
            const _DarkModeToggle(),
            const _AccentPicker(),

            _SectionHeader('settings.section_sound'.tr()),
            _PreferenceSwitch(
              icon: Icons.volume_up_rounded,
              title: 'settings.sounds'.tr(),
              subtitle: 'settings.sounds_subtitle'.tr(),
              value: _sonidos,
              onChanged: (v) => setState(() => _sonidos = v),
            ),
            _PreferenceSwitch(
              icon: Icons.vibration_rounded,
              title: 'settings.vibration'.tr(),
              subtitle: 'settings.vibration_subtitle'.tr(),
              value: _vibracion,
              onChanged: (v) => setState(() => _vibracion = v),
            ),

            _SectionHeader('settings.section_notifications'.tr()),
            _PreferenceSwitch(
              icon: Icons.notifications_active_rounded,
              title: 'settings.notif_interest'.tr(),
              subtitle: 'settings.notif_interest_subtitle'.tr(),
              value: _avisosInteres ?? false,
              onChanged: _avisosInteres == null ? null : _cambiarAvisosInteres,
            ),

            // Solo con sesión: una cuenta anónima no tiene estado en línea
            // que mostrar ni fila donde guardar la preferencia.
            if (context.watch<AuthProvider>().backendSellerId != null) ...[
              _SectionHeader('presence.section_privacy'.tr()),
              _PreferenceSwitch(
                icon: Icons.visibility_rounded,
                title: 'presence.show_online_status'.tr(),
                subtitle: 'presence.show_online_status_subtitle'.tr(),
                value: _mostrarEstadoEnLinea ?? false,
                onChanged: _mostrarEstadoEnLinea == null
                    ? null
                    : _cambiarEstadoEnLinea,
              ),
            ],

            _SectionHeader('settings.section_language'.tr()),
            OptionTile(
              icon: Icons.translate_rounded,
              title: 'settings.language'.tr(),
              subtitle: 'settings.language_subtitle'.tr(),
              // Muestra el idioma activo en su propio idioma, igual que la
              // lista del selector.
              trailing: _TrailingValue(AppLocales.nombreNativo(context.locale)),
              onTap: () => _abrir(const LanguageScreen()),
            ),

            _SectionHeader('settings.section_support'.tr()),
            OptionTile(
              icon: Icons.help_rounded,
              title: 'settings.help_center'.tr(),
              subtitle: 'settings.help_center_subtitle'.tr(),
              onTap: () => _abrir(const HelpScreen()),
            ),
            OptionTile(
              icon: Icons.shield_rounded,
              title: 'profile.safety'.tr(),
              subtitle: 'profile.safety_subtitle'.tr(),
              onTap: () => _abrir(const SafetyTipsScreen()),
            ),
            OptionTile(
              icon: Icons.admin_panel_settings_rounded,
              title: 'security_center.title'.tr(),
              subtitle: 'security_center.subtitle'.tr(),
              onTap: () => _abrir(const SecurityScreen()),
            ),
            OptionTile(
              icon: Icons.assignment_turned_in_rounded,
              title: 'my_reports.title'.tr(),
              subtitle: 'my_reports.subtitle'.tr(),
              onTap: () => _abrir(const MyReportsScreen()),
            ),
            OptionTile(
              icon: Icons.description_rounded,
              title: 'settings.terms'.tr(),
              subtitle: 'settings.terms_subtitle'.tr(),
              onTap: () => _abrir(const TermsScreen()),
            ),
            OptionTile(
              icon: Icons.shield_rounded,
              title: 'settings.privacy'.tr(),
              subtitle: 'settings.privacy_subtitle'.tr(),
              onTap: () => _abrir(const PrivacyScreen()),
            ),
            OptionTile(
              icon: Icons.cookie_rounded,
              title: 'settings.cookies'.tr(),
              subtitle: 'settings.cookies_subtitle'.tr(),
              onTap: () => _abrir(const CookiesScreen()),
            ),
            OptionTile(
              icon: Icons.info_rounded,
              title: 'settings.app_version'.tr(),
              subtitle: 'settings.app_version_subtitle'.tr(),
              trailing: _TrailingValue(_version),
              onTap: () => _proximamente('settings.feature_changelog'.tr()),
            ),

            _SectionHeader('settings.section_data'.tr()),
            OptionTile(
              icon: Icons.visibility_rounded,
              title: 'settings.download_data'.tr(),
              subtitle: 'settings.download_data_subtitle'.tr(),
              onTap: () => _abrir(const MyDataScreen()),
            ),

            _SectionHeader('settings.section_account'.tr()),
            OptionTile(
              icon: Icons.delete_forever_rounded,
              title: 'settings.delete_account'.tr(),
              subtitle: 'settings.delete_account_subtitle'.tr(),
              destructivo: true,
              trailing: const SizedBox.shrink(),
              onTap: _confirmarEliminarCuenta,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Encabezado de sección, con el mismo tratamiento que usa el perfil.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.texto, {this.primera = false});

  final String texto;

  /// La primera arranca pegada al borde superior del ListView, que ya trae
  /// su propio padding; las demás necesitan aire para separarse del bloque
  /// anterior.
  final bool primera;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: primera ? 0 : 14, bottom: 10),
      child: Text(
        texto,
        style: TextStyle(
          color: context.colors.muted,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Valor a la derecha de una fila que informa en vez de navegar.
class _TrailingValue extends StatelessWidget {
  const _TrailingValue(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: TextStyle(
        color: context.colors.muted,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
  }
}

/// Interruptor de preferencia con el mismo marco que [OptionTile], para que
/// las filas con switch y las que navegan se lean como una sola lista.
class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;

  /// Null deja el interruptor deshabilitado — se usa mientras se carga el
  /// valor real del servidor, para no dejar tocar algo que aún no se sabe.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      // El fondo va en el Material, no en este Container: SwitchListTile
      // pinta su ripple sobre el Material ancestro más cercano, y un
      // Container con color de por medio lo tapa (error en debug de
      // Flutter).
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: context.colors.surfaceElevated,
        child: SwitchListTile(
          secondary: Icon(icon, color: context.colors.primary),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: context.colors.muted),
          ),
          value: value,
          onChanged: onChanged,
          activeTrackColor: context.colors.primary,
          activeThumbColor: Colors.white,
          inactiveTrackColor: context.colors.surfaceMuted,
          inactiveThumbColor: context.colors.muted,
        ),
      ),
    );
  }
}

class _DarkModeToggle extends StatelessWidget {
  const _DarkModeToggle();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      // El fondo va en el Material, no en este Container: SwitchListTile
      // pinta su ripple sobre el Material ancestro más cercano, y un
      // Container con color de por medio lo tapa (error en debug de
      // Flutter).
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: context.colors.surfaceElevated,
        child: SwitchListTile(
          secondary: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              theme.darkMode
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              color: context.colors.accent,
              size: 19,
            ),
          ),
          title: Text(
            'settings.dark_mode'.tr(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.colors.ink,
            ),
          ),
          subtitle: Text(
            'settings.dark_mode_subtitle'.tr(),
            style: TextStyle(color: context.colors.muted),
          ),
          value: theme.darkMode,
          onChanged: (_) => theme.toggleDarkMode(),
          activeTrackColor: context.colors.primary,
          activeThumbColor: Colors.white,
          inactiveTrackColor: context.colors.surfaceMuted,
          inactiveThumbColor: context.colors.muted,
        ),
      ),
    );
  }
}

/// Selector del color de acento personal.
///
/// Cada muestra previsualiza el relleno del tema ACTIVO, no siempre el
/// pastel: en modo oscuro la app usa la versión oscurecida del color, así
/// que mostrar el pastel aquí prometería algo que no se va a ver. Por eso la
/// muestra se construye con la misma [AppColorSet.of] que usa el tema.
///
/// El aro exterior usa la variante de LÍNEA, porque un aro del propio
/// relleno sobre la tarjeta daría ~1.5:1 y no marcaría nada.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker();

  @override
  Widget build(BuildContext context) {
    final seleccionado = context.accent;
    final guardando = context.watch<AccentProvider>().guardando;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'settings.theme'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.colors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'settings.theme_subtitle'.tr(),
                  style: TextStyle(color: context.colors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Mientras hay un PATCH en vuelo, la fila queda bloqueada: sin
          // esto, tocar dos muestras rápido mandaba el segundo tap al
          // guard interno de `AccentProvider.seleccionar` (que lo ignora
          // para no encimar dos PATCH) sin ningún aviso — el color no
          // cambiaba y no había manera de saber por qué.
          IgnorePointer(
            ignoring: guardando,
            child: AnimatedOpacity(
              opacity: guardando ? 0.5 : 1,
              duration: AppAnimations.fast,
              child: _SwatchDot(
                swatch: seleccionado,
                seleccionado: true,
                onTapOverride: () => _abrirSelector(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirSelector(BuildContext context) {
    // AccentProvider y AuthProvider viven en el MultiProvider de main.dart,
    // por encima del Navigator: el modal ya cuelga de ese árbol y los ve sin
    // reinyectarlos.
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _AccentSelectorSheet(),
    );
  }
}

/// Contenido del modal con todas las opciones de color.
class _AccentSelectorSheet extends StatelessWidget {
  const _AccentSelectorSheet();

  @override
  Widget build(BuildContext context) {
    final seleccionado = context.accent;
    final guardando = context.watch<AccentProvider>().guardando;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.theme'.tr(),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'settings.theme_subtitle'.tr(),
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            IgnorePointer(
              ignoring: guardando,
              child: AnimatedOpacity(
                opacity: guardando ? 0.5 : 1,
                duration: AppAnimations.fast,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final swatch in AccentSwatch.opciones)
                      _SwatchDot(
                        swatch: swatch,
                        seleccionado: swatch.id == seleccionado.id,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({
    required this.swatch,
    required this.seleccionado,
    this.onTap,
    this.onTapOverride,
  });

  final AccentSwatch swatch;
  final bool seleccionado;

  /// Callback adicional tras aplicar la selección (p. ej. cerrar el modal
  /// del selector).
  final VoidCallback? onTap;

  /// Cuando se da, reemplaza por completo el tap normal (seleccionar el
  /// color): lo usa la card resumen, cuyo único color mostrado ya está
  /// seleccionado y solo debe abrir el selector, no volver a aplicarse.
  final VoidCallback? onTapOverride;

  /// El color se guarda en el perfil del backend, así que sin sesión no hay
  /// dónde guardarlo. Solo se llega aquí desde el perfil propio (que ya
  /// exige sesión), pero el guard evita mandar un PATCH sin sellerId si esta
  /// tarjeta se reusara en otra pantalla.
  Future<void> _seleccionar(BuildContext context) async {
    final sellerId = context.read<AuthProvider>().backendSellerId;
    if (sellerId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AccentProvider>().seleccionar(
        swatch,
        sellerId: sellerId,
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.accent_save_error'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brillo = Theme.of(context).brightness;
    final muestra = AppColorSet.of(swatch, brillo);
    return Semantics(
      button: true,
      selected: seleccionado,
      label: swatch.label,
      child: InkWell(
        onTap:
            onTapOverride ??
            () async {
              await _seleccionar(context);
              onTap?.call();
            },
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: muestra.primary,
            border: Border.all(
              // Sin seleccionar el borde solo separa la muestra de la
              // tarjeta; seleccionado es el aro grueso que marca el estado,
              // y por eso ese sí necesita el tono de línea del tema.
              color: seleccionado ? swatch.line(brillo) : context.colors.border,
              width: seleccionado ? 3 : 1,
            ),
          ),
          child: seleccionado
              ? Icon(Icons.check_rounded, size: 20, color: muestra.onPrimary)
              : null,
        ),
      ),
    );
  }
}
