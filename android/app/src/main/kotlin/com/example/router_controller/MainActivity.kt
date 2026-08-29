package com.example.router_controller

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.jcraft.jsch.JSch
import com.jcraft.jsch.Session
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import org.bouncycastle.jce.provider.BouncyCastleProvider
import java.security.Security

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.router/ssh"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 1. تسجيل BouncyCastle كمزود تشفير أمني لتفادي استثناء ClassNotFoundException
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
                            // إجبار JSch على تعيين BouncyCastle وتفادي أخطاء Random Class
                            JSch.setConfig("no_auth_handler", "true")
                            
                            val jsch = JSch()
                            val session: Session = jsch.getSession(user, host, port)
                            session.setPassword(pass)

                            val config = java.util.Properties()
                            config["StrictHostKeyChecking"] = "no"
                            config["kex"] = "diffie-hellman-group1-sha1"
                            config["cipher.s2c"] = "aes128-cbc,aes256-cbc,3des-cbc"
                            config["cipher.c2s"] = "aes128-cbc,aes256-cbc,3des-cbc"
                            config["HostKeyAlgorithms"] = "ssh-rsa"
                            config["PubkeyAcceptedAlgorithms"] = "ssh-rsa"
                            session.setConfig(config)

                            session.connect(10000)
                            Thread.sleep(3000) // انتظار استقرار الجلسة

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
                                result.success(mapOf("success" to false, "error" to (e.message ?: e.toString())))
                            }
                        }
                    }.start()
                }
                "checkEndpoint" -> {
                    val targetIp = call.argument<String>("ip") ?: "10.30.0.1"
                    Thread {
                        // استخدام Ping / ICMP حقيقي يتوافق مع استجابة (ms)
                        val isReachable = try {
                            val address = InetAddress.getByName(targetIp)
                            val pingSuccess = address.isReachable(2000)
                            if (pingSuccess) {
                                true
                            } else {
                                // محاولة احتياطية بفتح Socket
                                val socket = Socket()
                                socket.connect(InetSocketAddress(targetIp, 80), 1500)
                                socket.close()
                                true
                            }
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