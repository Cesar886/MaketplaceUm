/// Preguntas dinámicas por categoría.
///
/// Espejo de `backend/src/config/atributosCategoria.js`. Está duplicado a
/// propósito y no se descarga: el formulario de publicar tiene que poder
/// pintarse sin esperar a la red, igual que el catálogo de categorías ya
/// tiene su fallback en `mock_data.dart`. Un formulario que aparece medio
/// segundo después de elegir la categoría se siente roto.
///
/// El servidor sigue siendo la autoridad — valida cada respuesta contra SU
/// copia y rechaza lo que no reconoce. Este archivo decide qué se PINTA,
/// no qué se acepta.
///
/// `backend/src/config/atributosCategoria.paridad.test.js` compara ambos
/// archivos y falla si se desincronizan. Si tocas uno, toca el otro.
library;

enum AtributoTipo { booleano, seleccion, seleccionMultiple, texto, numero }

/// Una pregunta del formulario dinámico.
class AtributoPregunta {
  const AtributoPregunta({
    required this.key,
    required this.label,
    required this.tipo,
    this.options = const [],
    this.obligatoria = false,
    this.placeholder,
    this.badgeLabel,
    this.permiteCustom = false,
    this.showIfKey,
    this.showIfEquals,
  });

  /// Identificador estable; es la llave dentro del JSON `atributos` que se
  /// manda al servidor. Nunca renombrar una key ya publicada.
  final String key;

  /// Lo que lee el usuario, tanto al publicar como en el detalle.
  final String label;

  final AtributoTipo tipo;

  /// Valores permitidos (solo selección y selección múltiple).
  final List<String> options;

  /// Si hay que exigirla antes de publicar. Hoy todas están en false; ver la
  /// nota en la config del servidor.
  final bool obligatoria;

  /// Pista para los campos de texto y número.
  final String? placeholder;

  /// Texto corto para el badge de la tarjeta del listado. Solo lo necesitan
  /// los booleanos: su [label] es una pregunta y el badge tiene que ser una
  /// afirmación.
  final String? badgeLabel;

  /// Solo en selección múltiple: el usuario puede agregar valores propios
  /// además de los de [options]. Se guardan en la misma lista, sin marca que
  /// los distinga — para quien lee el detalle son un chip más.
  final bool permiteCustom;

  /// La pregunta solo aplica si la respuesta de [showIfKey] es
  /// [showIfEquals]. Se usa para los campos que cuelgan de un switch
  /// ("¿tiene garantía?" → "¿cuánto dura?").
  final String? showIfKey;
  final Object? showIfEquals;

  /// ¿Esta pregunta debe mostrarse, dado lo respondido hasta ahora?
  bool aplicaCon(Map<String, dynamic> respuestas) =>
      showIfKey == null || respuestas[showIfKey] == showIfEquals;
}

/// Topes de los valores personalizados de una pregunta con [permiteCustom].
/// Seis chips llenan dos renglones en un teléfono angosto y veinte caracteres
/// es lo que cabe en un chip sin truncarse. El servidor aplica los mismos.
const int maxOpcionesCustom = 6;
const int maxLargoOpcionCustom = 20;

/// Preguntas que aplican a TODAS las categorías.
const List<AtributoPregunta> atributosGenerales = [
  AtributoPregunta(
    key: 'acepta_devoluciones',
    label: '¿Aceptas devoluciones/reembolsos?',
    tipo: AtributoTipo.booleano,
  ),
  AtributoPregunta(
    key: 'precio_negociable',
    label: '¿El precio es negociable?',
    tipo: AtributoTipo.booleano,
  ),
  AtributoPregunta(
    key: 'lugar_entrega',
    label: '¿Entregas en punto de encuentro o solo en campus?',
    tipo: AtributoTipo.seleccion,
    options: ['Campus', 'Fuera del campus', 'Ambos'],
  ),
  AtributoPregunta(
    key: 'tiene_garantia',
    label: '¿Tiene garantía?',
    tipo: AtributoTipo.booleano,
  ),
  AtributoPregunta(
    key: 'duracion_garantia',
    label: '¿Cuánto dura la garantía?',
    tipo: AtributoTipo.texto,
    placeholder: 'Ej. 3 meses',
    showIfKey: 'tiene_garantia',
    showIfEquals: true,
  ),
];

