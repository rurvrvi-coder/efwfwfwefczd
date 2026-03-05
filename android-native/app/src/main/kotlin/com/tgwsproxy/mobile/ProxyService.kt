package com.tgwsproxy.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.io.IOException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class ProxyService : Service() {

    companion object {
        private const val CHANNEL_ID = "tg_ws_proxy_channel"
        private const val NOTIFICATION_ID = 1
        private const val DEFAULT_PORT = 1080

        @Volatile
        private var instance: ProxyService? = null

        fun getInstance(): ProxyService {
            return instance ?: synchronized(this) {
                instance ?: ProxyService().also { instance = it }
            }
        }
    }

    private var serverSocket: ServerSocket? = null
    private val isRunning = AtomicBoolean(false)
    private var serviceScope: CoroutineScope? = null
    private var onLogCallback: ((String) -> Unit)? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val port = intent.getIntExtra(EXTRA_PORT, DEFAULT_PORT)
                startForegroundService(port)
            }
            ACTION_STOP -> stopProxy()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopProxy()
        super.onDestroy()
    }

    fun start(context: Context, port: Int, onLog: ((String) -> Unit)? = null) = CoroutineScope(Dispatchers.IO).launch {
        try {
            onLogCallback = onLog
            serverSocket = ServerSocket(port)
            isRunning.set(true)
            log("Прокси запущен на порту $port")

            val intent = Intent(context, ProxyService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_PORT, port)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }

            while (isRunning.get()) {
                try {
                    val client = serverSocket?.accept()
                    client?.let { handleClient(it) }
                } catch (e: IOException) {
                    if (isRunning.get()) {
                        log("Ошибка клиента: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            isRunning.set(false)
            log("Ошибка запуска: ${e.message}")
            throw e
        }
    }

    fun stop() {
        isRunning.set(false)
        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        serverSocket = null
        serviceScope?.cancel()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        log("Прокси остановлен")
    }

    fun isRunning(): Boolean = isRunning.get()

    private fun startForegroundService(port: Int) {
        val notification = createNotification(port)
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createNotification(port: Int): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, ProxyService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("TG WS Proxy")
            .setContentText("Работает на порту $port")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "Остановить", stopPendingIntent)

        return builder.build()
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

    private fun handleClient(client: Socket) {
        thread {
            try {
                val input = client.getInputStream()
                val output = client.getOutputStream()

                // SOCKS5 приветствие
                val greeting = ByteArray(2)
                input.read(greeting)

                if (greeting[0] != 5.toByte()) {
                    log("Не SOCKS5 (ver=${greeting[0]})")
                    client.close()
                    return@thread
                }

                // Читаем методы
                val nMethods = greeting[1].toInt() and 0xFF
                input.skip(nMethods.toLong())

                // Ответ: без авторизации
                output.write(byteArrayOf(5, 0))
                output.flush()

                // Запрос CONNECT
                val request = ByteArray(4)
                input.read(request)

                val cmd = request[1]
                val atyp = request[3]

                if (cmd != 1) { // Только CONNECT
                    output.write(socks5Reply(7))
                    output.flush()
                    client.close()
                    return@thread
                }

                // Читаем адрес
                val (dst, port) = when (atyp.toInt()) {
                    1 -> { // IPv4
                        val addr = ByteArray(4)
                        input.read(addr)
                        val portBytes = ByteArray(2)
                        input.read(portBytes)
                        val portNum = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)
                        addr.joinToString(".") { it.toUInt().toString() } to portNum
                    }
                    3 -> { // Domain
                        val dlen = input.read().toInt() and 0xFF
                        val domain = ByteArray(dlen)
                        input.read(domain)
                        val portBytes = ByteArray(2)
                        input.read(portBytes)
                        val portNum = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)
                        String(domain) to portNum
                    }
                    4 -> { // IPv6
                        val addr = ByteArray(16)
                        input.read(addr)
                        val portBytes = ByteArray(2)
                        input.read(portBytes)
                        val portNum = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)
                        addr.joinToString(":") { it.toString(16).padStart(2, '0') } to portNum
                    }
                    else -> {
                        client.close()
                        return@thread
                    }
                }

                log("Подключение к $dst:$port")

                // Проверяем, Telegram ли это
                if (isTelegramIp(dst)) {
                    // Здесь должна быть логика WebSocket подключения
                    // Для упрощения - прямой TCP fallback
                    handleTelegramClient(client, dst, port)
                } else {
                    // Прямое подключение для не-Telegram
                    handlePassthrough(client, dst, port)
                }

            } catch (e: Exception) {
                log("Ошибка обработки: ${e.message}")
            } finally {
                try { client.close() } catch (_: Exception) {}
            }
        }
    }

    private fun handleTelegramClient(client: Socket, dst: String, port: Int) {
        try {
            val remote = Socket(dst, port)
            output.write(socks5Reply(0))
            output.flush()

            // Мост между сокетами
            val toRemote = thread {
                try {
                    client.getInputStream().copyTo(remote.getOutputStream())
                } catch (_: Exception) {}
            }
            val toClient = thread {
                try {
                    remote.getInputStream().copyTo(client.getOutputStream())
                } catch (_: Exception) {}
            }
            toRemote.join()
            toClient.join()
            remote.close()
        } catch (e: Exception) {
            log("Ошибка подключения к TG: ${e.message}")
            try {
                client.getOutputStream().write(socks5Reply(5))
                client.getOutputStream().flush()
            } catch (_: Exception) {}
        }
    }

    private fun handlePassthrough(client: Socket, dst: String, port: Int) {
        try {
            val remote = Socket(dst, port)
            client.getOutputStream().write(socks5Reply(0))
            client.getOutputStream().flush()

            val toRemote = thread {
                try {
                    client.getInputStream().copyTo(remote.getOutputStream())
                } catch (_: Exception) {}
            }
            val toClient = thread {
                try {
                    remote.getInputStream().copyTo(client.getOutputStream())
                } catch (_: Exception) {}
            }
            toRemote.join()
            toClient.join()
            remote.close()
        } catch (e: Exception) {
            log("Passthrough ошибка: ${e.message}")
        }
    }

    private fun isTelegramIp(ip: String): Boolean {
        return ip.startsWith("149.154.") || 
               ip.startsWith("185.76.") || 
               ip.startsWith("91.108.") || 
               ip.startsWith("91.105.")
    }

    private fun socks5Reply(status: Int): ByteArray {
        return byteArrayOf(
            5, status.toByte(), 0, 1,
            0, 0, 0, 0,
            0, 0
        )
    }

    private fun log(message: String) {
        val timestamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
            .format(java.util.Date())
        val logMsg = "[$timestamp] $message"
        println(logMsg)
        onLogCallback?.invoke(logMsg)
    }

    companion object {
        const val ACTION_START = "com.tgwsproxy.START"
        const val ACTION_STOP = "com.tgwsproxy.STOP"
        const val EXTRA_PORT = "port"
    }
}
