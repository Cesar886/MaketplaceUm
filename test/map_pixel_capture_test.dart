// Test de diagnóstico temporal: NO forma parte de la suite permanente.
// Captura los píxeles REALES renderizados (no solo el tamaño del RenderBox)
// de la card cuadrada de ubicación (SellerScheduleAndLocationRow), sirviendo
// un tile OSM real (descargado antes de correr el test) a través de un
// HttpOverrides — TestWidgetsFlutterBinding bloquea las peticiones de red
// reales (siempre devuelven 400), así que hay que interceptarlas a mano
// para poder decodificar bytes de imagen reales y ver el resultado final.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/seller_schedule_location_row.dart';

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this._bytes);
  final Uint8List _bytes;

  @override
  int get statusCode => 200;
  @override
  int get contentLength => _bytes.length;
  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._bytes);
  final Uint8List _bytes;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async =>
      _FakeHttpClientResponse(_bytes);

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._bytes);
  final Uint8List _bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(_bytes);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpClientRequest(_bytes);

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakeHttpOverrides extends HttpOverrides {
  _FakeHttpOverrides(this._bytes);
  final Uint8List _bytes;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(_bytes);
}

void main() {
  testWidgets('capture real pixels of the square location card', (
    tester,
  ) async {
    final tileBytes = await File(
      '/tmp/claude-1000/-home-daniel-mercaditoUM/c24cd3ed-855b-41a4-80ad-bb119367c1e3/scratchpad/test_tile.png',
    ).readAsBytes();
    HttpOverrides.global = _FakeHttpOverrides(tileBytes);
    debugNetworkImageHttpClientProvider = () => _FakeHttpClient(tileBytes);

    final seller = Seller(
      name: 'Taco Corner',
      avatarInitials: 'TC',
      major: '',
      isBusiness: true,
      rating: 5,
      reviews: 1,
      verified: true,
      locationLat: -34.9011,
      locationLng: -56.1645,
      businessHours: {
        0: const BusinessHoursRange(open: '09:00', close: '23:59'),
        1: const BusinessHoursRange(open: '09:00', close: '23:59'),
        2: const BusinessHoursRange(open: '09:00', close: '23:59'),
        3: const BusinessHoursRange(open: '09:00', close: '23:59'),
        4: const BusinessHoursRange(open: '09:00', close: '14:00'),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const Key('capture'),
              child: SizedBox(
                width: 400,
                child: SellerScheduleAndLocationRow(seller: seller),
              ),
            ),
          ),
        ),
      ),
    );

    // Deja que el Image decodifique los bytes servidos por el fake client.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    final boundary =
        tester.element(find.byKey(const Key('capture'))).findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('/tmp/map_card_capture.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('CAPTURED to ${file.path}, size=${image.width}x${image.height}');
  });
}
