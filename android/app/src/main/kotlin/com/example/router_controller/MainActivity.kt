package com.example.router_controller

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.jcraft.jsch.JSch
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.router/ssh"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "executeScript" -> {
                    val host = call.argument<String>("host") ?: ""
                    val port = call.argument<Int>("port") ?: 22
                    val username = call.argument<String>("username") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    val command = call.argument<String>("command") ?: ""

                    Thread {
                        try {
                            val jsch = JSch()
                            val session = jsch.getSession(username, host, port)
                            session.setPassword(password)
                            session.setConfig("StrictHostKeyChecking", "no")
                            session.connect(5000)

                            val channel = session.openChannel("exec") as com.jcraft.jsch.ChannelExec
                            channel.setCommand(command)

                            val inputStream = channel.inputStream
                            val errorStream = channel.extInputStream

                            channel.connect()

                            val reader = BufferedReader(InputStreamReader(inputStream))
                            val output = StringBuilder()
                            var line: String?
                            while (reader.readLine().also { line = it } != null) {
                                output.append(line).append("\n")
                            }

                            val errReader = BufferedReader(InputStreamReader(errorStream))
                            val errorOutput = StringBuilder()
                            while (errReader.readLine().also { line = it } != null) {
                                errorOutput.append(line).append("\n")
                            }

                            val exitCode = channel.exitStatus
                            channel.disconnect()
                            session.disconnect()

                            runOnUiThread {
                                val response = mapOf(
                                    "success" to true,
                                    "exitCode" to exitCode,
                                    "output" to output.toString(),
                                    "error" to errorOutput.toString()
                                )
                                result.success(response)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                val response = mapOf(
                                    "success" to false,
                                    "exitCode" to -1,
                                    "output" to "",
                                    "error" to (e.message ?: "SSH Execution Error")
                                )
                                result.success(response)
                            }
                        }
                    }.start()
                }

                "checkEndpoint" -> {
                    val ip = call.argument<String>("ip") ?: "10.30.0.1"
                    Thread {
                        val isReachable = try {
                            val process = Runtime.getRuntime().exec("ping -c 1 -w 2 $ip")
                            process.waitFor() == 0
                        } catch (e: Exception) {
                            false
                        }

                        runOnUiThread {
                            result.success(isReachable)
                        }
                    }.start()
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}