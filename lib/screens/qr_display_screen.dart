import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart';

/// Pantalla dedicada para mostrar un QR en grande.
///
/// El QR se pinta siempre en negro sobre blanco — no en el color de acento
/// del usuario ni con inversión en modo oscuro — porque eso es lo que
/// garantiza el mejor contraste para que cualquier lector lo escanee sin
/// fallar. El fondo de la pantalla usa el mismo claro fijo por lo mismo: es
/// una tarjeta pensada para enseñarse o imprimirse, no una superficie de la
/// app que deba mimetizarse con el tema.
class QrDisplayScreen extends StatefulWidget {
  const QrDisplayScreen({super.key, required this.data, this.title});

  /// Datos a codificar en el QR.
  final String data;

  /// Título opcional (ej: nombre del producto).
  final String? title;

  @override
  State<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends State<QrDisplayScreen> {
  final _qrKey = GlobalKey();
  bool _descargando = false;

  Future<void> _descargar() async {
    if (_descargando) return;
    setState(() => _descargando = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      // 3x: el QR se comparte para imprimir o pegar en otra publicación, así
      // que tiene que aguantar zoom sin pixelarse — no solo verse bien en la
      // pantalla que lo generó.
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final nombre = (widget.title == null || widget.title!.trim().isEmpty)
          ? 'qr_mercadito.png'
          : 'qr_${widget.title!.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.png';
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
            mimeType: 'image/png',
          ),
        ],
        // `fileNameOverrides` y no el `name:` del XFile: cross_file ignora ese
        // campo en todo lo que no sea web, así que sin esto el archivo llega
        // al chat con un nombre temporal aleatorio en vez del del producto.
        fileNameOverrides: [nombre],
        text: widget.title,
      );
    } catch (_) {
      // Compartir puede fallar por cosas ajenas a la app (sin app que reciba
      // el archivo, permisos, memoria al rasterizar). Sin este catch la
      // excepción sale de un `onPressed` y muere sin que nadie se entere:
      // el botón vuelve a su estado normal y parece que no pasó nada.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('qr.download_error'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fijo y no `context.colors.*`: esta pantalla no sigue el modo oscuro del
    // usuario a propósito (ver docstring de la clase).
    const fondo = AppColors.background;
    const superficie = AppColors.surface;
    const tinta = AppColors.ink;
    const tenue = AppColors.muted;
    const borde = AppColors.border;

    return Scaffold(
      backgroundColor: fondo,
      appBar: AppBar(
        backgroundColor: fondo,
        foregroundColor: tinta,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: Text(
          widget.title ?? 'qr.title'.tr(),
          style: const TextStyle(color: tinta, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // QR grande, capturable para la descarga.
              RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: superficie,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borde),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: widget.data,
                    version: QrVersions.auto,
                    size: MediaQuery.of(context).size.width * 0.65,
                    backgroundColor: superficie,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              if (widget.title != null)
                Text(
                  widget.title!,
                  style: const TextStyle(
                    color: tinta,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 8),
              Text(
                'qr.show_hint'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: tenue,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _descargando ? null : _descargar,
                  style: FilledButton.styleFrom(
                    backgroundColor: tinta,
                    foregroundColor: superficie,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _descargando
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: superficie,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 20),
                  label: Text(
                    _descargando
                        ? 'qr.downloading'.tr()
                        : 'qr.download'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tinta,
                    side: const BorderSide(color: borde),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  label: Text('common.close'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
