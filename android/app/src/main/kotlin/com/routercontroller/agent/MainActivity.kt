package com.routercontroller.agent

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import com.jcraft.jsch.ChannelExec
import com.jcraft.jsch.JSch
import com.jcraft.jsch.Session
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.util.Properties

class MainActivity : FlutterActivity() {

    private val SSH_CHANNEL = "com.routercontroller.agent/ssh"
    private val UPDATE_CHANNEL = "com.routercontroller.agent/update"
    private val NOTIFY_CHANNEL = "com.routercontroller.agent/notify"
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SSH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "executeScript" -> {
                        val host = call.argument<String>("host") ?: ""
                        val port = call.argument<Int>("port") ?: 22
                        val username = call.argument<String>("username") ?: ""
                        val password = call.argument<String>("password") ?: ""
                        val command = call.argument<String>("command") ?: ""

                        scope.launch {
                            val res = withContext(Dispatchers.IO) {
                                runSshCommand(host, port, username, password, command)
                            }
                            result.success(res)
                        }
                    }
                    "checkEndpoint" -> {
                        val ip = call.argument<String>("ip") ?: ""
                        scope.launch {
                            val reachable = withContext(Dispatchers.IO) { pingHost(ip) }
                            result.success(reachable)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val url = call.argument<String>("url") ?: ""
                        val version = call.argument<String>("version") ?: ""
                        scope.launch {
                            val res = withContext(Dispatchers.IO) {
                                ApkUpdateHelper.downloadAndRequestInstall(applicationContext, url, version)
                            }
                            result.success(res)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showApprovalRequest" -> {
                        val commandId = call.argument<String>("commandId") ?: ""
                        val summary = call.argument<String>("summary") ?: ""
                        NotificationHelper.showApprovalRequest(applicationContext, commandId, summary)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    /**
     * Legacy Netis routers only speak old SSH algorithms. JSch is
     * configured to allow them explicitly for this connection only —
     * this does not weaken anything else on the device.
     */
    private fun runSshCommand(
        host: String,
        port: Int,
        username: String,
        password: String,
        command: String
    ): Map<String, Any> {
        var session: Session? = null
        var channel: ChannelExec? = null
        return try {
            val jsch = JSch()
            session = jsch.getSession(username, host, port)
            session.setPassword(password)

            val config = Properties()
            config["StrictHostKeyChecking"] = "no"
            config["kex"] = "diffie-hellman-group1-sha1,diffie-hellman-group14-sha1"
            config["cipher.s2c"] = "aes128-cbc,aes256-cbc,3des-cbc"
            config["cipher.c2s"] = "aes128-cbc,aes256-cbc,3des-cbc"
            config["server_host_key"] = "ssh-rsa"
            config["PubkeyAcceptedAlgorithms"] = "ssh-rsa"
            session.setConfig(config)
            session.timeout = 8000
            session.connect(8000)

            channel = session.openChannel("exec") as ChannelExec
            channel.setCommand(command)
            val outStream = ByteArrayOutputStream()
            val errStream = ByteArrayOutputStream()
            channel.outputStream = null
            channel.setOutputStream(outStream)
            channel.setErrStream(errStream)
            channel.connect(8000)

            while (!channel.isClosed) {
                Thread.sleep(100)
            }

            val exitCode = channel.exitStatus
            mapOf(
                "success" to (exitCode == 0),
                "exitCode" to exitCode,
                "output" to outStream.toString("UTF-8"),
                "error" to errStream.toString("UTF-8")
            )
        } catch (e: Exception) {
            mapOf("success" to false, "exitCode" to -1, "output" to "", "error" to (e.message ?: "unknown error"))
        } finally {
            channel?.disconnect()
            session?.disconnect()
        }
    }

    private fun pingHost(ip: String): Boolean {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("ping", "-c", "1", "-W", "2", ip))
            process.waitFor() == 0
        } catch (e: Exception) {
            false
        }
    }
}