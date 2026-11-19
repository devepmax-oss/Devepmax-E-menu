/// Configuración en tiempo de compilación.
///
/// Cambiar el servidor:
///   flutter run --dart-define=API_BASE_URL=https://api.mirestaurante.com/api/v1
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );
}
