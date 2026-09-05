import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_theme.dart';
import '../services/deep_link_parser.dart';
import '../services/publicacion_lookup.dart';
import '../widgets/app_shimmer.dart';
import 'product_detail_screen.dart';

/// Pantalla que escanea códigos QR de productos de Marketplace UM.
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
        title: Text('nav.scan_qr'.tr()),
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
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 64,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'qr.aim'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
            Center(
              child: Container(
                width: 220,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppShimmer(
                      child: Column(
                        children: [
                          ShimmerBox(width: 52, height: 52, borderRadius: 14),
                          SizedBox(height: 14),
                          ShimmerBox(height: 13, borderRadius: 5),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'qr.searching'.tr(),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
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
        _showError('qr.read_error'.tr());
        return;
      }

      final raw = barcode.rawValue!;
      final productId = _parseProductId(raw);

      if (productId == null) {
        _showError('qr.invalid'.tr());
        return;
      }

      // El QR puede ser de un producto o de una publicación "se busca" (la
      // app genera ambos); buscarPublicacion resuelve cuál es.
      final product = await buscarPublicacion(productId);

      if (!mounted) return;

      if (product == null) {
        _showError('qr.not_found'.tr());
        return;
      }

      // Navegar al detalle del producto (reemplazando esta pantalla)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );
    } catch (e) {
      _showError('qr.not_found'.tr());
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
          label: 'common.retry'.tr(),
          textColor: Colors.white,
          onPressed: () => setState(() => _scanning = true),
        ),
      ),
    );
  }
}
