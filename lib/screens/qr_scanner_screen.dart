import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_theme.dart';
import '../services/deep_link_parser.dart';
import '../services/publicacion_lookup.dart';
import 'product_detail_screen.dart';

/// Pantalla que escanea códigos QR de productos de Mercadito UM.
///
/// El formato esperado en el QR es:
///   mercaditoum://product/ID_DEL_PRODUCTO
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _scanning = true;
  bool _processing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_rounded),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (!_scanning || _processing) return;
              _processBarcode(capture);
            },
          ),
          // ─── Overlay guía ─────────────────────────────────────
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 64,
                      color: Colors.white54,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Apunta al código QR\nde un producto',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_processing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Buscando producto...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _processBarcode(BarcodeCapture capture) async {
    setState(() => _processing = true);

    try {
      final barcode = capture.barcodes.firstOrNull;
      if (barcode == null || barcode.rawValue == null) {
        _showError('No se pudo leer el código QR');
        return;
      }

      final raw = barcode.rawValue!;
      final productId = _parseProductId(raw);

      if (productId == null) {
        _showError('QR inválido. Escanea un código de Mercadito UM.');
        return;
      }

      // El QR puede ser de un producto o de una publicación "se busca" (la
      // app genera ambos); buscarPublicacion resuelve cuál es.
      final product = await buscarPublicacion(productId);

      if (!mounted) return;

      if (product == null) {
        _showError('Publicación no encontrada. Verifica que el código sea válido.');
        return;
      }

      // Navegar al detalle del producto (reemplazando esta pantalla)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );
    } catch (e) {
      _showError('Publicación no encontrada. Verifica que el código sea válido.');
    }
  }

  /// Parsea el ID de la publicación desde el contenido del QR.
  ///
  /// Reusa el mismo parser que los deep links (idDePublicacionEnLink) en vez
  /// de tener su propia copia: así un QR con la URL del sitio
  /// (https://mercaditoum.site/producto/ID) funciona igual que uno con el
  /// esquema propio, y las reglas de qué link se acepta viven en un solo
  /// lugar, con sus tests.
  String? _parseProductId(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    return idDePublicacionEnLink(uri);
  }

  void _showError(String message) {
    setState(() => _processing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
        action: SnackBarAction(
          label: 'Reintentar',
          textColor: Colors.white,
          onPressed: () => setState(() => _scanning = true),
        ),
      ),
    );
  }
}
