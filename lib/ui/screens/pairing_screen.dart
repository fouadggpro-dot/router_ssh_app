import 'package:flutter/material.dart';
import '../../core/network/lan_client_service.dart';
import '../../core/security/device_identity.dart';

/// Shown until the device has been explicitly paired by entering the
/// code displayed on the Controller's dashboard. No pairing = no
/// registration = Controller cannot send this device any commands.
class PairingScreen extends StatefulWidget {
  final VoidCallback onPaired;
  const PairingScreen({super.key, required this.onPaired});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty || _codeController.text.trim().length < 4) {
      setState(() => _error = 'أدخل اسمك وكود الإقران المعروض على لوحة التحكم');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    await DeviceIdentityService.setUserName(_nameController.text.trim());
    final ok = await LanClientService().submitPairingCode(_codeController.text.trim());

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (ok) {
      widget.onPaired();
    } else {
      setState(() => _error = 'كود الإقران غير صحيح أو الاتصال بلوحة التحكم فشل. تأكد إنك على نفس الشبكة وحاول مجددًا.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.link, size: 64, color: Colors.indigo),
              const SizedBox(height: 16),
              const Text('ربط الجهاز بلوحة التحكم',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'هاد التطبيق رح يتصل فقط بلوحة التحكم يلي عندها نفس كود الإقران. ما رح يتنفذ أي أمر بدون موافقتك.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسمك', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'كود الإقران (من شاشة لوحة التحكم)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ربط'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
