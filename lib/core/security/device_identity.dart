import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  static const String _keyIsPaired = 'is_paired';
  static const String _keyDeviceId = 'device_id';
  static const String _keyUserName = 'user_name';
  static const String _keyControllerName = 'controller_name';
  static const String _keyPairToken = 'pair_token';
  static const String _keyRouterHost = 'router_host';
  static const String _keyRouterUser = 'router_user';
  static const String _keyRouterPass = 'router_pass';

  // --- Functions used across the app ---

  static Future<bool> isPaired() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsPaired) ?? false;
  }

  static Future<void> setPaired(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsPaired, value);
  }

  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_keyDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName);
  }

  static Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name);
  }

  // Alias support for older code versions
  static Future<void> saveUserName(String name) async => setUserName(name);

  static Future<String?> getControllerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyControllerName);
  }

  static Future<void> setControllerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyControllerName, name);
  }

  static Future<String?> getPairToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPairToken);
  }

  static Future<void> setPairToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPairToken, token);
  }

  static Future<Map<String, String>> getRouterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'host': prefs.getString(_keyRouterHost) ?? '',
      'username': prefs.getString(_keyRouterUser) ?? '',
      'password': prefs.getString(_keyRouterPass) ?? '',
    };
  }

  static Future<void> setRouterConfig(String host, String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRouterHost, host);
    await prefs.setString(_keyRouterUser, username);
    await prefs.setString(_keyRouterPass, password);
  }

  static Future<void> clearPairing() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsPaired);
    await prefs.remove(_keyPairToken);
    await prefs.remove(_keyControllerName);
  }
}