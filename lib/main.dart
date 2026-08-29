import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MaterialApp(
    home: RouterControlScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class RouterControlScreen extends StatefulWidget {
  const RouterControlScreen({super.key});

  @override
  State<RouterControlScreen> createState() => _RouterControlScreenState();
}

class _RouterControlScreenState extends State<RouterControlScreen> {
  static const platform = MethodChannel('com.example.router/ssh');
  
  bool _isAutoMode = false;
  bool _isInternetOnline = false;
  bool _isExecuting = false;
  String _statusMessage = 'جاهز';
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // الميزة 1: تشغيل النت يدوياً
  Future<void> _runScript() async {
    if (_isExecuting) return;
    setState(() {
      _isExecuting = true;
      _statusMessage = 'جاري الاتصال بالراوتر وتشغيل السكربت...';
    });

    try {
      final Map res = await platform.invokeMethod('executeScript', {
        'host': '10.42.0.1',
        'port': 22,
        'username': 'root',
        'password': '10002000',
      });

      if (res['success'] == true) {
        setState(() => _statusMessage = 'تم تشغيل السكربت بنجاح!');
        _checkInternetStatus();
      } else {
        setState(() => _statusMessage = 'خطأ: ${res['error']}');
      }
    } catch (e) {
      setState(() => _statusMessage = 'فشل الاتصال: $e');
    } finally {
      setState(() => _isExecuting = false);
    }
  }

  // الميزة 2: فحص 10.30.0.1 والتشغيل التلقائي
  Future<void> _checkInternetStatus() async {
    try {
      final bool isOnline = await platform.invokeMethod('checkEndpoint', {'ip': '10.30.0.1'});
      setState(() {
        _isInternetOnline = isOnline;
      });

      // إذا كانت ميزة التشغيل التلقائي مفعلة والنت مقطوع
      if (_isAutoMode && !isOnline && !_isExecuting) {
        setState(() => _statusMessage = 'انقطع النت! جاري إعادة التشغيل تلقائياً...');
        _runScript();
      }
    } catch (_) {
      setState(() => _isInternetOnline = false);
    }
  }

  void _toggleAutoMode(bool value) {
    setState(() {
      _isAutoMode = value;
    });

    if (_isAutoMode) {
      // فحص كل 10 ثوانٍ
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _checkInternetStatus());
      _checkInternetStatus();
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('متحكم النت والراوتر'),
        centerTitle: true,
        backgroundColor: Colors.indigo,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // بطاقة حالة الإنترنت
            Card(
              color: _isInternetOnline ? Colors.green.shade50 : Colors.red.shade50,
              child: ListTile(
                leading: Icon(
                  _isInternetOnline ? Icons.wifi : Icons.wifi_off,
                  color: _isInternetOnline ? Colors.green : Colors.red,
                  size: 40,
                ),
                title: Text(_isInternetOnline ? 'الإنترنت متصل (10.30.0.1)' : 'الإنترنت مقطوع'),
                subtitle: Text('حالة الخدمة: ${_isInternetOnline ? "شغالة" : "غير متاحة"}'),
              ),
            ),
            const SizedBox(height: 30),

            // الميزة 1: زر تشغيل النت يدوياً
            ElevatedButton.icon(
              onPressed: _isExecuting ? null : _runScript,
              icon: _isExecuting 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Icon(Icons.play_arrow),
              label: Text(_isExecuting ? 'جاري التنفيذ...' : 'تشغيل النت الآن (يدوي)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                minimumSize: const Size.fromHeight(55),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),

            // الميزة 2: مفتاح التشغيل التلقائي
            SwitchListTile(
              title: const Text('التشغيل التلقائي للنت'),
              subtitle: const Text('تفعيل السكربت تلقائياً عند انقطاع 10.30.0.1'),
              value: _isAutoMode,
              onChanged: _toggleAutoMode,
              secondary: const Icon(Icons.autorenew),
            ),
            const SizedBox(height: 30),

            // عرض الرسائل
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}