/**
 * Preguntas dinámicas por categoría — fuente de verdad del servidor.
 *
 * Cada publicación puede responder un set de preguntas que depende de su
 * categoría. La forma de una pregunta es:
 *
 *   key         identificador estable; es la llave dentro del JSON que se
 *               guarda en products.atributos_categoria. NUNCA renombrar una
 *               key ya publicada: los productos viejos quedarían con un
 *               atributo huérfano que nadie sabe pintar.
 *   label       texto que ve el usuario, tanto al publicar como en el detalle.
 *   type        'boolean' | 'select' | 'multiselect' | 'text' | 'number'
 *   options     valores permitidos (solo select/multiselect). La validación
 *               rechaza cualquier valor fuera de esta lista.
 *   required    si el cliente debe exigirlo antes de publicar. Hoy TODAS
 *               están en false: la fricción de publicar es más cara que un
 *               atributo vacío, y la sección del detalle ya oculta lo que no
 *               se respondió. La maquinaria (validación en servidor y
 *               cliente) está completa para poder activarlas por pregunta
 *               sin tocar código.
 *   placeholder pista para los campos de texto/número.
 *   badgeLabel  texto corto para el badge de la tarjeta del listado. Solo lo
 *               necesitan los booleanos destacados: su `label` es una
 *               pregunta ("¿Aceptas mascotas?") y como badge tiene que ser
 *               una afirmación ("Acepta mascotas").
 *   showIf      { key, equals } — la pregunta solo aplica si otra respuesta
 *               tiene cierto valor. Se usa para los campos de detalle que
 *               cuelgan de un booleano ("¿tiene garantía?" → "¿cuánto dura?").
 *               La normalización descarta el hijo si el padre no se cumple,
 *               así no queda basura de un switch que el usuario apagó
 *               después de escribir.
 *
 * Este archivo tiene un espejo en Dart (lib/constants/atributos_categoria.dart)
 * porque el formulario se pinta sin depender de la red, igual que el resto de
 * catálogos del proyecto. `atributosCategoria.paridad.test.js` compara ambos
 * y falla si se desincronizan.
 */

/** Preguntas que aplican a TODAS las categorías. */
const ATRIBUTOS_GENERALES = [
  {
    key: 'acepta_devoluciones',
    label: '¿Aceptas devoluciones/reembolsos?',
    type: 'boolean',
    required: false,
  },
  {
    key: 'precio_negociable',
    label: '¿El precio es negociable?',
    type: 'boolean',
    required: false,
  },
  {
    key: 'lugar_entrega',
    label: '¿Entregas en punto de encuentro o solo en campus?',
    type: 'select',
    options: ['Campus', 'Fuera del campus', 'Ambos'],
    required: false,
  },
  {
    key: 'tiene_garantia',
    label: '¿Tiene garantía?',
    type: 'boolean',
    required: false,
  },
  {
    key: 'duracion_garantia',
    label: '¿Cuánto dura la garantía?',
    type: 'text',
    placeholder: 'Ej. 3 meses',
    required: false,
    showIf: { key: 'tiene_garantia', equals: true },
  },
];

