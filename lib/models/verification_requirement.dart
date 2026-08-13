/// Un requisito que la cuenta debe cumplir para quedar verificada.
///
/// Lo calcula el backend (`validation/requisitosVerificacion.js`) y llega
/// tanto en `GET /verificacion/estado` como en la respuesta de confirmar.
/// La app NO reimplementa la regla: si la evaluara por su cuenta, el
/// checklist acabaría diciendo "todo listo" mientras el servidor rechaza,
/// que es la peor versión posible de esta pantalla.
class VerificationRequirement {
  const VerificationRequirement({
    required this.id,
    required this.titulo,
    required this.detalle,
    required this.cumplido,
    required this.accion,
    this.productos = const [],
  });

  factory VerificationRequirement.fromJson(Map<String, dynamic> json) {
    return VerificationRequirement(
      id: json['id'] as String? ?? '',
      titulo: json['titulo'] as String? ?? '',
      detalle: json['detalle'] as String? ?? '',
      cumplido: json['cumplido'] == true,
      accion: json['accion'] as String? ?? '',
      productos: (json['productos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((p) => (p['title'] as String?) ?? '')
          .where((t) => t.isNotEmpty)
          .toList(),
    );
  }

  static List<VerificationRequirement> listaDeJson(dynamic crudo) {
    if (crudo is! List) return const [];
    return crudo
        .whereType<Map<String, dynamic>>()
        .map(VerificationRequirement.fromJson)
        .toList();
  }

  final String id;
  final String titulo;
  final String detalle;
  final bool cumplido;

  /// A dónde llevar a la persona para resolverlo: 'editar_perfil',
  /// 'conectar_mercadopago' o 'revisar_productos'.
  final String accion;

  /// Títulos de los productos concretos que incumplen, cuando aplica.
  /// Decir "algún producto" obliga al vendedor a revisarlos todos a mano.
  final List<String> productos;
}
