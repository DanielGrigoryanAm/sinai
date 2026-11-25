/// Where the app's own backend lives.
///
/// Set at build time, e.g. for a local server:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080
abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://5-222-26-206.sslip.io',
  );

  /// Turns the move from Firebase to the backend on, screen by screen as
  /// they are switched over:
  ///   flutter run --dart-define=USE_BACKEND=true
  static const useBackend = bool.fromEnvironment('USE_BACKEND');

  static Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse(baseUrl).replace(path: path, queryParameters: query);

  /// The live socket: same host, ws(s) scheme.
  static Uri socketUri(String token) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/ws',
      queryParameters: {'token': token},
    );
  }
}
