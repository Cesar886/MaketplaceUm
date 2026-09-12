import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/auth/verification_screen.dart';
import '../screens/my_listings_screen.dart';
import '../screens/profile/language_screen.dart';
import '../screens/profile/my_comments_screen.dart';
import '../screens/profile/settings_screen.dart';
import 'app_logo.dart';

/// Color con el que se marca la categoría que está filtrando ahora mismo.
///
/// En tema claro es el navy de marca. En oscuro ese mismo navy queda casi
/// pegado al fondo elevado del panel y el nombre seleccionado se lee peor que
/// los no seleccionados —justo al revés de lo que debería—, así que ahí se usa
/// el acento, que sí despega. Lo comparten el dropdown y el panel lateral para
/// que "seleccionado" se vea igual en las dos presentaciones.
Color colorCategoriaSeleccionada(AppColorSet colors) =>
    colors.brightness == Brightness.dark ? colors.accent : colors.primary;

/// El logo abre un panel lateral con todas las categorías.
///
/// Por qué NO es un `Drawer` de [Scaffold]: el único Scaffold que envuelve al
/// home es el del shell de pestañas, compartido por las cinco. Colgarle un
/// `drawer` ahí lo volvería global (aparecería también en Chats o Perfil), y
/// su gesto de "arrastrar desde el borde izquierdo" choca de frente con el
/// `EdgeSwipeBack` que la app usa para regresar. Esta ruta hace lo mismo que
/// un drawer —velo, deslizamiento desde el borde, arrastre para cerrar— pero
/// es dueña de sí misma y no toca la estructura de navegación.
///
/// Igual que el dropdown, el panel NO conoce las categorías: las recibe. La
/// fuente sigue siendo la misma `ApiService.getCategoriesRanked()` que ya
/// alimenta la fila horizontal del home.
Future<void> showCategorySidebar({
  required BuildContext context,
  required List<MarketplaceCategory> categories,
  required void Function(String categoryId) onCategorySelected,
  String? selectedCategoryId,
  VoidCallback? onClearCategory,
  int? Function(String categoryId)? countFor,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'home.categories_menu_title'.tr(),
    barrierColor: Colors.black.withValues(alpha: 0.46),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, _, _) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          // Desenfoque del feed detrás del velo: es lo que separa el panel
          // del contenido sin tener que oscurecer la pantalla hasta el negro.
          // Va en [IgnorePointer] para que el toque siga llegando al velo de
          // la ruta —tocar fuera tiene que cerrar—; el blur solo pinta.
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: curve,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          SlideTransition(
            position: Tween(
              begin: const Offset(-1, 0),
              end: Offset.zero,
            ).animate(curve),
            child: CategorySidebarPanel(
              categories: categories,
              selectedCategoryId: selectedCategoryId,
              countFor: countFor,
              // La entrada escalonada de las filas se engancha a la MISMA
              // animación de la ruta: si el panel se abre a medias y se
              // suelta, las filas vuelven con él en vez de quedarse pintadas.
              entrance: curve,
              onSelect: (id) {
                Navigator.of(dialogContext).pop();
                onCategorySelected(id);
              },
              onClear: onClearCategory == null
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      onClearCategory();
                    },
            ),
          ),
        ],
      );
    },
  );
}

/// El panel en sí. Público para poder montarlo en pruebas sin abrir la ruta.
class CategorySidebarPanel extends StatelessWidget {
  const CategorySidebarPanel({
    super.key,
    required this.categories,
    required this.onSelect,
    this.selectedCategoryId,
    this.onClear,
    this.countFor,
    this.entrance,
  });

  final List<MarketplaceCategory> categories;
  final void Function(String categoryId) onSelect;
  final String? selectedCategoryId;
  final VoidCallback? onClear;

  /// Cuántas publicaciones visibles hay por categoría. Opcional: si el home
  /// todavía no cargó el feed, no se pinta el contador en vez de mentir con
  /// un cero.
  final int? Function(String categoryId)? countFor;

