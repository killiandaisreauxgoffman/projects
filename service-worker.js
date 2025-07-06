// service-worker.js
self.addEventListener('push', (event) => {
    const options = {
        body: 'Notification triggered on page load!',
        icon: 'https://via.placeholder.com/64',
        badge: 'https://via.placeholder.com/32',
        vibrate: [200, 100, 200],
        tag: 'welcome-notification',
        renotify: true
    };

    event.waitUntil(
        self.registration.showNotification('Killian Daisreaux Dedaisreaux Goffman | 216-KILLIAN', options)
    );
});

self.addEventListener('notificationclick', (event) => {
    event.notification.close();
    console.log('Notification clicked');
});