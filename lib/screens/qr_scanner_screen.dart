import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_theme.dart';
import '../services/api_service.dart';
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

      // Buscar producto en la API
      final product = await ApiService.getProduct(productId);

      if (!mounted) return;

      // Navegar al detalle del producto (reemplazando esta pantalla)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );
    } catch (e) {
      _showError('Producto no encontrado. Verifica que el código sea válido.');
    }
  }

  /// Parsea el ID del producto desde el formato:
  ///   mercaditoum://product/ID_DEL_PRODUCTO
  String? _parseProductId(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    // Formato URL: mercaditoum://product/ID
    if (uri.scheme == 'mercaditoum' &&
        uri.host == 'product' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }

    // Fallback: si el texto empieza con el prefijo
    const prefix = 'mercaditoum://product/';
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length).trim();
    }

    return null;
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
