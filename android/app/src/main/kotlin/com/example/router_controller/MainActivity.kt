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
import java.util.Properties

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.router/ssh"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "executeScript" -> {
                    val host = call.argument<String>("host") ?: "10.42.0.1"
                    val port = call.argument<Int>("port") ?: 22
                    val user = call.argument<String>("username") ?: "root"
                    val pass = call.argument<String>("password") ?: "10002000"
                    
                    Thread {
                        try {
                            // تعيين كلاس الـ Random والأمان صراحة لمنع البحث الديناميكي
                            JSch.setConfig("random", "com.jcraft.jsch.jce.Random")
                            
                            val jsch = JSch()
                            val session: Session = jsch.getSession(user, host, port)
                            session.setPassword(pass)

                            val config = Properties()
                            config["StrictHostKeyChecking"] = "no"
                            config["kex"] = "diffie-hellman-group1-sha1,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1"
                            config["cipher.s2c"] = "3des-cbc,aes128-cbc,aes256-cbc,blowfish-cbc"
                            config["cipher.c2s"] = "3des-cbc,aes128-cbc,aes256-cbc,blowfish-cbc"
                            config["HostKeyAlgorithms"] = "ssh-rsa,ssh-dss"
                            config["PubkeyAcceptedAlgorithms"] = "ssh-rsa,ssh-dss"
                            session.setConfig(config)

                            session.connect(10000)
                            Thread.sleep(1000)

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
                        val isReachable = try {
                            val address = InetAddress.getByName(targetIp)
                            if (address.isReachable(2000)) {
                                true
                            } else {
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