/// Preguntas generales que NO aplican a ciertas categorías.
///
/// Las generales son generales porque le sirven a casi todo el catálogo, no
/// porque le sirvan a todo. Preguntarle a quien renta un cuarto si entrega en
/// el campus, o a quien vende tacos si acepta devoluciones, no es una pregunta
/// opcional de más: es una que no tiene respuesta posible, y quien la lee
/// entiende que el formulario no es para él.
///
/// Se excluye por key; los condicionales que cuelgan de una key excluida se
/// caen solos (ver [preguntasDeCategoria]).
const Map<String, List<String>> generalesExcluidas = {
  // La comida no se devuelve ni se garantiza, y su entrega ya la resuelve su
  // propia pregunta (`tipo_entrega`).
  'food': [
    'acepta_devoluciones',
    'precio_negociable',
    'lugar_entrega',
    'tiene_garantia',
  ],
  // Una renta no se entrega en un punto de encuentro: se visita.
  'housing': ['lugar_entrega'],
  // Unos apuntes no traen garantía; lo demás sí aplica.
  'notes': ['tiene_garantia'],
  // Un servicio no se devuelve ni se entrega en un lugar: para dónde se da
  // está `modalidad`.
  'services': ['acepta_devoluciones', 'lugar_entrega'],
};

