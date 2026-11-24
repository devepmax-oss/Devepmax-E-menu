package com.devepmax.emenu.driver

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    /**
     * Canales de notificación (Android 8+). El servidor envía los pedidos nuevos al canal
     * "pedidos" con el sonido propio res/raw/nuevo_pedido; los avisos van a "avisos".
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return

        val sound = Uri.parse("${ContentResolver.SCHEME_ANDROID_RESOURCE}://$packageName/raw/nuevo_pedido")
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val orders = NotificationChannel("pedidos", "Pedidos nuevos", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Suena cuando te asignan un pedido"
            setSound(sound, attributes)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 300, 120, 300, 120, 300)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        val notices = NotificationChannel("avisos", "Avisos de entregas", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Pedido listo para recoger, pedido cancelado"
        }
        manager.createNotificationChannel(orders)
        manager.createNotificationChannel(notices)
    }
}
