package com.tgwsproxy.mobile

import android.os.Bundle
import android.widget.TextView
import android.widget.Button
import android.widget.EditText
import android.widget.Switch
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var statusText: TextView
    private lateinit var startButton: Button
    private lateinit var stopButton: Button
    private lateinit var portEdit: EditText
    private lateinit var logText: TextView
    private lateinit var proxyService: ProxyService

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        statusText = findViewById(R.id.statusText)
        startButton = findViewById(R.id.startButton)
        stopButton = findViewById(R.id.stopButton)
        portEdit = findViewById(R.id.portEdit)
        logText = findViewById(R.id.logText)

        proxyService = ProxyService.getInstance()

        startButton.setOnClickListener {
            val port = portEdit.text.toString().toIntOrNull() ?: 1080
            startProxy(port)
        }

        stopButton.setOnClickListener {
            stopProxy()
        }

        updateUI()
    }

    private fun startProxy(port: Int) {
        lifecycleScope.launch {
            try {
                proxyService.start(applicationContext, port) { message ->
                    runOnUiThread {
                        logText.append("\n$message")
                        updateUI()
                    }
                }
                statusText.text = "Работает на порту $port"
                updateUI()
            } catch (e: Exception) {
                statusText.text = "Ошибка: ${e.message}"
                logText.append("\nERROR: ${e.message}")
            }
        }
    }

    private fun stopProxy() {
        proxyService.stop()
        statusText.text = "Остановлен"
        logText.append("\nПрокси остановлен")
        updateUI()
    }

    private fun updateUI() {
        val isRunning = proxyService.isRunning()
        startButton.isEnabled = !isRunning
        stopButton.isEnabled = isRunning
        startButton.alpha = if (isRunning) 0.5f else 1.0f
        stopButton.alpha = if (isRunning) 1.0f else 0.5f
    }
}
