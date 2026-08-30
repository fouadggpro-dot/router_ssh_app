import 'package:flutter/material.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.build_circle_outlined, size: 90, color: Colors.orange.shade700),
              const SizedBox(height: 24),
              const Text(
                'التطبيق متوقف مؤقتًا',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  'توجد أعمال صيانة أو تحديثات تخص المطور Fouad.\nيرجى المحاولة لاحقًا.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}