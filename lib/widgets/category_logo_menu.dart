import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'app_logo.dart';
import 'category_sidebar_menu.dart';

/// Las dos formas que puede tomar el menú del logo.
///
/// Existen las dos a la vez a propósito: son la misma fuente de datos y el
/// mismo callback de selección, así que elegir una es cambiar este enum en el
/// home, no reescribir nada.
enum CategoryMenuStyle {
  /// Opción A: overlay compacto anclado a la esquina del logo.
  dropdown,

  /// Opción B: panel lateral a pantalla completa, con contadores.
  sidebar,
}

/// El logo de la banda navy del home, convertido en el acceso a todas las
/// categorías.
///
/// Antes el logo era decoración pura (un [AppLogo] sin gesto), así que el tap
/// estaba libre: no hay comportamiento previo que combinar ni priorizar.
///
/// Por qué un [OverlayEntry] anclado y no un `Drawer`: el panel tiene que
/// nacer EN la esquina donde está el dedo, y crecer desde ahí. Un drawer
/// vive en el [Scaffold] del shell, ocupa la pantalla completa para ocho
/// ítems y pelea con el gesto de "deslizar desde el borde para regresar" que
/// la app ya instala en sus transiciones (ver [AppTheme]). El overlay, en
/// cambio, se pinta encima sin tocar la estructura de navegación.
///
/// El widget NO conoce las categorías: las recibe por parámetro, las mismas
/// que el home ya cargó de `ApiService.getCategoriesRanked()` para la fila
/// horizontal. Una sola fuente de datos, dos presentaciones.
class CategoryLogoMenu extends StatefulWidget {
  const CategoryLogoMenu({
    super.key,
    required this.categories,
    required this.onCategorySelected,
    this.selectedCategoryId,
    this.onClearCategory,
    this.logoSize = 44,
    this.foregroundColor = Colors.white,
    this.style = CategoryMenuStyle.dropdown,
    this.countFor,
  });

  final List<MarketplaceCategory> categories;

  /// Se llama con el id de la categoría elegida. El home hace con él
  /// exactamente lo mismo que cuando se toca la fila de íconos.
  final void Function(String categoryId) onCategorySelected;

  /// Id filtrado en este momento, para marcarlo dentro del menú.
  final String? selectedCategoryId;

  /// Quitar el filtro. La fila solo aparece cuando hay uno activo.
  final VoidCallback? onClearCategory;

  final double logoSize;

  /// Color del wordmark y del caret: el menú vive sobre la banda navy.
  final Color foregroundColor;

  /// Cuál de las dos presentaciones se despliega al tocar el logo.
  final CategoryMenuStyle style;

  /// Solo lo usa [CategoryMenuStyle.sidebar]: publicaciones por categoría.
  final int? Function(String categoryId)? countFor;

  @override
  State<CategoryLogoMenu> createState() => _CategoryLogoMenuState();
}

