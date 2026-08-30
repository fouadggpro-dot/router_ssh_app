import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  static const _storage = FlutterSecureStorage();
  static const String _keyDeviceId = 'device_id_secure';
  static const String _keyUserName = 'user_name';
  static const String _keyAppNotice = 'app_notice_text';
  static const String _keyAppDisabled = 'is_app_disabled';
  static const String _keyDevMode = 'is_dev_mode_enabled';

  // الحصول على Device ID أو إنشاؤه لأول مرة
  static Future<String> getOrCreateDeviceId() async {
    String? deviceId = await _storage.read(key: _keyDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'dev_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
      await _storage.write(key: _keyDeviceId, value: deviceId);
    }
    return deviceId;
  }

  // حفظ اسم المستخدم
  static Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name);
  }

  // جلب اسم المستخدم
  static Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName) ?? '';
  }

  // حفظ نص الملاحظة المحدثة من السيرفر
  static Future<void> saveNotice(String notice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppNotice, notice);
  }

  // جلب نص الملاحظة
  static Future<String> getNotice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAppNotice) ??
        'هذا التطبيق مخصص للتحكم بالشبكة ومراقبة الاتصال داخل الشبكة المحلية LAN.';
  }

  // حفظ حالة تعطيل التطبيق
  static Future<void> setAppDisabled(bool disabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAppDisabled, disabled);
  }

  static Future<bool> isAppDisabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAppDisabled) ?? false;
  }

  // حفظ حالة Developer Mode
  static Future<void> setDeveloperMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDevMode, enabled);
  }

  static Future<bool> isDeveloperMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDevMode) ?? false;
  }
}