/// Preguntas propias de cada categoría, indexadas por `MarketplaceCategory.id`.
const Map<String, List<AtributoPregunta>> atributosPorCategoria = {
  'books': [
    AtributoPregunta(
      key: 'edicion',
      label: '¿Es edición original o copia?',
      tipo: AtributoTipo.seleccion,
      options: ['Original', 'Copia/Fotocopia'],
    ),
    AtributoPregunta(
      key: 'estado_libro',
      label: 'Estado del libro',
      tipo: AtributoTipo.seleccion,
      options: ['Nuevo', 'Como nuevo', 'Buen estado', 'Con detalles/subrayado'],
    ),
  ],
  'clothes': [
    AtributoPregunta(
      key: 'talla',
      label: 'Talla',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. M, 28, 7½',
    ),
    AtributoPregunta(
      key: 'marca',
      label: 'Marca',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. Nike, Zara, sin marca',
    ),
    AtributoPregunta(
      key: 'condicion_etiqueta',
      label: '¿Conserva la etiqueta?',
      tipo: AtributoTipo.seleccion,
      options: ['Nuevo con etiqueta', 'Usado'],
    ),
    AtributoPregunta(
      key: 'estado_ropa',
      label: 'Estado de la prenda',
      tipo: AtributoTipo.seleccion,
      options: ['Nueva', 'Poco uso', 'Uso normal', 'Con detalles'],
    ),
    AtributoPregunta(
      key: 'cambio_talla',
      label: '¿Aplica cambio de talla si no queda?',
      tipo: AtributoTipo.booleano,
    ),
  ],
  'electronics': [
    AtributoPregunta(
      key: 'estado_electronico',
      label: 'Estado del equipo',
      tipo: AtributoTipo.seleccion,
      options: ['Nuevo', 'Seminuevo', 'Usado', 'Para refacciones'],
    ),
    AtributoPregunta(
      key: 'incluye_accesorios',
      label: '¿Incluye caja y accesorios originales?',
      tipo: AtributoTipo.booleano,
    ),
    AtributoPregunta(
      key: 'garantia_vigente',
      label: '¿Tiene garantía vigente?',
      tipo: AtributoTipo.booleano,
    ),
    AtributoPregunta(
      key: 'con_quien_garantia',
      label: '¿Con quién es la garantía?',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. Apple, Best Buy, la tienda donde lo compré',
      showIfKey: 'garantia_vigente',
      showIfEquals: true,
    ),
    AtributoPregunta(
      key: 'tiene_desperfecto',
      label: '¿Presenta algún desperfecto o detalle?',
      tipo: AtributoTipo.booleano,
    ),
    AtributoPregunta(
      key: 'descripcion_desperfecto',
      label: '¿Cuál es el desperfecto?',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. rayón en la esquina, la batería dura poco',
      showIfKey: 'tiene_desperfecto',
      showIfEquals: true,
    ),
    AtributoPregunta(
      key: 'tiempo_uso',
      label: 'Tiempo de uso aproximado',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. 8 meses',
    ),
  ],
  'food': [
    AtributoPregunta(
      key: 'opciones_veg',
      label: '¿Tienes opciones vegetarianas/veganas?',
      tipo: AtributoTipo.booleano,
      badgeLabel: 'Opción veggie',
    ),
    AtributoPregunta(
      key: 'tipo_entrega',
      label: '¿Cómo entregas el pedido?',
      tipo: AtributoTipo.seleccion,
      options: ['Entrega a domicilio', 'Solo pickup', 'Ambos'],
    ),
    AtributoPregunta(
      key: 'personalizable',
      label: '¿Se puede personalizar el pedido?',
      tipo: AtributoTipo.booleano,
    ),
  ],
  'housing': [
    AtributoPregunta(
      key: 'incluye_renta',
      label: '¿Qué incluye la renta?',
      tipo: AtributoTipo.seleccionMultiple,
      options: ['Luz', 'Agua', 'Internet', 'Gas', 'Amueblado'],
      // Ningún catálogo cubre lo que incluye un cuarto ("Wifi 300mb",
      // "Limpieza semanal"), y alargar la lista tampoco: se vuelve una reja
      // de chips que nadie lee.
      permiteCustom: true,
    ),
    AtributoPregunta(
      key: 'requisitos',
      label: '¿Qué requisitos pides?',
      tipo: AtributoTipo.seleccionMultiple,
      options: ['Aval', 'Depósito', 'Contrato', 'Identificación'],
      permiteCustom: true,
    ),
    AtributoPregunta(
      key: 'acepta_mascotas',
      label: '¿Aceptas mascotas?',
      tipo: AtributoTipo.booleano,
      badgeLabel: 'Acepta mascotas',
    ),
    AtributoPregunta(
      key: 'exclusivo_para',
      label: '¿Hay alguna restricción de inquilino?',
      tipo: AtributoTipo.seleccion,
      options: [
        'Sin restricción',
        'Solo estudiantes',
        'Solo mujeres',
        'Solo hombres',
      ],
    ),
    AtributoPregunta(
      key: 'duracion_minima',
      label: 'Duración mínima de contrato',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. 6 meses',
    ),
    AtributoPregunta(
      key: 'monto_deposito',
      label: '¿Cuánto es el depósito?',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. \$3,000 o un mes de renta',
    ),
    AtributoPregunta(
      key: 'distancia_universidad',
      label: 'Distancia a la universidad',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. 10 min caminando',
    ),
  ],
  'notes': [
    AtributoPregunta(
      key: 'materia_profesor',
      label: 'Materia y profesor',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. Cálculo II — Ing. Ramírez',
    ),
    AtributoPregunta(
      key: 'periodo',
      label: 'Periodo/semestre',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. Otoño 2025',
    ),
    AtributoPregunta(
      key: 'formato',
      label: 'Formato',
      tipo: AtributoTipo.seleccion,
      options: ['Digital PDF', 'Físico', 'Ambos'],
    ),
    AtributoPregunta(
      key: 'completos',
      label: '¿Los apuntes están completos?',
      tipo: AtributoTipo.seleccion,
      options: ['Completos', 'Parciales'],
    ),
    AtributoPregunta(
      key: 'calificacion',
      label: 'Calificación con la que se aprobó',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. 95',
    ),
  ],
  'services': [
    AtributoPregunta(
      key: 'tiempo_entrega',
      label: 'Tiempo estimado de entrega',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. 3 días hábiles',
    ),
    AtributoPregunta(
      key: 'revisiones_incluidas',
      label: '¿Cuántas revisiones/ajustes incluidos?',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. 2 revisiones sin costo',
    ),
    AtributoPregunta(
      key: 'modalidad',
      label: 'Modalidad',
      tipo: AtributoTipo.seleccion,
      options: ['Presencial', 'Remoto', 'Ambos'],
    ),
    AtributoPregunta(
      key: 'requiere_anticipo',
      label: '¿Requieres anticipo?',
      tipo: AtributoTipo.booleano,
    ),
    AtributoPregunta(
      key: 'porcentaje_anticipo',
      label: '¿De cuánto es el anticipo?',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. 50%',
      showIfKey: 'requiere_anticipo',
      showIfEquals: true,
    ),
    AtributoPregunta(
      key: 'tiene_portafolio',
      label: '¿Experiencia/portafolio disponible?',
      tipo: AtributoTipo.booleano,
    ),
  ],
  'other': [
    AtributoPregunta(
      key: 'estado_general',
      label: 'Estado general',
      tipo: AtributoTipo.texto,
      placeholder: 'Ej. Usado, funciona bien',
    ),
    AtributoPregunta(
      key: 'motivo_venta',
      label: 'Motivo de venta',
      tipo: AtributoTipo.texto,
      placeholder: 'Opcional',
    ),
    AtributoPregunta(
      key: 'razon_urgencia',
      label: '¿Por qué lo vendes con urgencia?',
      tipo: AtributoTipo.texto,
      placeholder: 'Opcional',
    ),
    AtributoPregunta(
      key: 'incluye_accesorios_otros',
      label: '¿Incluye accesorios?',
      tipo: AtributoTipo.booleano,
    ),
  ],
};

