import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const RouterControllerApp());
}

class RouterControllerApp extends StatelessWidget {
  const RouterControllerApp({super.key});

  @override
  Widget build(BuildContext meContext) {
    return MaterialApp(
      title: 'متحكم النت والراوتر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        fontFamily: 'Roboto',
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
    // فحص حالة الاتصال تلقائياً كل 5 ثوانٍ
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
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
      final bool isReachable = await platform.invokeMethod('checkEndpoint', {'ip': '10.30.0.1'});
      setState(() {
        _isOnline = isReachable;
      });

      if (!isReachable && _autoRunEnabled && !_isExecutingScript && !_isRebooting) {
        _runScript();
      }
    } catch (e) {
      setState(() {
        _isOnline = false;
      });
    } finally {
      setState(() => _isChecking = false);
    }
  }

  Future<void> _runScript() async {
    setState(() {
      _isExecutingScript = true;
      _statusMessage = 'جاري تشغيل النت...';
    });

    try {
      final Map<dynamic, dynamic> result = await platform.invokeMethod('executeScript', {
        'host': '10.42.0.1',
        'port': 22,
        'username': 'root',
        'password': '10002000',
        'command': '/netis/my_script.sh',
      });

      if (result['success'] == true) {
        setState(() => _statusMessage = 'تم تشغيل السكربت بنجاح!');
        _checkStatus();
      } else {
        setState(() => _statusMessage = 'خطأ: ${result['error']}');
      }
    } catch (e) {
      setState(() => _statusMessage = 'حدث خطأ غير متوقع: $e');
    } finally {
      setState(() => _isExecutingScript = false);
    }
  }

  Future<void> _rebootRouter() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تشغيل الراوتر'),
        content: const Text('هل أنت أكتيد من رغبتك في إعادة تشغيل الراوتر الآن؟'),
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
      _statusMessage = 'جاري إرسال أمر إعادة التشغيل...';
    });

    try {
      final Map<dynamic, dynamic> result = await platform.invokeMethod('executeScript', {
        'host': '10.42.0.1',
        'port': 22,
        'username': 'root',
        'password': '10002000',
        'command': 'reboot',
      });

      if (result['success'] == true) {
        setState(() => _statusMessage = 'تم إرسال أمر Reboot بنجاح. الراوتر سيعيد التشغيل.');
      } else {
        setState(() => _statusMessage = 'خطأ أثناء إعادة التشغيل: ${result['error']}');
      }
    } catch (e) {
      setState(() => _statusMessage = 'خطأ: $e');
    } finally {
      setState(() => _isRebooting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('متحكم النت والراوتر', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
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
                        width: 20,
                        height: 20,
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
                        width: 24,
                        height: 24,
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
                        width: 24,
                        height: 24,
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