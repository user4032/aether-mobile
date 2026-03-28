importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');
importScripts('/firebase-config.js');

var cfg = self.FIREBASE_WEB_CONFIG || {};

if (cfg.apiKey && cfg.appId && cfg.projectId && cfg.messagingSenderId) {
  firebase.initializeApp({
    apiKey: cfg.apiKey,
    authDomain: cfg.authDomain,
    projectId: cfg.projectId,
    storageBucket: cfg.storageBucket,
    messagingSenderId: cfg.messagingSenderId,
    appId: cfg.appId,
  });

  var messaging = firebase.messaging();

  messaging.onBackgroundMessage(function(payload) {
    var notification = payload.notification || {};
    var data = payload.data || {};

    var title = notification.title || data.title || 'LUMYN';
    var body = notification.body || data.body || 'New message';
    var icon = notification.icon || '/icons/logo-192.png';
    var clickAction = data.click_action || '/';

    self.registration.showNotification(title, {
      body: body,
      icon: icon,
      badge: '/icons/logo-192.png',
      data: { click_action: clickAction },
    });
  });

  self.addEventListener('notificationclick', function(event) {
    event.notification.close();
    var target = '/';
    if (event.notification && event.notification.data && event.notification.data.click_action) {
      target = event.notification.data.click_action;
    }

    event.waitUntil(
      clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(windowClients) {
        for (var i = 0; i < windowClients.length; i++) {
          var client = windowClients[i];
          if ('focus' in client) {
            client.navigate(target);
            return client.focus();
          }
        }
        if (clients.openWindow) {
          return clients.openWindow(target);
        }
        return null;
      })
    );
  });
}
