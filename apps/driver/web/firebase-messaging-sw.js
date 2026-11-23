/*
 * Notificaciones push de la app del repartidor en el navegador.
 * Muestra "Nuevo pedido #12" aunque la pestaña esté cerrada o en segundo plano.
 * (Si la app está abierta y visible, no se muestra: la app ya suena y lo enseña.)
 */
self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {};
  }
  const data = payload.data || {};
  const notification = payload.notification || {};
  const title = notification.title || data.title || 'Nuevo aviso';
  const options = {
    body: notification.body || data.body || '',
    icon: 'assets/assets/images/logo.png',
    badge: 'assets/assets/images/logo.png',
    tag: data.tag || undefined,
    renotify: true,
    requireInteraction: data.urgent === '1',
    vibrate: data.urgent === '1' ? [300, 120, 300, 120, 300] : undefined,
    data,
  };
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      if (clients.some((c) => c.visibilityState === 'visible')) return undefined;
      return self.registration.showNotification(title, options);
    }),
  );
});

// Al tocar la notificación: abrir (o enfocar) la app.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      const open = clients.find((c) => 'focus' in c);
      if (open) return open.focus();
      return self.clients.openWindow(self.registration.scope.replace(/firebase-cloud-messaging-push-scope\/?$/, ''));
    }),
  );
});

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
