package com.example.router_controller

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.jcraft.jsch.JSch
import com.jcraft.jsch.Session
import java.io.ByteArrayOutputStream
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
                    val command = call.argument<String>("command") ?: "/netis/my_script.sh"
                    
                    Thread {
                        try {
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

                            // المهلة 5 ثوانٍ فقط لمنع التعليق
                            session.connect(5000)

                            val channel = session.openChannel("exec")
                            (channel as com.jcraft.jsch.ChannelExec).setCommand(command)

                            val outputStream = ByteArrayOutputStream()
                            channel.outputStream = outputStream
                            channel.connect()

                            var attempts = 0
                            while (!channel.isClosed && attempts < 50) { 
                                Thread.sleep(100)
                                attempts++
                            }

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
                            val process = Runtime.getRuntime().exec("ping -c 1 -w 1 $targetIp")
                            val exitVal = process.waitFor()
                            exitVal == 0
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