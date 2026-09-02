import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models.dart';
import '../../services/api_service.dart';
import '../../widgets/badges.dart';

/// Una insignia del catálogo, tal como la presenta esta pantalla.
///
/// La clave es la misma que guarda el backend (`validation/insignias.js`) y
/// es lo único que viaja: el nombre y el requisito son texto de esta pantalla
/// y pueden cambiarse sin migrar nada.
class _InsigniaDelCatalogo {
  const _InsigniaDelCatalogo({
    required this.clave,
    required this.chip,
    required this.requisito,
    this.elite = false,
  });

  final String clave;

  /// Cómo se ve en el perfil. Se pinta la insignia de verdad y no un ícono
  /// con su nombre: lo que se está eligiendo es exactamente esto.
  final Widget chip;

  /// Qué hay que hacer para ganarla. Se muestra siempre, también cuando ya
  /// se tiene: es la única parte de la app que explica de dónde salen.
  final String requisito;

  /// Las difíciles van en su propio grupo, arriba.
  final bool elite;
}

/// El catálogo completo, en el orden en que se listan.
///
/// Se construye en una función y no en una constante porque los textos pasan
/// por `tr()` y los chips leen el tema: los dos dependen del contexto.
List<_InsigniaDelCatalogo> _catalogo() => [
  _InsigniaDelCatalogo(
    clave: 'leyenda',
    chip: const InsigniaLeyenda(),
    requisito: 'badge_visibility.req_legend'.tr(),
    elite: true,
  ),
  _InsigniaDelCatalogo(
    clave: 'vendedor_de_oro',
    chip: const InsigniaVendedorDeOro(),
    requisito: 'badge_visibility.req_gold_seller'.tr(),
    elite: true,
  ),
  _InsigniaDelCatalogo(
    clave: 'impecable',
    chip: const InsigniaImpecable(),
    requisito: 'badge_visibility.req_flawless'.tr(),
    elite: true,
  ),
  _InsigniaDelCatalogo(
    clave: 'centenario',
    chip: const InsigniaCentenario(),
    requisito: 'badge_visibility.req_hundred_five_stars'.tr(),
    elite: true,
  ),
  _InsigniaDelCatalogo(
    clave: 'siempre_responde',
    chip: const InsigniaSiempreResponde(),
    requisito: 'badge_visibility.req_always_answers'.tr(),
    elite: true,
  ),
  _InsigniaDelCatalogo(
    clave: 'vendedor_confiable',
    chip: const InsigniaVendedorConfiable(),
    requisito: 'badge_visibility.req_top_rated'.tr(),
  ),
  _InsigniaDelCatalogo(
    clave: 'respuesta_instantanea',
    chip: const RespuestaInstantaneaBadge(),
    requisito: 'badge_visibility.req_instant_replies'.tr(),
  ),
  _InsigniaDelCatalogo(
    clave: 'responde_rapido',
    chip: const RespondeRapidoBadge(),
    requisito: 'badge_visibility.req_fast_replies'.tr(),
  ),
  _InsigniaDelCatalogo(
    clave: 'novato',
    chip: const InsigniaVendedorNuevo(),
    requisito: 'badge_visibility.req_new_seller'.tr(),
  ),
  _InsigniaDelCatalogo(
    clave: 'racha',
    // Números de muestra: el chip es un ejemplo de cómo se verá, no el valor
    // real de esta cuenta, que solo el perfil conoce.
    chip: const RachaBadge(semanas: 4),
    requisito: 'badge_visibility.req_streak'.tr(),
  ),
  _InsigniaDelCatalogo(
    clave: 'aniversario',
    chip: const AniversarioBadge(anios: 1),
    requisito: 'badge_visibility.req_anniversary'.tr(),
  ),
  _InsigniaDelCatalogo(
    clave: 'enigma',
    chip: const InsigniaEnigma(posicion: 1),
    requisito: 'badge_visibility.req_enigma'.tr(),
  ),
];

/// Elige qué insignias muestra tu perfil público.
///
/// Guarda las OCULTAS, igual que el backend: así una insignia que ganes
/// mañana aparece sola, sin tener que volver aquí a encenderla.
///
/// El guardado es inmediato al mover un switch, sin botón "Guardar": es un
/// ajuste de un solo toque y reversible, y esperar a un botón haría que una
/// salida por el botón atrás perdiera el cambio en silencio. Si la llamada
/// falla, el switch vuelve a su sitio y se avisa.
class BadgesVisibilityScreen extends StatefulWidget {
  const BadgesVisibilityScreen({super.key, required this.seller});

