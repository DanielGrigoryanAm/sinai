import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/api_config.dart';

/// How to load a photo or voice message.
///
/// Files on the app's backend need the access token, sent as `?token=` so
/// it doesn't follow the redirect to storage. They are cached by their
/// address without the token, so a renewed token doesn't download them
/// again. Anything else (Firebase links, link previews) loads as it is.
({String url, String? cacheKey}) mediaUrl(String url) {
  if (!url.startsWith(ApiConfig.baseUrl)) return (url: url, cacheKey: null);
  final token = ApiClient.instance.currentAccessToken;
  if (token == null) return (url: url, cacheKey: url);
  final uri = Uri.parse(url);
  return (
    url: uri.replace(
      queryParameters: {...uri.queryParameters, 'token': token},
    ).toString(),
    cacheKey: url,
  );
}
