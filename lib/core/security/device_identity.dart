import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentityService {
  static const String _keyIsPaired = 'is_paired';

  static Future<bool> isPaired() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsPaired) ?? false;
  }

  static Future<void> setPaired(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsPaired, value);
  }
}