import 'package:flutter/material.dart';
import '../../core/security/device_identity.dart';

class FirstRunScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const FirstRunScreen({super.key, required this.onSetupComplete});

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _noticeText = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotice();
  }

  Future<void> _loadNotice() async {
    final notice = await DeviceIdentityService.getNotice();
    setState(() {
      _noticeText = notice;
      _isLoading = false;
    });
  }

  Future<void> _submitName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسمك للاستمرار')),
      );
      return;
    }

    await DeviceIdentityService.saveUserName(name);
    await DeviceIdentityService.getOrCreateDeviceId(); // ضمان إنشاء Device ID
    widget.onSetupComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.router, size: 70, color: Colors.indigo),
                    const SizedBox(height: 24),
                    const Text(
                      'مرحباً بك في Router Controller',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    
                    // بطاقة الملاحظة
                    Card(
                      color: Colors.amber.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.amber.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.amber),
                                SizedBox(width: 8),
                                Text('ملاحظة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(_noticeText, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // إدخال الاسم
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'أدخل اسمك',
                        hintText: 'مثال: أحمد',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: _submitName,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: Colors.indigo,
                      ),
                      child: const Text('متابعة', style: TextStyle(fontSize: 18, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}