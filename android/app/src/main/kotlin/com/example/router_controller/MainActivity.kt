package com.example.router_controller

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.jcraft.jsch.JSch
import com.jcraft.jsch.Session
import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import org.bouncycastle.jce.provider.BouncyCastleProvider
import java.security.Security

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.router/ssh"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (Security.getProvider("BC") == null) {
            Security.addProvider(BouncyCastleProvider())
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "executeScript" -> {
                    val host = call.argument<String>("host") ?: "10.42.0.1"
                    val port = call.argument<Int>("port") ?: 22
                    val user = call.argument<String>("username") ?: "root"
                    val pass = call.argument<String>("password") ?: "10002000"

                    Thread {
                        try {
                            val jsch = JSch()
                            val session: Session = jsch.getSession(user, host, port)
                            session.setPassword(pass)

                            val config = java.util.Properties()
                            config["StrictHostKeyChecking"] = "no"
                            config["kex"] = "diffie-hellman-group1-sha1"
                            config["cipher.s2c"] = "aes128-cbc,aes256-cbc,3des-cbc"
                            config["cipher.c2s"] = "aes128-cbc,aes256-cbc,3des-cbc"
                            config["HostKeyAlgorithms"] = "ssh-rsa"
                            session.setConfig(config)

                            session.connect(10000)
                            Thread.sleep(5000)

                            val channel = session.openChannel("exec")
                            (channel as com.jcraft.jsch.ChannelExec).setCommand("/netis/my_script.sh")

                            val outputStream = ByteArrayOutputStream()
                            channel.outputStream = outputStream
                            channel.connect()

                            while (!channel.isClosed) { Thread.sleep(100) }

                            val exitStatus = channel.exitStatus
                            session.disconnect()

                            runOnUiThread {
                                result.success(mapOf("success" to true, "exitCode" to exitStatus, "output" to outputStream.toString()))
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.success(mapOf("success" to false, "error" to (e.message ?: "Unknown SSH Error")))
                            }
                        }
                    }.start()
                }
                "checkEndpoint" -> {
                    val targetIp = call.argument<String>("ip") ?: "10.30.0.1"
                    Thread {
                        val isReachable = try {
                            val socket = Socket()
                            socket.connect(InetSocketAddress(targetIp, 80), 3000)
                            socket.close()
                            true
                        } catch (e: Exception) {
                            false
                        }
                        runOnUiThread { result.success(isReachable) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
}