import 'package:flutter/material.dart';

/// Medidas de la cuadrícula de tarjetas de producto — fuente única.
///
/// Existe porque estos números tienen que coincidir entre pantallas que no
/// se leen juntas: el grid de home, el del perfil de vendedor, y los dos
/// skeletons que los sustituyen mientras cargan. Un skeleton que mide
/// distinto del grid que reemplaza hace que las tarjetas salten al aparecer,
/// y nada avisa al desarrollar: cada archivo compila igual con su copia
/// desactualizada del número.
///
/// No es hipotético. Antes de centralizarlo, el skeleton del perfil se quedó
/// en 0.66 cuando su grid ya había pasado a 0.62, y el docstring del
/// skeleton de home anunciaba 0.58, un valor que ya no usaba nadie.
class ProductGridMetrics {
  const ProductGridMetrics._();

  /// Separación entre celdas, en los dos ejes.
  static const double spacing = 12;

  /// A partir de este ancho la cuadrícula pasa a tres columnas (tablet).
  static const double threeColumnBreakpoint = 720;

  /// Alto de la tarjeta horizontal de una lista (búsqueda, ofertas).
  ///
  /// 130 y no 122: con un título de dos renglones más la fila de atributos
  /// destacados —más alta que la línea de descripción que sustituyó— 122
  /// dejaba el contenido a ~2 px de desbordar, y cualquier variación en la
  /// métrica de la fuente lo tiraba a barras amarillas.
  static const double horizontalCardHeight = 130;

  /// Columnas que caben en [width].
  static int columnsFor(double width) => width >= threeColumnBreakpoint ? 3 : 2;

  /// Relación ancho/alto de la celda.
  ///
  /// Con tres columnas la celda es más angosta, pero su contenido (foto,
  /// título de dos renglones, descripción, pie) no encoge en la misma
  /// proporción: necesita proporcionalmente menos alto, de ahí el valor más
  /// grande.
  static double aspectRatioFor(int columns) => columns == 3 ? 0.72 : 0.62;

  /// El delegate ya armado, que es lo que consumen grids y skeletons.
  static SliverGridDelegateWithFixedCrossAxisCount delegateFor(int columns) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: aspectRatioFor(columns),
      );
}