/** Preguntas propias de cada categoría, indexadas por category.id. */
const ATRIBUTOS_POR_CATEGORIA = {
  books: [
    {
      key: 'edicion',
      label: '¿Es edición original o copia?',
      type: 'select',
      options: ['Original', 'Copia/Fotocopia'],
      required: false,
    },
    {
      key: 'estado_libro',
      label: 'Estado del libro',
      type: 'select',
      options: ['Nuevo', 'Como nuevo', 'Buen estado', 'Con detalles/subrayado'],
      required: false,
    },
  ],

  clothes: [
    {
      key: 'talla',
      label: 'Talla',
      type: 'text',
      placeholder: 'Ej. M, 28, 7½',
      required: false,
    },
    {
      key: 'marca',
      label: 'Marca',
      type: 'text',
      placeholder: 'Ej. Nike, Zara, sin marca',
      required: false,
    },
    {
      key: 'condicion_etiqueta',
      label: '¿Conserva la etiqueta?',
      type: 'select',
      options: ['Nuevo con etiqueta', 'Usado'],
      required: false,
    },
    {
      key: 'estado_ropa',
      label: 'Estado de la prenda',
      type: 'select',
      options: ['Nueva', 'Poco uso', 'Uso normal', 'Con detalles'],
      required: false,
    },
    {
      key: 'cambio_talla',
      label: '¿Aplica cambio de talla si no queda?',
      type: 'boolean',
      required: false,
    },
  ],

  electronics: [
    {
      key: 'estado_electronico',
      label: 'Estado del equipo',
      type: 'select',
      options: ['Nuevo', 'Seminuevo', 'Usado', 'Para refacciones'],
      required: false,
    },
    {
      key: 'incluye_accesorios',
      label: '¿Incluye caja y accesorios originales?',
      type: 'boolean',
      required: false,
    },
    {
      key: 'garantia_vigente',
      label: '¿Tiene garantía vigente?',
      type: 'boolean',
      required: false,
    },
    {
      key: 'con_quien_garantia',
      label: '¿Con quién es la garantía?',
      type: 'text',
      placeholder: 'Ej. Apple, Best Buy, la tienda donde lo compré',
      required: false,
      showIf: { key: 'garantia_vigente', equals: true },
    },
    {
      key: 'tiene_desperfecto',
      label: '¿Presenta algún desperfecto o detalle?',
      type: 'boolean',
      required: false,
    },
    {
      key: 'descripcion_desperfecto',
      label: '¿Cuál es el desperfecto?',
      type: 'text',
      placeholder: 'Ej. rayón en la esquina, la batería dura poco',
      required: false,
      showIf: { key: 'tiene_desperfecto', equals: true },
    },
    {
      key: 'tiempo_uso',
      label: 'Tiempo de uso aproximado',
      type: 'text',
      placeholder: 'Ej. 8 meses',
      required: false,
    },
  ],

  food: [
    {
      key: 'opciones_veg',
      label: '¿Tienes opciones vegetarianas/veganas?',
      type: 'boolean',
      required: false,
      badgeLabel: 'Opción veggie',
    },
    {
      key: 'tipo_entrega',
      label: '¿Cómo entregas el pedido?',
      type: 'select',
      options: ['Entrega a domicilio', 'Solo pickup', 'Ambos'],
      required: false,
    },
    {
      key: 'personalizable',
      label: '¿Se puede personalizar el pedido?',
      type: 'boolean',
      required: false,
    },
  ],

  housing: [
    {
      key: 'incluye_renta',
      label: '¿Qué incluye la renta?',
      type: 'multiselect',
      options: ['Luz', 'Agua', 'Internet', 'Gas', 'Amueblado'],
      required: false,
    },
    {
      key: 'requisitos',
      label: '¿Qué requisitos pides?',
      type: 'multiselect',
      options: ['Aval', 'Depósito', 'Contrato', 'Identificación'],
      required: false,
    },
    {
      key: 'acepta_mascotas',
      label: '¿Aceptas mascotas?',
      type: 'boolean',
      required: false,
      badgeLabel: 'Acepta mascotas',
    },
    {
      key: 'exclusivo_para',
      label: '¿Hay alguna restricción de inquilino?',
      type: 'select',
      options: [
        'Sin restricción',
        'Solo estudiantes',
        'Solo mujeres',
        'Solo hombres',
      ],
      required: false,
    },
    {
      key: 'duracion_minima',
      label: 'Duración mínima de contrato',
      type: 'text',
      placeholder: 'Ej. 6 meses',
      required: false,
    },
    {
      key: 'monto_deposito',
      label: '¿Cuánto es el depósito?',
      type: 'text',
      placeholder: 'Ej. $3,000 o un mes de renta',
      required: false,
    },
    {
      key: 'distancia_universidad',
      label: 'Distancia a la universidad',
      type: 'text',
      placeholder: 'Ej. 10 min caminando',
      required: false,
    },
  ],

  notes: [
    {
      key: 'materia_profesor',
      label: 'Materia y profesor',
      type: 'text',
      placeholder: 'Ej. Cálculo II — Ing. Ramírez',
      required: false,
    },
    {
      key: 'periodo',
      label: 'Periodo/semestre',
      type: 'text',
      placeholder: 'Ej. Otoño 2025',
      required: false,
    },
    {
      key: 'formato',
      label: 'Formato',
      type: 'select',
      options: ['Digital PDF', 'Físico', 'Ambos'],
      required: false,
    },
    {
      key: 'completos',
      label: '¿Los apuntes están completos?',
      type: 'select',
      options: ['Completos', 'Parciales'],
      required: false,
    },
    {
      key: 'calificacion',
      label: 'Calificación con la que se aprobó',
      type: 'text',
      placeholder: 'Ej. 95',
      required: false,
    },
  ],

  services: [
    {
      key: 'tiempo_entrega',
      label: 'Tiempo estimado de entrega',
      type: 'text',
      placeholder: 'Ej. 3 días hábiles',
      required: false,
    },
    {
      key: 'revisiones_incluidas',
      label: '¿Cuántas revisiones/ajustes incluidos?',
      type: 'text',
      placeholder: 'Ej. 2 revisiones sin costo',
      required: false,
    },
    {
      key: 'modalidad',
      label: 'Modalidad',
      type: 'select',
      options: ['Presencial', 'Remoto', 'Ambos'],
      required: false,
    },
    {
      key: 'requiere_anticipo',
      label: '¿Requieres anticipo?',
      type: 'boolean',
      required: false,
    },
    {
      key: 'porcentaje_anticipo',
      label: '¿De cuánto es el anticipo?',
      type: 'text',
      placeholder: 'Ej. 50%',
      required: false,
      showIf: { key: 'requiere_anticipo', equals: true },
    },
    {
      key: 'tiene_portafolio',
      label: '¿Experiencia/portafolio disponible?',
      type: 'boolean',
      required: false,
    },
  ],

  other: [
    {
      key: 'estado_general',
      label: 'Estado general',
      type: 'text',
      placeholder: 'Ej. Usado, funciona bien',
      required: false,
    },
    {
      key: 'motivo_venta',
      label: 'Motivo de venta',
      type: 'text',
      placeholder: 'Opcional',
      required: false,
    },
    {
      key: 'razon_urgencia',
      label: '¿Por qué lo vendes con urgencia?',
      type: 'text',
      placeholder: 'Opcional',
      required: false,
    },
    {
      key: 'incluye_accesorios_otros',
      label: '¿Incluye accesorios?',
      type: 'boolean',
      required: false,
    },
  ],
};