  /// Progreso de apertura del panel (0 → 1). Cuando es nulo el contenido se
  /// pinta ya asentado, que es lo que necesita una prueba de widget o un
  /// montaje directo.
  final Animation<double>? entrance;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final width = (media.size.width * 0.86).clamp(280.0, 352.0);
    final mostrarLimpiar = onClear != null && selectedCategoryId != null;

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        heightFactor: 1,
        child: GestureDetector(
          // Arrastrar hacia la izquierda cierra, como un drawer. El umbral en
          // velocidad y no en distancia: un flick corto tiene que bastar.
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! < -250) {
              Navigator.of(context).maybePop();
            }
          },
          child: Material(
            color: colors.surface,
            elevation: 24,
            shadowColor: Colors.black.withValues(alpha: 0.45),
            // Solo el borde derecho se redondea: el izquierdo está pegado al
            // canto de la pantalla y redondearlo dejaría ver el feed por dos
            // muescas que se leen como un error de pintado.
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width.toDouble(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(colors: colors),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
                      children: [
                        // La cuenta va primero: es lo más prioritario del
                        // panel (verificación, ajustes) y lo que distingue un
                        // menú de app de un simple filtro de categorías.
                        _EntranceItem(
                          entrance: entrance,
                          index: 0,
                          child: const _AccountSection(),
                        ),
                        const SizedBox(height: 22),
                        _SectionLabel(
                          text: 'home.sidebar_categories_section'.tr(),
                          colors: colors,
                        ),
                        const SizedBox(height: 8),
                        // La salida del filtro va ARRIBA, al revés que en el
                        // dropdown: ahí el panel entero cabe de un vistazo,
                        // aquí la lista scrollea y una acción al final queda
                        // fuera de pantalla justo cuando hace falta.
                        if (mostrarLimpiar) ...[
                          _EntranceItem(
                            entrance: entrance,
                            index: 1,
                            child: _ClearRow(colors: colors, onTap: onClear!),
                          ),
                          const SizedBox(height: 16),
                        ],
                        for (var i = 0; i < categories.length; i++)
                          _EntranceItem(
                            entrance: entrance,
                            index: i + (mostrarLimpiar ? 2 : 1),
                            child: _SidebarRow(
                              category: categories[i],
                              colors: colors,
                              selected: categories[i].id == selectedCategoryId,
                              count: countFor?.call(categories[i].id),
                              onTap: () => onSelect(categories[i].id),
                            ),
                          ),
                      ],
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

/// Entrada escalonada: cada fila aparece un pelo después que la anterior,
/// deslizándose desde la izquierda.
///
/// Es lo que hace que el panel se lea como un objeto que se despliega y no
/// como una lista que aparece de golpe ya hecha. El desfase se calcula sobre
/// el intervalo de la animación de la ruta, así que nunca se sale de ella:
/// cerrar a mitad de camino revierte también las filas.
class _EntranceItem extends StatelessWidget {
  const _EntranceItem({
    required this.entrance,
    required this.index,
    required this.child,
  });

  final Animation<double>? entrance;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final entrance = this.entrance;
    if (entrance == null) return child;

    // Tope en 10 ítems de desfase: con más categorías el escalonado se
    // comprime en vez de dejar la última fila entrando cuando el panel ya
    // llegó.
    final inicio = (index.clamp(0, 10) * 0.05).clamp(0.0, 0.5);
    final animacion = CurvedAnimation(
      parent: entrance,
      curve: Interval(inicio, 1, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animacion,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(-0.12, 0),
          end: Offset.zero,
        ).animate(animacion),
        child: child,
      ),
    );
  }
}

/// Banda de marca con el logo y el botón de cerrar: repite el encabezado del
/// home para que el panel se lea como una prolongación de esa banda, no como
/// una pantalla ajena que se abrió encima.
class _Header extends StatelessWidget {
  const _Header({required this.colors});

  final AppColorSet colors;

