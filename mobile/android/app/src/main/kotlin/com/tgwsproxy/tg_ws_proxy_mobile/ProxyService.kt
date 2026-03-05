package com.tgwsproxy.tg_ws_proxy_mobile

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class ProxyService : Service() {

    companion object {
        const val CHANNEL_ID = "tg_ws_proxy_channel"
        const val NOTIFICATION_ID = 1
        const val ACTION_START = "com.tgwsproxy.START"
        const val ACTION_STOP = "com.tgwsproxy.STOP"
    }

    private var serverSocket: ServerSocket? = null
    private val isRunning = AtomicBoolean(false)
    private var serverThread: Thread? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startProxy()
            ACTION_STOP -> stopProxy()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopProxy()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "TG WS Proxy",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Статус прокси"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startProxy() {
        if (isRunning.getAndSet(true)) return

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("TG WS Proxy")
            .setContentText("Работает на порту 1080")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .addAction(
                android.R.drawable.ic_media_pause,
                "Остановить",
                PendingIntent.getService(
                    this, 0,
                    Intent(this, ProxyService::class.java).setAction(ACTION_STOP),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            .build()

        startForeground(NOTIFICATION_ID, notification)

        serverThread = thread {
            try {
                serverSocket = ServerSocket(1080)
                while (isRunning.get()) {
                    try {
                        val client = serverSocket?.accept()
                        client?.let { handleClient(it) }
                    } catch (e: Exception) {
                        if (isRunning.get()) {
                            // Логирование ошибки
                        }
                    }
                }
            } catch (e: Exception) {
                isRunning.set(false)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun stopProxy() {
        isRunning.set(false)
        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        serverThread?.interrupt()
        serverThread = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun handleClient(client: Socket) {
        thread {
            try {
                // SOCKS5 обработка
                val input = client.getInputStream()
                val output = client.getOutputStream()

                // Приветствие
                val greeting = ByteArray(2)
                input.read(greeting)

                // Ответ: без авторизации
                output.write(byteArrayOf(5, 0))
                output.flush()

                // Запрос
                val request = ByteArray(4)
                input.read(request)

                val atyp = request[3]
                val dst: String
                val port: Int

                when (atyp.toInt()) {
                    1 -> { // IPv4
                        val addr = ByteArray(4)
                        input.read(addr)
                        dst = addr.joinToString(".") { it.toUInt().toString() }
                        val portBytes = ByteArray(2)
                        input.read(portBytes)
                        port = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)
                    }
                    3 -> { // Domain
                        val dlen = input.read().toInt()
                        val domain = ByteArray(dlen)
                        input.read(domain)
                        dst = String(domain)
                        val portBytes = ByteArray(2)
                        input.read(portBytes)
                        port = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)
                    }
                    4 -> { // IPv6
                        val addr = ByteArray(16)
                        input.read(addr)
                        dst = addr.joinToString(":") { it.toString(16) }
                        val portBytes = ByteArray(2)
                        input.read(portBytes)
                        port = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)
                    }
                    else -> {
                        client.close()
                        return@thread
                    }
                }

                // Ответ: успех
                val reply = byteArrayOf(
                    5, 0, 0, 1,
                    0, 0, 0, 0,
                    0, 0
                )
                output.write(reply)
                output.flush()

                // Здесь должна быть логика подключения к целевому серверу
                // Для краткости опущено

            } catch (e: Exception) {
                // Обработка ошибок
            } finally {
                try { client.close() } catch (_: Exception) {}
            }
        }
    }
}
