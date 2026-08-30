import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'lan_client_service.dart';
import '../security/device_identity.dart';

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  // إنشاء قناة الإشعارات في أندرويد لتفادي Bad notification exception
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'lan_connection', // ID القناة
    'LAN Connection Service', // اسم القناة الظاهر للمستخدم
    description: 'Keeps the router control background service alive',
    importance: Importance.low, // مستوى الأولوية للإشعار المستمر
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: 'lan_connection',
      initialNotificationTitle: 'Router Controller',
      initialNotificationContent: 'جاري البحث عن لوحة تحكم على الشبكة...',
      foregroundServiceNotificationId: 9001,
    ),
    iosConfiguration: IosConfiguration(),
  );

  await service.startService();
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  LanClientService().start();

  LanClientService().onConnectionChanged = (connected) async {
    if (service is AndroidServiceInstance) {
      if (connected) {
        final name = await DeviceIdentityService.getControllerName();
        final safeName = name ?? '';
        final displayName = safeName.isNotEmpty ? safeName : "?";
        service.setForegroundNotificationInfo(
          title: 'Router Controller',
          content: 'متصل بلوحة تحكم: $displayName — اضغط لفتح التطبيق وقطع الاتصال',
        );
      } else {
        service.setForegroundNotificationInfo(
          title: 'Router Controller',
          content: 'غير متصل — جاري البحث عن لوحة تحكم...',
        );
      }
    }
  };

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}