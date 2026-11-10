import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Маленький HTTP-сервер на loopback для тестов скачивания.
class LocalHttpServer {
  LocalHttpServer._(this._server);

  final HttpServer _server;
  final requests = <String>[];

  /// Вызывается для каждого запроса вместе с телом (для проверки того, что отправил клиент).
  void Function(HttpRequest request, String body)? onRequest;

  /// Что отдавать по пути; по умолчанию 404.
  final routes = <String, FutureOr<void> Function(HttpResponse)>{};

  int get port => _server.port;

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  static Future<LocalHttpServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final local = LocalHttpServer._(server);
    server.listen((request) async {
      local.requests.add(request.uri.path);
      final body = await utf8.decoder.bind(request).join();
      local.onRequest?.call(request, body);
      final handler = local.routes[request.uri.path];
      if (handler == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } else {
        await handler(request.response);
      }
    });
    return local;
  }

  void serveBytes(String path, List<int> bytes) {
    routes[path] = (response) async {
      response.contentLength = bytes.length;
      response.add(bytes);
      await response.close();
    };
  }

  void redirect(String from, String to) {
    routes[from] = (response) async {
      response.statusCode = HttpStatus.found;
      response.headers.set(HttpHeaders.locationHeader, url(to).toString());
      await response.close();
    };
  }

  Future<void> close() => _server.close(force: true);
}