/**
 * Todas las preguntas que aplican a una categoría: las generales primero,
 * luego las propias. Una categoría desconocida (o nula) recibe solo las
 * generales en vez de reventar — un producto viejo con una categoría que ya
 * no existe en el catálogo debe seguir pudiendo guardarse.
 */
function preguntasDeCategoria(categoryId) {
  return [...ATRIBUTOS_GENERALES, ...(ATRIBUTOS_POR_CATEGORIA[categoryId] || [])];
}

/**
 * Atributos que vale la pena asomar en la tarjeta del listado, en orden de
 * prioridad y con un máximo de 2. Es una lista de keys por categoría, no una
 * heurística: cuál es "el dato que decide" depende del rubro y lo sabe un
 * humano, no una regla genérica.
 *
 * Las generales quedan fuera a propósito: son las mismas en toda la
 * cuadrícula y no ayudan a comparar dos publicaciones entre sí.
 */
const ATRIBUTOS_DESTACADOS = {
  books: ['estado_libro', 'edicion'],
  clothes: ['talla', 'estado_ropa'],
  electronics: ['estado_electronico'],
  food: ['opciones_veg', 'tipo_entrega'],
  housing: ['exclusivo_para', 'acepta_mascotas'],
  notes: ['formato', 'completos'],
  services: ['modalidad'],
  other: [],
};

const MAX_ATRIBUTOS_DESTACADOS = 2;

module.exports = {
  ATRIBUTOS_GENERALES,
  ATRIBUTOS_POR_CATEGORIA,
  ATRIBUTOS_DESTACADOS,
  MAX_ATRIBUTOS_DESTACADOS,
  preguntasDeCategoria,
};
