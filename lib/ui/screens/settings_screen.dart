import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/security/device_identity.dart';

/// Router credentials are entered here by the user and saved through
/// EncryptedSharedPreferences — nothing is hard-coded in source.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _saved = false;
  bool _batteryExempt = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _checkBatteryExemption();
  }

  Future<void> _loadConfig() async {
    final cfg = await DeviceIdentityService.getRouterConfig();
    setState(() {
      _host.text = cfg['host'] ?? '';
      _port.text = cfg['port'] ?? '22';
      _user.text = cfg['username'] ?? '';
      _pass.text = cfg['password'] ?? '';
    });
  }

  Future<void> _checkBatteryExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    setState(() => _batteryExempt = status.isGranted);
  }

  Future<void> _requestBatteryExemption() async {
    // Explicit, user-initiated request — explained in plain language,
    // never requested silently on first launch.
    await Permission.ignoreBatteryOptimizations.request();
    _checkBatteryExemption();
  }

  Future<void> _save() async {
    await DeviceIdentityService.setRouterConfig(
      host: _host.text.trim(),
      port: _port.text.trim(),
      username: _user.text.trim(),
      password: _pass.text,
    );
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('بيانات الراوتر (SSH)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _host, decoration: const InputDecoration(labelText: 'IP الراوتر', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _port, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _save, child: Text(_saved ? 'تم الحفظ ✓' : 'حفظ')),
          const Divider(height: 40),
          const Text('إشعارات طلبات الموافقة', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'عشان توصلك طلبات الموافقة فورًا حتى لو الشاشة مقفولة، التطبيق بيحتاج استثناء من تحسين البطارية. بدون هيك، ممكن يتأخر وصول الإشعار.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _batteryExempt ? null : _requestBatteryExemption,
            icon: Icon(_batteryExempt ? Icons.check : Icons.battery_alert),
            label: Text(_batteryExempt ? 'مُفعّل' : 'طلب الاستثناء'),
          ),
        ],
      ),
    );
  }
}
