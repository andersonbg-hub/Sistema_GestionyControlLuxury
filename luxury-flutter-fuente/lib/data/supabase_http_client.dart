import 'dart:async';

import 'package:http/http.dart' as http;

class SupabaseHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final timeout = switch (path) {
      _ when path.startsWith('/auth/v1/') => const Duration(seconds: 12),
      _
          when path.startsWith('/functions/v1/') ||
              path.startsWith('/storage/v1/') =>
        const Duration(seconds: 25),
      _ => null,
    };
    if (timeout == null) return _inner.send(request);

    final deadline = Completer<void>();
    final existing = request is http.Abortable ? request.abortTrigger : null;
    final abort = existing == null
        ? deadline.future
        : Future.any([existing, deadline.future]);
    final timed = switch (request) {
      http.Request() => http.AbortableRequest(
        request.method,
        request.url,
        abortTrigger: abort,
      )..bodyBytes = request.bodyBytes,
      http.MultipartRequest() =>
        http.AbortableMultipartRequest(
            request.method,
            request.url,
            abortTrigger: abort,
          )
          ..fields.addAll(request.fields)
          ..files.addAll(request.files),
      _ => null,
    };
    if (timed == null) return _inner.send(request);
    timed
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;

    final timer = Timer(timeout, deadline.complete);
    try {
      final streamed = await _inner.send(timed);
      final response = await http.Response.fromStream(streamed);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        contentLength: response.contentLength,
        reasonPhrase: response.reasonPhrase,
        request: request,
      );
    } on http.RequestAbortedException {
      if (deadline.isCompleted) {
        throw TimeoutException('Supabase no respondió a tiempo.', timeout);
      }
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  @override
  void close() => _inner.close();
}
