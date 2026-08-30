import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../security/device_identity.dart';

class LanClientService {
  static final LanClientService _instance = LanClientService._internal();
  factory LanClientService() => _instance;
  LanClientService._internal();

  WebSocketChannel? _channel;
  RawDatagramSocket? _udpSocket;
  Timer? _heartbeatTimer;
  Timer? _discoveryTimer;

  Function(bool connected)? onConnectionChanged;
  Function(Map<String, dynamic> command)? onCommandReceived;

  String? _currentControllerIp;
  bool _isConnecting = false;

  void start() {
    _startUdpDiscovery();
  }

  // الاستماع للبث المحلي UDP للتعرف على الـ IP الخاص بالسيرفر
  void _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8888);
      _udpSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = _udpSocket?.receive();
          if (dg != null) {
            final message = utf8.decode(dg.data);
            final hostIp = dg.address.address;
            if (message.contains("ROUTER_CONTROLLER_ANNOUNCE")) {
              _connectToWebSocket(hostIp);
            }
          }
        }
      });
    } catch (e) {
      debugPrint("UDP Discovery Error: $e");
    }
  }

  // محاولة الاتصال بـ WebSocket اللوحة مباشرة
  Future<bool> pairWithCode(String code, String name, {String? manualIp}) async {
    final targetIp = manualIp ?? _currentControllerIp ?? "10.42.0.40";
    try {
      final wsUrl = Uri.parse('ws://$targetIp:8080/ws');
      final channel = IOWebSocketChannel.connect(wsUrl);

      final deviceId = await DeviceIdentityService.getDeviceId();

      final pairPayload = {
        "messageId": DateTime.now().millisecondsSinceEpoch.toString(),
        "deviceId": deviceId,
        "type": "PAIR_REQUEST",
        "timestamp": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "payload": {
          "code": code,
          "name": name,
        }
      };

      channel.sink.add(jsonEncode(pairPayload));

      // انتظار الاستجابة من السيرفر
      final Completer<bool> completer = Completer<bool>();

      channel.stream.listen((data) async {
        final map = jsonDecode(data);
        if (map['type'] == 'PAIR_ACCEPTED') {
          final token = map['payload']['deviceToken'];
          await DeviceIdentityService.savePairing(token, name, targetIp);
          _channel = channel;
          _listenToMessages();
          if (!completer.isCompleted) completer.complete(true);
        } else if (map['type'] == 'PAIR_REJECTED') {
          if (!completer.isCompleted) completer.complete(false);
        }
      }, onError: (err) {
        if (!completer.isCompleted) completer.complete(false);
      });

      return await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
    } catch (e) {
      debugPrint("Pairing Exception: $e");
      return false;
    }
  }

  void _connectToWebSocket(String ip) async {
    if (_isConnecting || _channel != null) return;
    _isConnecting = true;
    _currentControllerIp = ip;

    final paired = await DeviceIdentityService.isPaired();
    if (!paired) {
      _isConnecting = false;
      return;
    }

    try {
      final token = await DeviceIdentityService.getDeviceToken();
      final name = await DeviceIdentityService.getUserName();
      final deviceId = await DeviceIdentityService.getDeviceId();

      final wsUrl = Uri.parse('ws://$ip:8080/ws');
      _channel = IOWebSocketChannel.connect(wsUrl);

      final registerPayload = {
        "messageId": DateTime.now().millisecondsSinceEpoch.toString(),
        "deviceId": deviceId,
        "type": "DEVICE_REGISTER",
        "timestamp": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "payload": {
          "deviceToken": token,
          "userName": name,
          "appVersion": "1.0.0"
        }
      };

      _channel?.sink.add(jsonEncode(registerPayload));
      onConnectionChanged?.call(true);
      _listenToMessages();
      _startHeartbeat();
    } catch (e) {
      onConnectionChanged?.call(false);
    } finally {
      _isConnecting = false;
    }
  }

  void _listenToMessages() {
    _channel?.stream.listen((message) {
      final map = jsonDecode(message);
      if (map['type'] == 'COMMAND_REQUEST') {
        onCommandReceived?.call(map['payload']);
      }
    }, onDone: () {
      _disconnect();
    }, onError: (error) {
      _disconnect();
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_channel != null) {
        final deviceId = await DeviceIdentityService.getDeviceId();
        _channel?.sink.add(jsonEncode({
          "messageId": DateTime.now().millisecondsSinceEpoch.toString(),
          "deviceId": deviceId,
          "type": "HEARTBEAT",
          "timestamp": DateTime.now().millisecondsSinceEpoch ~/ 1000,
          "payload": {}
        }));
      }
    });
  }

  void _disconnect() {
    _channel = null;
    _heartbeatTimer?.cancel();
    onConnectionChanged?.call(false);
  }
}