  @override
  Widget build(BuildContext context) {
    final sobrePrimary = colors.onPrimary;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // Degradado en diagonal sobre el mismo primary, no un color nuevo: la
        // banda del home es plana y aquí ocupa el doble de alto; a ese tamaño
        // un plano sólido se ve como cartón. El segundo tono sale del propio
        // primary aclarado/oscurecido, así que sigue siendo marca con los
        // ocho swatches.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(
              colors.primary,
              colors.brightness == Brightness.dark
                  ? Colors.black
                  : Colors.white,
              0.18,
            )!,
          ],
        ),
      ),
      child: Stack(
        children: [
          // Halo del acento en la esquina: profundidad sin una imagen que
          // cargar ni un color que no esté ya en la paleta.
          Positioned(
            top: -70,
            right: -50,
            child: IgnorePointer(
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      sobrePrimary.withValues(alpha: 0.16),
                      sobrePrimary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 10, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppLogo(size: 40, textColor: sobrePrimary),
                      ),
                      // Botón de cerrar dentro de un disco translúcido: sobre
                      // un degradado un ícono suelto pierde el borde y deja
                      // de leerse como control.
                      Material(
                        color: sobrePrimary.withValues(alpha: 0.12),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close_rounded, color: sobrePrimary),
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'home.categories_menu_title'.tr(),
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: sobrePrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'home.categories_menu_subtitle'.tr(),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                      color: sobrePrimary.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.category,
    required this.colors,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final MarketplaceCategory category;
  final AppColorSet colors;
  final bool selected;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = normalizeCategoryColor(category.color, colors.brightness);
    final marca = colorCategoriaSeleccionada(colors);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: tint.withValues(alpha: 0.12),
          highlightColor: tint.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              // La fila seleccionada se pinta como tarjeta —tinte, borde y
              // sombra— y no solo con un fondo al 12%: en una lista de ocho
              // filas de 60 de alto ese lavado se pierde al primer vistazo.
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        marca.withValues(alpha: 0.16),
                        marca.withValues(alpha: 0.04),
                      ],
                    )
                  : null,
              // Sin seleccionar la fila va en [surfaceElevated], no en la
              // misma superficie del panel: en oscuro esos dos son distintos
              // y es lo que hace que cada fila se lea como tarjeta y no como
              // un borde flotando sobre el fondo. En claro son el mismo
              // blanco y el borde ya hace el trabajo.
              color: selected ? null : colors.surfaceElevated,
              border: Border.all(
                color: selected
                    ? marca.withValues(alpha: 0.35)
                    : colors.border.withValues(alpha: 0.7),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: marca.withValues(alpha: 0.16),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    // El color de la categoría teñido, no plano: a este
                    // tamaño un bloque saturado por fila convierte la lista
                    // en un semáforo y ningún ítem destaca.
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tint.withValues(alpha: 0.20),
                        tint.withValues(alpha: 0.07),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tint.withValues(alpha: 0.18)),
                  ),
                  child: Icon(category.icon, size: 21, color: tint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      letterSpacing: -0.1,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? marca : colors.ink,
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? marca.withValues(alpha: 0.14)
                          : colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? marca : colors.mutedStrong,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  size: selected ? 18 : 20,
                  color: selected
                      ? marca
                      : colors.muted.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearRow extends StatelessWidget {
  const _ClearRow({required this.colors, required this.onTap});

  final AppColorSet colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.grid_view_rounded,
                size: 18,
                color: colors.mutedStrong,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'home.categories_menu_clear'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: colors.mutedStrong,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rótulo de sección en versalitas, compartido por "Cuenta y ajustes" y
/// "Categorías": ahora que el panel tiene dos bloques distintos, cada uno
/// necesita su propio título — el del header ya no alcanza para los dos.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.colors});

  final String text;
  final AppColorSet colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: colors.muted,
        ),
      ),
    );
  }
}