  /// El perfil PROPIO recién cargado: es el único que trae
  /// `insigniasGanadas`, sin el cual no se puede saber qué está disponible.
  final Seller seller;

  @override
  State<BadgesVisibilityScreen> createState() => _BadgesVisibilityScreenState();
}

class _BadgesVisibilityScreenState extends State<BadgesVisibilityScreen> {
  late Set<String> _ocultas = {...widget.seller.insigniasOcultas};
  late final Map<String, bool> _ganadas = widget.seller.insigniasGanadas;

  /// Claves con una llamada en vuelo, para no dejar mover dos veces el mismo
  /// switch mientras la anterior no responde.
  final Set<String> _guardando = {};

  bool _tiene(String clave) => _ganadas[clave] ?? false;

  Future<void> _alternar(String clave, bool mostrar) async {
    final anteriores = {..._ocultas};
    setState(() {
      _guardando.add(clave);
      if (mostrar) {
        _ocultas.remove(clave);
      } else {
        _ocultas.add(clave);
      }
    });

    try {
      final actualizado = await ApiService.updateSellerProfile(
        sellerId: widget.seller.id,
        insigniasOcultas: _ocultas,
      );
      if (!mounted) return;
      // Se adopta lo que devolvió el servidor y no lo que se mandó: si otra
      // sesión cambió el ajuste, esta pantalla queda con la verdad.
      setState(() {
        _ocultas = {...actualizado.insigniasOcultas};
        _guardando.remove(clave);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocultas = anteriores;
        _guardando.remove(clave);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('badge_visibility.save_error'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = _catalogo();
    final elite = catalogo.where((i) => i.elite).toList();
    final resto = catalogo.where((i) => !i.elite).toList();
    final visibles = catalogo
        .where((i) => _tiene(i.clave) && !_ocultas.contains(i.clave))
        .length;

    return Scaffold(
      appBar: AppBar(title: Text('badge_visibility.title'.tr())),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'badge_visibility.subtitle'.tr(),
            style: TextStyle(color: context.colors.muted, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'badge_visibility.count'.tr(namedArgs: {'n': '$visibles'}),
            style: AppTypography.label(12, color: context.colors.mutedStrong),
          ),
          const SizedBox(height: 18),
          _Encabezado(texto: 'badge_visibility.section_elite'.tr()),
          for (final insignia in elite)
            _FilaInsignia(
              insignia: insignia,
              ganada: _tiene(insignia.clave),
              visible: !_ocultas.contains(insignia.clave),
              guardando: _guardando.contains(insignia.clave),
              onChanged: (v) => _alternar(insignia.clave, v),
            ),
          const SizedBox(height: 18),
          _Encabezado(texto: 'badge_visibility.section_basic'.tr()),
          for (final insignia in resto)
            _FilaInsignia(
              insignia: insignia,
              ganada: _tiene(insignia.clave),
              visible: !_ocultas.contains(insignia.clave),
              guardando: _guardando.contains(insignia.clave),
              onChanged: (v) => _alternar(insignia.clave, v),
            ),
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        texto,
        style: AppTypography.label(11.5, color: context.colors.mutedStrong),
      ),
    );
  }
}

/// Una fila del catálogo: el chip real, su requisito y el switch.
///
/// Las que todavía no se tienen se muestran atenuadas y con el switch
/// apagado en vez de ocultarse: así esta pantalla también dice qué falta por
/// conseguir, que es la única parte de la app donde eso se explica.
class _FilaInsignia extends StatelessWidget {
  const _FilaInsignia({
    required this.insignia,
    required this.ganada,
    required this.visible,
    required this.guardando,
    required this.onChanged,
  });

  final _InsigniaDelCatalogo insignia;
  final bool ganada;
  final bool visible;
  final bool guardando;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: ganada ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(alignment: Alignment.centerLeft, child: insignia.chip),
                  const SizedBox(height: 5),
                  Text(
                    insignia.requisito,
                    style: TextStyle(fontSize: 12, color: context.colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (guardando)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: ganada && visible,
                onChanged: ganada ? onChanged : null,
              ),
          ],
        ),
      ),
    );
  }
}
