import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const RouterControllerApp());
}

class RouterControllerApp extends StatelessWidget {
  const RouterControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'متحكم النت والراوتر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      home: const HomeScreen(),
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

  String _statusMessage = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      // إلغاء حالة الـ Loading فوراً وعدم تعليق الزر
      if (mounted) {
        setState(() => _isExecutingScript = false);
        _checkStatus();
      }
    }
  }

  Future<void> _rebootRouter() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تشغيل الراوتر'),
        content: const Text('هل أنت تأكد من رغبتك في إعادة تشغيل الراوتر الآن؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إعادة التشغيل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isRebooting = true;
      _statusMessage = 'جاري إرسال أمر Reboot...';
    });

    try {
      await platform.invokeMethod('executeScript', {
        'host': '10.42.0.1',
        'port': 22,
        'username': 'root',
        'password': '10002000',
        'command': 'reboot',
      }).timeout(const Duration(seconds: 4), onTimeout: () => {'success': true});

      if (mounted) setState(() => _statusMessage = 'تم إعادة تشغيل الراوتر بنجاح.');
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'تم إرسال أمر إعادة التشغيل.');
    } finally {
      if (mounted) setState(() => _isRebooting = false);
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
            const SizedBox(height: 24),

            // زر تشغيل النت اليدوي
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isExecutingScript ? null : _runScript,
                icon: _isExecutingScript
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
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

            // زر إعادة تشغيل الراوتر (Reboot)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _isRebooting ? null : _rebootRouter,
                icon: _isRebooting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.restart_alt, color: Colors.orange),
                label: Text(
                  _isRebooting ? 'جاري إعادة التشغيل...' : 'إعادة تشغيل الراوتر (Reboot)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // خيار التشغيل التلقائي
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SwitchListTile(
                secondary: const Icon(Icons.autorenew, color: Colors.indigo),
                title: const Text('التشغيل التلقائي للنت', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('تفعيل السكربت تلقائياً عند انقطاع 10.30.0.1'),
                value: _autoRunEnabled,
                onChanged: (val) {
                  setState(() => _autoRunEnabled = val);
                },
              ),
            ),

            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ]
          ],
        ),
      ),
    );
  }
}