import 'package:flutter_background_service/flutter_background_service.dart';
import 'lan_client_service.dart';
import '../security/device_identity.dart';

/// Keeps the LAN connection alive while the app is backgrounded, via a
/// persistent, always-visible foreground-service notification. The
/// notification text always states which Controller (if any) this
/// device is linked to — the same visibility promised in the design —
/// and the service does nothing beyond what LanClientService already
/// does (discover, register, relay commands to the approval UI).
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

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