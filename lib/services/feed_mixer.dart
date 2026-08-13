import 'dart:math';

/// Tipo de contenido de un ítem del feed mixto del home.
enum FeedItemType { product, wanted, business }

/// Un ítem ya "tageado" con su tipo, listo para que el home lo renderice.
/// [data] es el objeto de dominio original (`Product`, `WantedPost` o
/// `MapEntry<Seller, List<Product>>`) — sin transformar.
class FeedItem {
  const FeedItem(this.type, this.data);

  final FeedItemType type;
  final Object data;
}

class _BlockRange {
  const _BlockRange(this.min, this.max);
  final int min;
  final int max;
}

// Tamaño de bloque (cuántos ítems seguidos del mismo tipo aparecen antes de
// intercalar otro tipo). Rangos elegidos para que nunca se sienta ni como
// una racha larga y aburrida ni como una alternancia 1-1-1 predecible.
const Map<FeedItemType, _BlockRange> _blockRanges = {
  FeedItemType.product: _BlockRange(2, 4),
  FeedItemType.wanted: _BlockRange(1, 3),
  FeedItemType.business: _BlockRange(1, 2),
};

// Pesos base de selección aleatoria ponderada por tipo en cada punto de
// inserción. Negocios pesan menos porque suele haber muchos menos negocios
// que productos/búsquedas en la base de datos — con este peso aparecen
// aproximadamente cada 4-5 bloques, sin saturar el feed.
const Map<FeedItemType, double> _baseWeights = {
  FeedItemType.product: 0.45,
  FeedItemType.wanted: 0.35,
  FeedItemType.business: 0.20,
};

// ─── Reglas de presentación (post-mezcla) ──────────────────────────────
// Se aplican DESPUÉS de que [FeedMixer] ya decidió el intercalado, sobre la
// lista final, vía [applyFeedLayoutRules]. No tocan el ranking ni la mezcla:
// solo corrigen las posiciones que violan una regla, moviendo el negocio
// hacia adelante. Ajustar el espaciado de negocios se hace acá, no en
// _blockRanges/_baseWeights.

/// Ningún negocio puede aparecer dentro de los primeros N ítems del feed.
/// La unidad es ÍTEM, no fila de grid: la cantidad de columnas se decide en
/// tiempo de layout (2 en teléfono, 3 en ≥720px — ver `_buildFeedSlivers`),
/// así que una función pura no puede razonar en filas. En el grid de 2
/// columnas del teléfono, 8 ítems ≈ las primeras 4 filas.
const int kFeedTopItemsNoBusiness = 8;

/// Mínimo de publicaciones normales (producto o "se busca") que deben
/// separar dos negocios. 2 ítems ≈ 1 fila del grid de 2 columnas.
const int kMinGapEntreNegocios = 2;

/// Aplica las reglas de presentación sobre la lista YA mezclada por
/// [FeedMixer]:
///
/// 1. Ningún negocio dentro de los primeros [topItemsNoBusiness] ítems.
/// 2. Al menos [minGapEntreNegocios] publicaciones normales entre dos
///    negocios.
///
/// Un negocio en posición prohibida **no se elimina**: se difiere hasta la
/// primera posición legal a partir de la suya, y el resto de los ítems sube
/// una posición. Nada más se reordena.
///
/// Propiedades garantizadas (y cubiertas por
/// `test/feed_layout_rules_test.dart`):
///
/// - **Es identidad sobre feeds que ya cumplen.** Un negocio que ya estaba
///   en posición legal se recoloca en su índice exacto, así que la salida es
///   idéntica a la entrada — el orden de personalización se preserva entero.
/// - **Cada negocio cae en la primera posición legal ≥ su posición
///   original.** Nunca se adelanta ni se manda al final del feed.
/// - **El orden relativo de los no-negocios nunca cambia**, por
///   construcción: solo se les agrega a `result` en el orden del bucle.
///
/// `wanted` cuenta como publicación normal para ambas reglas: llena la zona
/// de exclusión y satisface el espaciado. Solo `business` es especial.
///
/// **Cola best-effort:** si al agotarse la lista quedan negocios pendientes,
/// ya no hay publicaciones normales con las cuales separarlos. Se anexan al
/// final en su orden relativo original — no se descarta contenido — por lo
/// que la regla 2 puede no cumplirse entre los negocios de esa cola. La
/// invariante estricta rige hasta el último ítem normal.
///
/// **Pendiente para scroll infinito:** aplicar esta función por batch
/// reiniciaría el estado de espaciado en cada página, y un negocio al final
/// de la página 1 podría quedar pegado a otro al inicio de la página 2. La
/// corrección sería que la función acepte y devuelva ese estado de arrastre
/// (última posición de negocio + negocios pendientes). Hoy no hace falta:
/// el home consume todo de un tirón con `getAll()` — ver el doc de
/// [FeedMixer] sobre paginación.
List<FeedItem> applyFeedLayoutRules(
  List<FeedItem> items, {
  int topItemsNoBusiness = kFeedTopItemsNoBusiness,
  int minGapEntreNegocios = kMinGapEntreNegocios,
}) {
  final result = <FeedItem>[];
  // Negocios diferidos esperando posición legal, en su orden relativo
  // original (FIFO): el que venía antes en el ranking se coloca antes.
  final pending = <FeedItem>[];
  // Índice EN result del último negocio ya emitido (-1 si ninguno).
  var lastBusinessPos = -1;

  bool canPlaceBusinessNow() {
    if (result.length < topItemsNoBusiness) return false;
    if (lastBusinessPos < 0) return true;
    return result.length - lastBusinessPos - 1 >= minGapEntreNegocios;
  }

  for (final item in items) {
    if (item.type == FeedItemType.business) {
      pending.add(item);
      continue;
    }
    // Antes de cada publicación normal se intenta colocar UN negocio
    // pendiente. Uno solo: colocar dos seguidos violaría el espaciado.
    if (pending.isNotEmpty && canPlaceBusinessNow()) {
      lastBusinessPos = result.length;
      result.add(pending.removeAt(0));
    }
    result.add(item);
  }

  result.addAll(pending);
  return result;
}