/// Todas las preguntas que aplican a una categoría: las generales que no estén
/// excluidas primero, luego las propias. Una categoría desconocida recibe solo
/// las generales en vez de reventar — un producto viejo con una categoría
/// retirada del catálogo debe seguir pudiéndose editar.
List<AtributoPregunta> preguntasDeCategoria(String categoryId) {
  final excluidas = {...?generalesExcluidas[categoryId]};
  final generales = <AtributoPregunta>[];
  for (final pregunta in atributosGenerales) {
    // Un hijo se va con su padre: el showIf de una pregunta que ya no se
    // pinta no se cumpliría nunca, y dejarla suelta la volvería visible.
    if (excluidas.contains(pregunta.key)) continue;
    if (pregunta.showIfKey != null && excluidas.contains(pregunta.showIfKey)) {
      excluidas.add(pregunta.key);
      continue;
    }
    generales.add(pregunta);
  }
  return [...generales, ...?atributosPorCategoria[categoryId]];
}

/// Busca una pregunta por su key dentro de una categoría. Devuelve null si no
/// existe: el detalle de un producto puede traer respuestas de una versión de
/// la app más nueva que esta, y esas simplemente no se pintan.
AtributoPregunta? preguntaPorKey(String categoryId, String key) {
  for (final pregunta in preguntasDeCategoria(categoryId)) {
    if (pregunta.key == key) return pregunta;
  }
  return null;
}

/// Deja solo las respuestas que siguen aplicando: descarta las de otra
/// categoría y los campos condicionales cuyo padre ya no se cumple.
///
/// Se aplica antes de mandar al servidor, para que apagar un switch borre de
/// verdad el texto que colgaba de él en vez de mandarlo y que el servidor lo
/// tenga que tirar. También se usa al cambiar de categoría en el formulario.
Map<String, dynamic> depurarRespuestas(
  Map<String, dynamic> respuestas,
  String categoryId,
) {
  final limpio = <String, dynamic>{};
  for (final pregunta in preguntasDeCategoria(categoryId)) {
    // El padre de un condicional siempre va declarado antes que el hijo, así
    // que `limpio` ya tiene su valor cuando toca evaluar el showIf.
    if (!pregunta.aplicaCon(limpio)) continue;

    final valor = respuestas[pregunta.key];
    if (valor == null) continue;
    if (valor is String && valor.trim().isEmpty) continue;
    if (valor is List && valor.isEmpty) continue;

    limpio[pregunta.key] = valor is String ? valor.trim() : valor;
  }
  return limpio;
}
