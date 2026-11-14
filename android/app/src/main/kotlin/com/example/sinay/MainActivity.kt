package com.example.sinai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMessagesChannel()
    }

    // Chat pushes are sent to the "messages" channel (see the manifest and
    // functions/index.js). High importance makes them pop up as heads-up
    // notifications; the fallback channel FCM would use otherwise is silent.
    private fun createMessagesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            "messages",
            "Messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New chat messages"
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
