import 'package:intl/intl.dart';

final _currency = NumberFormat.simpleCurrency(locale: 'en_US');

String formatMoney(double value) => _currency.format(value);

/// El backend envía montos como texto ("14.50") o número.
double parseMoney(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

/// Las fotos guardadas en el servidor local llegan como http://localhost:3000/…; desde el
/// emulador o una tablet hay que pedirlas al mismo servidor que la API.
String? mediaUrl(String? url, String apiBaseUrl) {
  if (url == null || url.isEmpty) return null;
  final image = Uri.tryParse(url);
  final api = Uri.tryParse(apiBaseUrl);
  if (image == null || api == null) return url;
  if (!image.hasScheme) return api.replace(path: url.startsWith('/') ? url : '/$url', query: null).toString();
  const local = {'localhost', '127.0.0.1'};
  if (local.contains(image.host) && !local.contains(api.host)) {
    return image.replace(scheme: api.scheme, host: api.host, port: api.port).toString();
  }
  return url;
}

/// "Recién", "5 min", "1 h 05".
String elapsedLabel(DateTime since) {
  final minutes = DateTime.now().difference(since).inMinutes;
  if (minutes < 1) return 'Recién';
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}