/// Controlador con estado que decide, de una sola vez y con una sola
/// semilla, la secuencia COMPLETA de mezcla (orden e intercalado de
/// bloques) de productos, búsquedas ("se busca") y negocios para una
/// sesión del home — y la entrega en tandas mediante [getNextBatch] a
/// medida que se van necesitando.
///
/// [products], [wantedPosts] y [businesses] deben venir YA ordenados por su
/// score/ranking respectivo (recencia, popularidad, afinidad, etc.) — esta
/// clase nunca reordena los ítems dentro de un mismo tipo, solo decide en
/// qué orden y en bloques de qué tamaño se van intercalando los tipos entre
/// sí, tratando cada lista como una cola FIFO de la que se va sacando.
///
/// ## Por qué la semilla se fija una sola vez al construir, y NO por página
///
/// Hoy el home consume todo de un tirón (`getAll()`), pero esta clase está
/// pensada desde ya para scroll infinito, y ese es precisamente el motivo
/// de que el estado (semilla, `Random`, colas, bloque en curso) viva en la
/// instancia y no se recalcule en cada llamada:
///
/// - Cada [FeedMixer] representa UNA sesión de mezcla — una apertura del
///   home o un pull-to-refresh — no una página. La secuencia completa de
///   bloques queda decidida (aunque no toda "materializada" de una vez)
///   desde el momento en que se crea la instancia con su semilla.
/// - Página 2, 3, etc. del scroll infinito deben llamar [getNextBatch] otra
///   vez SOBRE LA MISMA instancia, nunca crear un [FeedMixer] nuevo. Si se
///   creara uno nuevo por página (con una semilla nueva o incluso la misma
///   pero reiniciando las colas desde cero), el usuario vería, por ejemplo,
///   2 búsquedas al final de la página 1 y luego, al cargar la página 2, un
///   bloque de negocios "decidido de nuevo" ahí mismo — un salto de
///   contenido a mitad de bloque que se siente como un glitch.
/// - Por eso [_activeType]/[_activeRemaining] (el bloque que está a medio
///   consumir) también son estado de instancia, no variables locales de
///   [getNextBatch]: un batch puede cortar un bloque a la mitad (p. ej. un
///   bloque de 4 productos que arranca en el ítem 8 de la página 1 pero la
///   página termina en el ítem 10) y el siguiente [getNextBatch] debe
///   retomar esos 2 productos restantes del MISMO bloque en vez de volver
///   a tirar el dado en ese punto.
/// - Solo se debe crear un [FeedMixer] nuevo (con una semilla nueva, p. ej.
///   `DateTime.now().millisecondsSinceEpoch`) cuando el usuario pide
///   explícitamente una mezcla distinta: abrir el home desde cero o hacer
///   pull-to-refresh. Ver `HomeScreen._loadData`.
///
/// Si en el futuro algo "se ve raro" con la mezcla durante el scroll, casi
/// seguro la causa es que se creó un [FeedMixer] nuevo por página en vez de
/// reutilizar la instancia — no que la lógica de mezcla esté rota.
class FeedMixer {
  FeedMixer({
    required List<dynamic> products,
    required List<dynamic> wantedPosts,
    required List<dynamic> businesses,
    required this.seed,
  }) : _random = Random(seed),
       _queues = {
         FeedItemType.product: List<dynamic>.from(products),
         FeedItemType.wanted: List<dynamic>.from(wantedPosts),
         FeedItemType.business: List<dynamic>.from(businesses),
       };