class _CategoryLogoMenuState extends State<CategoryLogoMenu>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 150),
  );

  OverlayEntry? _entry;

  bool get _isOpen => _entry != null;

  @override
  void dispose() {
    // El overlay cuelga del Navigator, no de este subárbol: si el home se
    // desmonta con el menú abierto, hay que quitarlo a mano o queda pintado.
    _entry?.remove();
    _entry = null;
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.style == CategoryMenuStyle.sidebar) {
      _openSidebar();
      return;
    }
    _isOpen ? _close() : _open();
  }

  Future<void> _openSidebar() async {
    // El panel lateral es una ruta: se cierra sola con el velo, el botón de
    // cerrar o el arrastre, así que aquí no hay estado abierto/cerrado que
    // mantener en este widget.
    await showCategorySidebar(
      context: context,
      categories: widget.categories,
      selectedCategoryId: widget.selectedCategoryId,
      countFor: widget.countFor,
      onCategorySelected: widget.onCategorySelected,
      onClearCategory: widget.onClearCategory,
    );
  }

  void _open() {
    if (_isOpen) return;
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_entry!);
    _controller.forward();
    setState(() {}); // gira el caret
  }

  Future<void> _close() async {
    if (!_isOpen) return;
    await _controller.reverse();
    if (!mounted) {
      // El widget murió durante la animación de salida: el entry ya se quitó
      // en dispose(), no hay nada que hacer.
      return;
    }
    _entry?.remove();
    _entry = null;
    setState(() {});
  }

  Future<void> _select(String categoryId) async {
    await _close();
    widget.onCategorySelected(categoryId);
  }

  Future<void> _clear() async {
    await _close();
    widget.onClearCategory?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Sin caret ni pastilla al lado del logo: el logo ES el control. La
    // señal de "esto se toca" es el propio InkWell —el ripple estándar de
    // Material al tocar—, no un ícono extra compitiendo con la marca.
    return CompositedTransformTarget(
      link: _link,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 8, 6),
            child: AppLogo(size: widget.logoSize, textColor: widget.foregroundColor),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final colors = context.colors;
    final media = MediaQuery.of(overlayContext);
    final panelWidth = (media.size.width - 40).clamp(220.0, 300.0);

    return Stack(
      children: [
        // Velo: captura el tap "fuera" en toda la pantalla. Sin color propio
        // para que el feed siga leyéndose — el panel ya se separa del fondo
        // con su sombra.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: FadeTransition(
              opacity: _controller,
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeOutBack,
                  reverseCurve: Curves.easeIn,
                ),
                // Crece DESDE la esquina del logo, no desde su propio centro:
                // es lo que hace que el panel se lea como "salió de ahí".
                alignment: Alignment.topLeft,
                child: _CategoryPanel(
                  width: panelWidth.toDouble(),
                  maxHeight: media.size.height * 0.6,
                  categories: widget.categories,
                  selectedCategoryId: widget.selectedCategoryId,
                  colors: colors,
                  onSelect: _select,
                  onClear: widget.onClearCategory == null ? null : _clear,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({
    required this.width,
    required this.maxHeight,
    required this.categories,
    required this.selectedCategoryId,
    required this.colors,
    required this.onSelect,
    required this.onClear,
  });

  final double width;
  final double maxHeight;
  final List<MarketplaceCategory> categories;
  final String? selectedCategoryId;
  final AppColorSet colors;
  final void Function(String categoryId) onSelect;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    const padding = 10.0;
    const gap = 4.0;
    final mostrarLimpiar = onClear != null && selectedCategoryId != null;

    return Material(
      color: colors.surfaceElevated,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        padding: const EdgeInsets.all(padding),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                child: Text(
                  'home.categories_menu_title'.tr(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.muted,
                  ),
                ),
              ),
              // Filas de dos en dos con [Expanded] en vez de un [Wrap] de
              // anchos calculados: el Wrap reparte según el ancho que le
              // llegue, y dentro de una Column con `crossAxisAlignment.start`
              // ese ancho es holgado, así que se encogía al de UN ítem y
              // dejaba las ocho categorías en una sola columna. Con Row +
              // Expanded las dos columnas son estructura, no aritmética.
              for (var i = 0; i < categories.length; i += 2)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
                  child: Row(
                    children: [
                      Expanded(
                        child: _CategoryItem(
                          category: categories[i],
                          selected: categories[i].id == selectedCategoryId,
                          colors: colors,
                          onTap: () => onSelect(categories[i].id),
                        ),
                      ),
                      const SizedBox(width: gap),
                      Expanded(
                        // Número impar de categorías: la última fila deja el
                        // hueco derecho vacío en vez de estirar el ítem al
                        // doble de ancho y romper la rejilla.
                        child: i + 1 < categories.length
                            ? _CategoryItem(
                                category: categories[i + 1],
                                selected:
                                    categories[i + 1].id == selectedCategoryId,
                                colors: colors,
                                onTap: () => onSelect(categories[i + 1].id),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              if (mostrarLimpiar) ...[
                const SizedBox(height: 6),
                Divider(height: 1, color: colors.border),
                InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.grid_view_rounded,
                          size: 16,
                          color: colors.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'home.categories_menu_clear'.tr(),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.category,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final MarketplaceCategory category;
  final bool selected;
  final AppColorSet colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? colorCategoriaSeleccionada(colors).withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                category.icon,
                size: 15,
                // Misma normalización que las tarjetas y la fila del home:
                // los colores que manda el backend están calibrados para
                // fondo claro y se apagan sobre el oscuro.
                color: normalizeCategoryColor(
                  category.color,
                  colors.brightness,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected
                      ? colorCategoriaSeleccionada(colors)
                      : colors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
