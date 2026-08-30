import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';

class LanClientService {
  // Singleton Pattern
  static final LanClientService _instance = LanClientService._internal();
  factory LanClientService() => _instance;
  LanClientService._internal();

  IOWebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _discoveryTimer;

  // الخصائص المطلوبة في main.dart
  bool isConnected = false;
  Function(bool)? onAppStatusChanged;
  Function(bool)? onDevModeChanged;

  // دالة البدء الرئيسية التي يستدعيها main.dart
  void start() {
    startDiscoveryAndConnect();
  }

  void startDiscoveryAndConnect() {
    // إرسال طلب استكشاف كل 3 ثوانٍ حتى يجد الحاسوب
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_channel != null) return; // متصل بالفعل

      try {
        RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;

        // إرسال طلب البحث للعنوان العام في الـ LAN
        String requestData = "DISCOVER_CONTROLLER";
        socket.send(
          utf8.encode(requestData),
          InternetAddress("255.255.255.255"),
          8888,
        );

        // الاستماع للرد الآتي من الكمبيوتر
        socket.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            Datagram? dg = socket.receive();
            if (dg != null) {
              String response = utf8.decode(dg.data);
              final json = jsonDecode(response);
              if (json['type'] == 'CONTROLLER_HERE') {
                String controllerIp = dg.address.address;
                int port = json['wsPort'] ?? 8080;

                // إلغاء مؤقت البحث والاتصال بالـ WebSocket
                _discoveryTimer?.cancel();
                socket.close();
                _connectToWebSocket(controllerIp, port);
              }
            }
          }
        });
      } catch (e) {
        print("UDP Discovery error: $e");
      }
    });
  }

  void _connectToWebSocket(String ip, int port) {
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse('ws://$ip:$port'));
      isConnected = true;

      // 1. إرسال تسجيل الجهاز للـ PC
      _sendRegisterMessage();

      // 2. البدء بإرسال Heartbeat كل 5 ثوانٍ
      _startHeartbeat();

      // 3. الاستماع لأوامر الـ PC
      _channel!.stream.listen(
        (message) {
          _handleServerCommand(message);
        },
        onDone: () {
          _channel = null;
          isConnected = false;
          _heartbeatTimer?.cancel();
          startDiscoveryAndConnect(); // إعادة محاولة الاتصال
        },
        onError: (error) {
          _channel = null;
          isConnected = false;
          _heartbeatTimer?.cancel();
          startDiscoveryAndConnect();
        },
      );
    } catch (e) {
      isConnected = false;
      print("WebSocket connect error: $e");
    }
  }

  void _sendRegisterMessage() {
    final msg = jsonEncode({
      'header': {
        'messageId': DateTime.now().millisecondsSinceEpoch.toString(),
        'deviceId': 'android_phone_01',
        'type': 'REGISTER',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      'payload': {
        'userName': 'Fouad Phone',
      }
    });
    _channel?.sink.add(msg);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_channel != null && isConnected) {
        final msg = jsonEncode({
          'header': {
            'messageId': DateTime.now().millisecondsSinceEpoch.toString(),
            'deviceId': 'android_phone_01',
            'type': 'HEARTBEAT',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          'payload': {}
        });
        _channel?.sink.add(msg);
      }
    });
  }

  void _handleServerCommand(dynamic message) {
    try {
      final json = jsonDecode(message.toString());
      final type = json['header']['type'];

      if (type == 'REBOOT_ROUTER') {
        print("تم استقبال أمر إعادة تشغيل الراوتر من الكمبيوتر!");
      } else if (type == 'APP_STATUS') {
        bool isDisabled = json['payload']['isDisabled'] ?? false;
        if (onAppStatusChanged != null) {
          onAppStatusChanged!(isDisabled);
        }
      } else if (type == 'DEV_MODE') {
        bool isDev = json['payload']['isDev'] ?? false;
        if (onDevModeChanged != null) {
          onDevModeChanged!(isDev);
        }
      }
    } catch (e) {
      print("Error parsing server command: $e");
    }
  }
}