  /// Semilla usada para esta sesión de mezcla. Se expone solo para
  /// depuración/logging — no hace falta leerla para consumir la clase.
  final int seed;

  final Random _random;
  final Map<FeedItemType, List<dynamic>> _queues;

  // Bloque en curso: tipo activo y cuántos ítems de ese tipo faltan por
  // emitir antes de decidir el siguiente tipo. Es estado de instancia (no
  // local a getNextBatch) para que un batch pueda cortar un bloque a la
  // mitad sin que el siguiente batch "olvide" que venía ese bloque — ver
  // el doc de la clase.
  FeedItemType? _activeType;
  int _activeRemaining = 0;
  FeedItemType? _lastEmittedType;

  /// true si queda algún ítem sin consumir en cualquiera de las 3 colas.
  /// El scroll infinito debe dejar de pedir páginas cuando esto sea false.
  bool get hasMore => _queues.values.any((q) => q.isNotEmpty);

  /// Cuántos ítems quedan sin consumir en total, sumando las 3 colas.
  int get remainingCount => _queues.values.fold(0, (sum, q) => sum + q.length);

  /// Devuelve hasta [count] ítems siguientes de la secuencia de mezcla ya
  /// decidida, avanzando el cursor de las colas internas. Pensado para
  /// llamarse una vez por página de scroll infinito; devuelve menos de
  /// [count] (incluso una lista vacía) si las colas se agotan antes.
  ///
  /// Manejo de agotamiento: si una cola se vacía a mitad de sesión (p. ej.
  /// negocios, normalmente la más corta), simplemente se deja de elegir
  /// ese tipo — la mezcla sigue intercalando solo con las colas que aún
  /// tienen contenido, sin cortar el scroll ni intentar sacar de una cola
  /// vacía.
  List<FeedItem> getNextBatch(int count) {
    final result = <FeedItem>[];
    while (result.length < count && hasMore) {
      final active = _activeType;
      if (active == null || _activeRemaining <= 0 || _queues[active]!.isEmpty) {
        _startNewBlock();
        if (_activeType == null) break;
      }
      final type = _activeType!;
      final queue = _queues[type]!;
      final take = min(
        _activeRemaining,
        min(count - result.length, queue.length),
      );
      for (var i = 0; i < take; i++) {
        result.add(FeedItem(type, queue.removeAt(0)));
      }
      _activeRemaining -= take;
    }
    return result;
  }

  /// Azúcar sobre [getNextBatch] para el modo de consumo de hoy (sin
  /// scroll infinito): trae todo lo que quede de las 3 colas en un solo
  /// tirón. Cuando se agregue paginación real, este método deja de usarse
  /// en el home y se reemplaza por llamadas a [getNextBatch] del tamaño de
  /// una página — la lógica de mezcla en sí no cambia.
  List<FeedItem> getAll() => getNextBatch(remainingCount);

  void _startNewBlock() {
    final available = FeedItemType.values
        .where((t) => _queues[t]!.isNotEmpty)
        .toList(growable: false);
    if (available.isEmpty) {
      _activeType = null;
      return;
    }

    // Regla anti-racha: si hay otro tipo disponible, no repetir el tipo del
    // bloque anterior — evita "3 productos, 3 productos, 3 productos..."
    // por simple mala suerte del RNG. "Bloque anterior" puede haber
    // terminado en una página/batch distinta; por eso _lastEmittedType es
    // estado de instancia y no se resetea entre llamadas a getNextBatch.
    var candidates = available.where((t) => t != _lastEmittedType).toList();
    if (candidates.isEmpty) candidates = available;

    final type = _weightedPick(candidates);
    final range = _blockRanges[type]!;
    final blockSize = range.min + _random.nextInt(range.max - range.min + 1);

    _activeType = type;
    _activeRemaining = min(blockSize, _queues[type]!.length);
    _lastEmittedType = type;
  }

  FeedItemType _weightedPick(List<FeedItemType> candidates) {
    final total = candidates.fold<double>(
      0,
      (sum, t) => sum + _baseWeights[t]!,
    );
    var roll = _random.nextDouble() * total;
    for (final type in candidates) {
      roll -= _baseWeights[type]!;
      if (roll <= 0) return type;
    }
    return candidates.last;
  }
}
