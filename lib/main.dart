import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // طلب الأذونات المطلوبة
  await Permission.notification.request();
  await Permission.ignoreBatteryOptimizations.request();
  await Permission.requestInstallPackages.request();

  // إعداد الإشعارات المحلية
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // تشغيل خدمة الخلفية
  await initializeBackgroundService();

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MobileHomeScreen(),
  ));
}

// -------------------------------------------------------------
// إعداد خدمة الخلفية المستمرة (Foreground Service)
// -------------------------------------------------------------
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'router_control_channel',
    'خدمة الكنترول',
    description: 'الاتصال المستمر مع برنامج التحكم',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'router_control_channel',
      initialNotificationTitle: 'تطبيق الكنترول نشط',
      initialNotificationContent: 'جاهز لاستقبال الأوامر في الخلفية...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences prefs = await SharedPreferences.getInstance();
  IOWebSocketChannel? channel;
  Timer? heartbeatTimer;
  Timer? discoveryTimer;

  void connect() {
    discoveryTimer?.cancel();
    discoveryTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (channel != null) return;

      try {
        RawDatagramSocket socket =
            await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;

        socket.send(
          utf8.encode("DISCOVER_CONTROLLER"),
          InternetAddress("255.255.255.255"),
          8888,
        );

        socket.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            Datagram? dg = socket.receive();
            if (dg != null) {
              final json = jsonDecode(utf8.decode(dg.data));
              if (json['type'] == 'CONTROLLER_HERE') {
                String controllerIp = dg.address.address;
                int port = json['wsPort'] ?? 8080;

                discoveryTimer?.cancel();
                socket.close();

                // فتح الـ WebSocket
                channel = IOWebSocketChannel.connect(
                    Uri.parse('ws://$controllerIp:$port'));

                String savedName = prefs.getString('userName') ?? 'User';

                // تسجيل الجهاز لدى الكنترول
                channel?.sink.add(jsonEncode({
                  'header': {
                    'messageId':
                        DateTime.now().millisecondsSinceEpoch.toString(),
                    'deviceId': 'android_phone_01',
                    'type': 'REGISTER',
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                  },
                  'payload': {'userName': savedName}
                }));

                // إرسال نبض الحياة (Heartbeat)
                heartbeatTimer?.cancel();
                heartbeatTimer =
                    Timer.periodic(const Duration(seconds: 5), (_) {
                  channel?.sink.add(jsonEncode({
                    'header': {
                      'messageId':
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      'deviceId': 'android_phone_01',
                      'type': 'HEARTBEAT',
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                    },
                    'payload': {}
                  }));
                });

                // الاستماع المباشر للأوامر المبعوثة من الكمبيوتر
                channel?.stream.listen((message) async {
                  final data = jsonDecode(message.toString());
                  final type = data['header']['type'];
                  final payload = data['payload'] ?? {};

                  if (type == 'ENABLE_DEV_MODE') {
                    bool enabled = payload['enabled'] ?? false;
                    await prefs.setBool('isDevMode', enabled);
                    service.invoke('updateUI');
                  } else if (type == 'SET_MAINTENANCE') {
                    bool enabled = payload['enabled'] ?? false;
                    await prefs.setBool('isMaintenance', enabled);
                    service.invoke('updateUI');
                  } else if (type == 'SEND_NOTIFICATION') {
                    String title = payload['title'] ?? 'رسالة من التحكم';
                    String body = payload['message'] ?? '';
                    _showNotification(title, body);
                  } else if (type == 'PREPARE_UPDATE') {
                    String updatePath = payload['filePath'] ?? '';
                    await prefs.setString('updatePath', updatePath);
                    await prefs.setBool('hasUpdate', true);
                    service.invoke('updateUI');
                  }
                }, onDone: () {
                  channel = null;
                  connect();
                }, onError: (_) {
                  channel = null;
                  connect();
                });
              }
            }
          }
        });
      } catch (e) {
        print("UDP Service Error: $e");
      }
    });
  }

  connect();
}

void _showNotification(String title, String body) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails('router_control_channel', 'إشعارات الكنترول',
          importance: Importance.max, priority: Priority.high);
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  await flutterLocalNotificationsPlugin.show(
      0, title, body, platformChannelSpecifics);
}

