String proxifyImageUrl(String? url) {
  if (url == null || url.trim().isEmpty) return '';

  final raw = url.trim();

  final normalized = raw.startsWith('//')
      ? 'https:$raw'
      : raw.startsWith('/')
          ? 'https://gopicadera.com$raw'
          : raw;

  final uri = Uri.tryParse(normalized);
  if (uri == null) return normalized;

  final host = uri.host.toLowerCase();

  // ⚠️ Aquí detectamos tu dominio que da 403
  if (host.contains('gopicadera.com')) {
    final encoded = Uri.encodeComponent(
      '${uri.host}${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
    );

    // Proxy CDN (rápido y funciona bien)
    return 'https://images.weserv.nl/?url=$encoded&w=1200&output=jpg';
  }

  return normalized;
}