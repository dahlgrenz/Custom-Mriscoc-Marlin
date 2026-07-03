import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Kör en liten HTTP-server på själva enheten och serverar webbklienten
/// (mappen `web_client/`, buntad som Flutter-assets) över det lokala nätverket.
///
/// Tanken: värdtelefonen delar en URL som `http://192.168.x.y:8080/?code=ABCD`.
/// Andra enheter på samma Wi-Fi (iOS, Android, dator) öppnar den i webbläsaren
/// och ansluter till spelet — ingen app-installation krävs.
///
/// Obs: webbklienten pratar med Firebase direkt (kräver internet); den lokala
/// servern distribuerar bara själva webbsidan. Se web_client/README.
class LanServerService {
  HttpServer? _server;
  String? _baseUrl;

  /// Basadress medan servern körs, t.ex. `http://192.168.1.42:8080` (annars null).
  String? get baseUrl => _baseUrl;
  bool get isRunning => _server != null;

  static const _assetRoot = 'web_client';

  /// Startar servern (om den inte redan kör) och returnerar basadressen.
  /// Kastar om ingen lokal IPv4-adress hittas eller porten är upptagen.
  Future<String> start({int port = 8080}) async {
    if (_server != null && _baseUrl != null) return _baseUrl!;

    final ip = await _localIpv4();
    if (ip == null) {
      throw const SocketException('Hittade ingen Wi-Fi/LAN-adress. Är du ansluten till ett nätverk?');
    }

    final server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server = server;
    _baseUrl = 'http://$ip:$port';

    // Hantera förfrågningar i bakgrunden.
    server.listen(_handle, onError: (e) => debugPrint('LAN-server fel: $e'));
    debugPrint('LAN-server igång på $_baseUrl');
    return _baseUrl!;
  }

  /// Länk som en spelare öppnar för att gå med i ett visst rum.
  String? joinUrl(String code) =>
      _baseUrl == null ? null : '$_baseUrl/?code=$code';

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _baseUrl = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      // Ruttlösa vägar (t.ex. "/" eller "/?code=ABCD") → index.html.
      var path = req.uri.path;
      if (path == '/' || path.isEmpty) path = '/index.html';

      final assetPath = '$_assetRoot$path';
      try {
        final data = await rootBundle.load(assetPath);
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = _contentTypeFor(path)
          // Låt webbläsaren cacha statiska filer kort.
          ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        req.response.add(data.buffer.asUint8List());
      } catch (_) {
        // Okänd fil → fall tillbaka på index.html (SPA-routing).
        final index = await rootBundle.load('$_assetRoot/index.html');
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html;
        req.response.add(index.buffer.asUint8List());
      }
    } catch (e) {
      req.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Serverfel: $e');
    } finally {
      await req.response.close();
    }
  }

  ContentType _contentTypeFor(String path) {
    if (path.endsWith('.html')) return ContentType.html;
    if (path.endsWith('.js')) return ContentType('application', 'javascript', charset: 'utf-8');
    if (path.endsWith('.css')) return ContentType('text', 'css', charset: 'utf-8');
    if (path.endsWith('.json')) return ContentType.json;
    if (path.endsWith('.svg')) return ContentType('image', 'svg+xml');
    if (path.endsWith('.png')) return ContentType('image', 'png');
    if (path.endsWith('.ico')) return ContentType('image', 'x-icon');
    return ContentType.binary;
  }

  /// Letar upp enhetens lokala IPv4-adress (t.ex. 192.168.x.y) utan extra
  /// beroenden eller behörigheter.
  Future<String?> _localIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }
}