// -------------------------------------------------------------
// واجهة الجوال الرئيسية (Mobile UI)
// -------------------------------------------------------------
class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool isDevMode = false;
  bool isMaintenance = false;
  bool autoStart = true;
  bool hasUpdate = false;
  String updateFilePath = '';
  bool isRegistered = false;

  @override
  void initState() {
    super.initState();
    _loadSavedData();

    // الاستماع للتحديثات المباشرة القادمة من خدمة الخلفية
    FlutterBackgroundService().on('updateUI').listen((event) {
      _loadSavedData();
    });
  }

  Future<void> _loadSavedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('userName') ?? '';
      isRegistered = prefs.getBool('isRegistered') ?? false;
      isDevMode = prefs.getBool('isDevMode') ?? false;
      isMaintenance = prefs.getBool('isMaintenance') ?? false;
      autoStart = prefs.getBool('autoStart') ?? true;
      hasUpdate = prefs.getBool('hasUpdate') ?? false;
      updateFilePath = prefs.getString('updatePath') ?? '';
    });
  }

  Future<void> _saveUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', _nameController.text.trim());
    await prefs.setBool('isRegistered', true);
    await prefs.setBool('autoStart', autoStart);
    setState(() {
      isRegistered = true;
    });
  }

  void _installUpdate() async {
    if (updateFilePath.isNotEmpty) {
      final file = File(updateFilePath);
      if (await file.exists()) {
        await OpenFile.open(updateFilePath);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ملف التحديث غير موجود على الجهاز!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. شاشة قفل الصيانة عند إرسال أمر SET_MAINTENANCE من الكمبيوتر
    if (isMaintenance) {
      return Scaffold(
        backgroundColor: Colors.red.shade900,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 90, color: Colors.white),
                const SizedBox(height: 20),
                const Text(
                  'التطبيق متوقف بداعي الصيانة',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'تم تعطيل الوصول مؤقتاً من لوحة تحكم الكمبيوتر.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 40),

                // زر تثبيت التحديث المباشر وسط شاشة الصيانة
                Opacity(
                  opacity: hasUpdate ? 1.0 : 0.3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade900,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                    ),
                    icon: const Icon(Icons.system_update),
                    label: const Text('تثبيت التحديث الجديد'),
                    onPressed: hasUpdate ? _installUpdate : null,
                  ),
                )
              ],
            ),
          ),
        ),
      );
    }

    // 2. شاشة التسجيل الأولى (في حال لم يتم حفظ الاسم سابقاً)
    if (!isRegistered) {
      return Scaffold(
        appBar: AppBar(title: const Text('إعداد التطبيق')),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: const Text(
                    "صممت هاد التطبيق خصيصا لتخلص من منية طالب وغبائه,بتسجيل اسمك انت توافق ان تكون عبد وضيع لفؤاد (امزح)",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'ادخل اسمك للتعريف في الشبكة',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('التشغيل التلقائي مع فتح الجهاز'),
                  value: autoStart,
                  onChanged: (val) {
                    setState(() {
                      autoStart = val;
                    });
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () {
                    if (_nameController.text.trim().isNotEmpty) {
                      _saveUserData();
                    }
                  },
                  child: const Text('حفظ والمتابعة'),
                )
              ],
            ),
          ),
        ),
      );
    }

    // 3. الشاشة الرئيسية للتطبيق
    return Scaffold(
      appBar: AppBar(
        title: const Text('Router Client'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              setState(() {
                isRegistered = false;
              });
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.person, color: Colors.indigo),
                title: Text('المستخدم: ${_nameController.text}'),
                subtitle: const Text('الاتصال بالكنترول نشط بالخلفية'),
              ),
            ),
            const SizedBox(height: 20),

            // خيار إعادة تشغيل الراوتر (يظهر فقط عند تفعيل وضع المطور)
            if (isDevMode)
              Card(
                color: Colors.red.shade50,
                child: ListTile(
                  leading:
                      const Icon(Icons.restart_alt, color: Colors.redAccent),
                  title: const Text('وضع المطور مفعّل'),
                  subtitle: const Text('إعادة تشغيل الراوتر عبر SSH'),
                  trailing: ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('جاري تنفيؤ أمر إعادة التشغيل...')),
                      );
                    },
                    child: const Text('Reboot',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),

            const Spacer(),

            // زر تثبيت التحديث المباشر في منتصف الشاشة (يتفعل عند إرسال تحديث من الويندوز)
            Opacity(
              opacity: hasUpdate ? 1.0 : 0.2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.system_update),
                label: const Text('تثبيت التحديث الجديد'),
                onPressed: hasUpdate ? _installUpdate : null,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}