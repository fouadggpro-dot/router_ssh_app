import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../security/device_identity.dart';
import 'protocol_models.dart';

class LanClientService {
  static final LanClientService _instance = LanClientService._internal();
  factory LanClientService() => _instance;
  LanClientService._internal();

  static const platform = MethodChannel('com.example.router/ssh');

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _discoveryTimer;
  
  String? _controllerIp;
  int _controllerPort = 8080;
  bool _isConnected = false;

  // callbacks للتفاعل مع واجهة المستخدم
  Function(bool isDisabled)? onAppStatusChanged;
  Function(bool isDev)? onDevModeChanged;
  Function(String notice)? onNoticeUpdated;

  bool get isConnected => _isConnected;

  // بدء تشغيل الخدمة
  void start() {
    _startUdpDiscovery();
  }

  // 1. الاكتشاف التلقائي عبر UDP Broadcast على البورت 8888
  void _startUdpDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_isConnected) return;

      try {
        RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;

        String deviceId = await DeviceIdentityService.getOrCreateDeviceId();
        String userName = await DeviceIdentityService.getUserName();

        String payload = 'DISCOVER_CONTROLLER:$deviceId:$userName';
        socket.send(payload.codeUnits, InternetAddress('255.255.255.255'), 8888);

        socket.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            Datagram? dg = socket.receive();
            if (dg != null) {
              String response = String.fromCharCodes(dg.data);
              // استلام عنوان الـ Controller مثلاً: "CONTROLLER_OFFER:192.168.1.100:8080"
              if (response.startsWith('CONTROLLER_OFFER')) {
                List<String> parts = response.split(':');
                if (parts.length >= 3) {
                  _controllerIp = parts[1];
                  _controllerPort = int.tryParse(parts[2]) ?? 8080;
                  socket.close();
                  _connectWebSocket();
                }
              }
            }
          }
        });
      } catch (_) {}
    });
  }

  // 2. الاتصال بـ WebSocket السيرفر المركزي
  void _connectWebSocket() async {
    if (_controllerIp == null || _isConnected) return;

    final wsUrl = Uri.parse('ws://$_controllerIp:$_controllerPort/ws');
    try {
      _channel = IOWebSocketChannel.connect(wsUrl, connectTimeout: const Duration(seconds: 5));
      _isConnected = true;
      _discoveryTimer?.cancel();

      // إرسال طلب تسجيل الجهاز
      await _sendRegisterRequest();

      // تشغيل الـ Heartbeat كل 5 ثوانٍ
      _startHeartbeat();

      // استماع للرسائل القادمة من السيرفر
      _channel!.stream.listen(
        (data) => _handleIncomingMessage(data),
        onDone: () => _handleDisconnect(),
        onError: (_) => _handleDisconnect(),
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  // 3. إرسال طلب التسجيل DEVICE_REGISTER
  Future<void> _sendRegisterRequest() async {
    final deviceId = await DeviceIdentityService.getOrCreateDeviceId();
    final userName = await DeviceIdentityService.getUserName();
    final isDev = await DeviceIdentityService.isDeveloperMode();
    final isDisabled = await DeviceIdentityService.isAppDisabled();

    final msg = NetworkMessage(
      messageId: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      deviceId: deviceId,
      type: 'DEVICE_REGISTER',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'userName': userName,
        'appVersion': '2.0.0',
        'isDeveloperMode': isDev,
        'isAppDisabled': isDisabled,
      },
    );

    _sendMessage(msg);
  }

  // 4. إرسال Heartbeat دوري
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isConnected) return;

      final deviceId = await DeviceIdentityService.getOrCreateDeviceId();
      final isDisabled = await DeviceIdentityService.isAppDisabled();

      final msg = NetworkMessage(
        messageId: 'hb_${DateTime.now().millisecondsSinceEpoch}',
        deviceId: deviceId,
        type: 'HEARTBEAT',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'appState': isDisabled ? 'APPLICATION_DISABLED' : 'APPLICATION_ENABLED',
        },
      );

      _sendMessage(msg);
    });
  }

  // 5. معالجة الأوامر الواردة من السيرفر المركزي
  void _handleIncomingMessage(dynamic rawData) async {
    try {
      final msg = NetworkMessage.decode(rawData.toString());
      final deviceId = await DeviceIdentityService.getOrCreateDeviceId();

      // إرسال تأكيد استلام الرسالة ACK
      _sendAck(msg.messageId);

      switch (msg.type) {
        case 'COMMAND_DISABLE_APP':
          await DeviceIdentityService.setAppDisabled(true);
          onAppStatusChanged?.call(true);
          break;

        case 'COMMAND_ENABLE_APP':
          await DeviceIdentityService.setAppDisabled(false);
          onAppStatusChanged?.call(false);
          break;

        case 'COMMAND_ENABLE_DEV':
          await DeviceIdentityService.setDeveloperMode(true);
          onDevModeChanged?.call(true);
          break;

        case 'COMMAND_DISABLE_DEV':
          await DeviceIdentityService.setDeveloperMode(false);
          onDevModeChanged?.call(false);
          break;

        case 'COMMAND_UPDATE_NOTICE':
          final newNotice = msg.payload['notice'] ?? '';
          if (newNotice.isNotEmpty) {
            await DeviceIdentityService.saveNotice(newNotice);
            onNoticeUpdated?.call(newNotice);
          }
          break;

        case 'COMMAND_EXECUTE_SSH':
          // تنفيذ أمر SSH مخصص تم طلب تنفيذه عن بُعد
          final cmd = msg.payload['command'] ?? '';
          if (cmd.isNotEmpty) {
            _executeSSHAndReturnResult(msg.messageId, deviceId, cmd);
          }
          break;
      }
    } catch (_) {}
  }

  // تنفيذ وتصادق أمر SSH وإرجاع Result للسيرفر
  Future<void> _executeSSHAndReturnResult(String commandId, String deviceId, String command) async {
    try {
      final dynamic rawResult = await platform.invokeMethod('executeScript', {
        'host': '10.42.0.1',
        'port': 22,
        'username': 'root',
        'password': '10002000',
        'command': command,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () => {'success': false, 'error': 'Timeout Error'},
      );

      final Map<dynamic, dynamic> res = Map<dynamic, dynamic>.from(rawResult);

      final responseMsg = NetworkMessage(
        messageId: 'res_${DateTime.now().millisecondsSinceEpoch}',
        deviceId: deviceId,
        type: 'COMMAND_RESULT',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'commandId': commandId,
          'success': res['success'] ?? false,
          'exitCode': res['exitCode'] ?? -1,
          'output': res['output'] ?? '',
          'error': res['error'] ?? '',
        },
      );

      _sendMessage(responseMsg);
    } catch (e) {
      // إرسال النتيجة في حال حدث خطأ
    }
  }

  void _sendAck(String originalMessageId) async {
    final deviceId = await DeviceIdentityService.getOrCreateDeviceId();
    final ackMsg = NetworkMessage(
      messageId: 'ack_${DateTime.now().millisecondsSinceEpoch}',
      deviceId: deviceId,
      type: 'COMMAND_ACK',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {'ackMessageId': originalMessageId},
    );
    _sendMessage(ackMsg);
  }

  void _sendMessage(NetworkMessage msg) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(msg.encode());
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    // إعادة محاولة الاكتشاف والاتصال تلقائياً
    _startUdpDiscovery();
  }
}


  void _handleIncomingMessage(NetworkMessage msg) {
  switch (msg.type) {
    case 'ENABLE_DEV_MODE':
      // تفعيل وضع المطور
      _enableDevMode(msg.payload['enabled'] ?? false);
      break;

    case 'REBOOT_ROUTER':
      // تنفيذ أمر إعادة تشغيل الراوتر فوراً عبر الـ SSH MethodChannel
      _rebootRouter();
      break;

    default:
      print('Unknown message type: ${msg.type}');
  }
}

Future<void> _rebootRouter() async {
  try {
    const platform = MethodChannel('com.example.router/ssh');
    await platform.invokeMethod('executeScript', {
      'host': '10.30.0.1', // أو IP الراوتر الخاص بك
      'port': 22,
      'username': 'root',
      'password': 'your_password', // كلمة سر الراوتر
      'command': 'reboot',
    });
  } catch (e) {
    print('Error executing reboot: $e');
  }
}