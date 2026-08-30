import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/security/device_identity.dart';
import 'core/network/lan_client_service.dart';
import 'ui/screens/first_run_screen.dart';
import 'ui/screens/maintenance_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تشغيل خدمة الاتصال بالشبكة المحلية LAN في الخلفية
  LanClientService().start();
  
  runApp(const RouterControllerApp());
}

class RouterControllerApp extends StatefulWidget {
  const RouterControllerApp({super.key});

  @override
  State<RouterControllerApp> createState() => _RouterControllerAppState();
}

class _RouterControllerAppState extends State<RouterControllerApp> {
  bool _isFirstRun = true;
  bool _isAppDisabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAppState();

    // الاستماع الفوري لأوامر التعطيل/التفعيل القادمة من Windows Controller
    LanClientService().onAppStatusChanged = (isDisabled) {
      if (mounted) {
        setState(() {
          _isAppDisabled = isDisabled;
        });
      }
    };
  }

  Future<void> _checkAppState() async {
    final userName = await DeviceIdentityService.getUserName();
    final disabled = await DeviceIdentityService.isAppDisabled();

    setState(() {
      _isFirstRun = userName.isEmpty;
      _isAppDisabled = disabled;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    Widget homeScreen;
    if (_isFirstRun) {
      homeScreen = FirstRunScreen(onSetupComplete: () {
        setState(() => _isFirstRun = false);
      });
    } else if (_isAppDisabled) {
      homeScreen = const MaintenanceScreen();
    } else {
      homeScreen = const HomeScreen();
    }

    return MaterialApp(
      title: 'متحكم النت والراوتر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      home: homeScreen,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const platform = MethodChannel('com.example.router/ssh');

  bool _isOnline = false;
  bool _isChecking = false;
  bool _isExecutingScript = false;
  bool _isRebooting = false;
  bool _autoRunEnabled = false;
  bool _isDevMode = false;

  String _userName = '';
  String _deviceId = '';
  String _statusMessage = '';
  Timer? _timer;

  final TextEditingController _customCommandController = TextEditingController();
  String _customCommandOutput = '';

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    _checkStatus();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _checkStatus());

    // تحديث خيارات المطور فور تغيير الصلاحية من Controller
    LanClientService().onDevModeChanged = (isDev) {
      if (mounted) {
        setState(() => _isDevMode = isDev);
      }
    };
  }

  Future<void> _loadIdentity() async {
    final name = await DeviceIdentityService.getUserName();
    final id = await DeviceIdentityService.getOrCreateDeviceId();
    final dev = await DeviceIdentityService.isDeveloperMode();
    setState(() {
      _userName = name;
      _deviceId = id;
      _isDevMode = dev;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _customCommandController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    try {
      final bool isReachable = await platform
          .invokeMethod('checkEndpoint', {'ip': '10.30.0.1'})
          .timeout(const Duration(seconds: 2), onTimeout: () => false);

      if (mounted) {
        setState(() {
          _isOnline = isReachable;
        });
      }

      if (!isReachable && _autoRunEnabled && !_isExecutingScript && !_isRebooting) {
        _runScript();
      }
    } catch (_) {
      if (mounted) setState(() => _isOnline = false);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _runScript() async {
    if (_isExecutingScript) return;

    setState(() {
      _isExecutingScript = true;
      _statusMessage = 'جاري تنفيذ السكربت...';
    });

    try {
      final dynamic rawResult = await platform.invokeMethod('executeScript', {
        'host': '10.42.0.1',
        'port': 22,
        'username': 'root',
        'password': '10002000',
        'command': '/netis/my_script.sh',
      }).timeout(
        const Duration(seconds: 6),
        onTimeout: () => {'success': true, 'output': 'تم الإرسال (انقضى وقت الانتظار)'},
      );

      final Map<dynamic, dynamic> result = Map<dynamic, dynamic>.from(rawResult);

      if (mounted) {
        if (result['success'] == true) {
          setState(() => _statusMessage = 'تم تشغيل السكربت بنجاح!');
        } else {
          setState(() => _statusMessage = 'خطأ: ${result['error']}');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'تم إرسال الأمر للراوتر.');
    } finally {
      if (mounted) {
        setState(() => _isExecutingScript = false);
        _checkStatus();
      }
    }
  }

  Future<void> _executeCustomCommand() async {
    final cmd = _customCommandController.text.trim();
    if (cmd.isEmpty) return;

    setState(() {
      _statusMessage = 'جاري تنفيذ الأمر المخصص...';
      _customCommandOutput = 'انتظار النتيجة...';
    });

    try {
      final dynamic rawResult = await platform.invokeMethod('executeScript', {
        'host': '10.42.0.1',
        'port': 22,
        'username': 'root',
        'password': '10002000',
        'command': cmd,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () => {'success': false, 'error': 'Timeout Error'},
      );

      final Map<dynamic, dynamic> result = Map<dynamic, dynamic>.from(rawResult);

      if (mounted) {
        setState(() {
          _customCommandOutput = "Exit Code: ${result['exitCode']}\nOutput:\n${result['output'] ?? result['error']}";
          _statusMessage = 'اكتمل تنفيذ الأمر.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _customCommandOutput = 'حدث خطأ أثناء التنفيذ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('متحكم النت والراوتر', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // بطاقة بيانات المستخدم والجهاز وحالة اتصال الـ Controller
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.person, color: Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المستخدم: $_userName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Text('ID: $_deviceId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Icon(
                      LanClientService().isConnected ? Icons.cloud_done : Icons.cloud_off,
                      color: LanClientService().isConnected ? Colors.green : Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // بطاقة حالة الإنترنت
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: _isOnline ? Colors.green.shade50 : Colors.red.shade50,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Icon(
                      _isOnline ? Icons.wifi : Icons.wifi_off,
                      size: 40,
                      color: _isOnline ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isOnline ? 'الإنترنت متصل' : 'الإنترنت مقطوع',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _isOnline ? Colors.green.shade900 : Colors.red.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isOnline ? 'حالة الخدمة: تعمل بنجاح' : 'حالة الخدمة: غير متاحة (10.30.0.1)',
                            style: TextStyle(
                              fontSize: 14,
                              color: _isOnline ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isChecking)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // زر تشغيل النت اليدوي
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isExecutingScript ? null : _runScript,
                icon: _isExecutingScript
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Icon(Icons.play_arrow),
                label: Text(
                  _isExecutingScript ? 'جاري التفعيل...' : 'تشغيل النت الآن (يدوي)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // خيار التشغيل التلقائي
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SwitchListTile(
                secondary: const Icon(Icons.autorenew, color: Colors.indigo),
                title: const Text('التشغيل التلقائي للنت', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('تفعيل السكربت تلقائياً عند انقطاع 10.30.0.1'),
                value: _autoRunEnabled,
                onChanged: (val) => setState(() => _autoRunEnabled = val),
              ),
            ),

            // خيارات المطور (تظهر عند الاستجابة لأمر المطور من Controller)
            if (_isDevMode) ...[
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('خيارات المطور (Developer Mode)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _customCommandController,
                        decoration: const InputDecoration(
                          labelText: 'Custom Router Command',
                          hintText: 'e.g. reboot or /netis/my_script.sh',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _executeCustomCommand,
                        icon: const Icon(Icons.code),
                        label: const Text('Execute'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade900),
                      ),
                      if (_customCommandOutput.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          color: Colors.black,
                          child: Text(
                            _customCommandOutput,
                            style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
            ],

            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}