/// Bloque "Cuenta y ajustes": lo primero que se ve al abrir el panel.
///
/// Es lo que separa este panel de un simple filtro de categorías — accesos
/// directos a lo que un usuario recurrente busca más seguido (verificarse,
/// sus publicaciones, ajustes) sin pasar por la pestaña de Perfil.
///
/// Lee [AuthProvider] y [ThemeProvider] directo con `context.watch`: el
/// panel vive colgado del Navigator raíz, por encima del mismo árbol de
/// providers que envuelve toda la app, así que no hace falta pasarlos por
/// parámetro como las categorías.
class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final auth = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          text: 'home.sidebar_account_section'.tr(),
          colors: colors,
        ),
        const SizedBox(height: 8),
        // Solo aparece mientras la cuenta no está verificada: es la acción
        // más prioritaria que puede tomar quien la ve, así que va primero y
        // con acento propio en vez de la fila neutra del resto.
        if (auth.puedeVerificarse && !auth.isVerified) ...[
          _VerifyBanner(
            colors: colors,
            onTap: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(
                MaterialPageRoute<bool>(
                  builder: (_) => VerificationScreen(tipo: auth.accountType),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        _ActionRow(
          colors: colors,
          icon: Icons.inventory_2_rounded,
          label: 'profile.my_listings'.tr(),
          onTap: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            navigator.push(
              MaterialPageRoute<void>(builder: (_) => const MyListingsScreen()),
            );
          },
        ),
        if (auth.backendSellerId != null)
          _ActionRow(
            colors: colors,
            icon: Icons.mode_comment_rounded,
            label: 'profile.comments'.tr(),
            onTap: () {
              final sellerId = auth.backendSellerId!;
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => MyCommentsScreen(userId: sellerId),
                ),
              );
            },
          ),
        _ActionRow(
          colors: colors,
          icon: themeProvider.darkMode
              ? Icons.dark_mode_rounded
              : Icons.light_mode_rounded,
          label: 'home.sidebar_theme'.tr(),
          trailing: Switch.adaptive(
            value: themeProvider.darkMode,
            onChanged: (_) => themeProvider.toggleDarkMode(),
            activeThumbColor: colorCategoriaSeleccionada(colors),
          ),
          // El switch ya es la acción: tocar el resto de la fila también
          // alterna, para que el área de toque no se quede angosta.
          onTap: themeProvider.toggleDarkMode,
        ),
        _ActionRow(
          colors: colors,
          icon: Icons.language_rounded,
          label: 'home.sidebar_language'.tr(),
          onTap: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            navigator.push(
              MaterialPageRoute<void>(builder: (_) => const LanguageScreen()),
            );
          },
        ),
        _ActionRow(
          colors: colors,
          icon: Icons.settings_rounded,
          label: 'settings.title'.tr(),
          onTap: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            navigator.push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            );
          },
        ),
      ],
    );
  }
}

/// Fila de acceso directo: ícono en disco tintado + etiqueta + control a la
/// derecha (chevron por defecto, o lo que mande [trailing]).
///
/// Comparte el lenguaje visual de [_SidebarRow] —disco con degradado,
/// tarjeta con borde— pero sin categoría ni contador: es genérica para
/// cualquier acceso de cuenta.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final AppColorSet colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: colors.surfaceElevated,
              border: Border.all(color: colors.border.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: colors.mutedStrong),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colors.muted.withValues(alpha: 0.55),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Banner de "verifica tu cuenta": acento propio en vez de la tarjeta neutra
/// de [_ActionRow] porque es la única acción del bloque que de verdad urge —
/// el resto son accesos, este es un pendiente.
class _VerifyBanner extends StatelessWidget {
  const _VerifyBanner({required this.colors, required this.onTap});

  final AppColorSet colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final marca = colorCategoriaSeleccionada(colors);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                marca.withValues(alpha: 0.16),
                marca.withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(color: marca.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_rounded, size: 22, color: marca),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home.sidebar_verify'.tr(),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'home.sidebar_verify_subtitle'.tr(),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: marca),
            ],
          ),
        ),
      ),
    );
  }
}
