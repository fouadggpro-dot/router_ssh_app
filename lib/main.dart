import 'package:flutter/material.dart';
import 'package:router_controller/core/network/background_service.dart';
import 'package:router_controller/core/security/device_identity.dart';
import 'package:router_controller/ui/screens/pairing_screen.dart';
import 'package:router_controller/ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initBackgroundService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Router Controller Agent',
      theme: ThemeData.dark(),
      home: const RouterControllerApp(),
    );
  }
}

class RouterControllerApp extends StatefulWidget {
  const RouterControllerApp({super.key});

  @override
  State<RouterControllerApp> createState() => _RouterControllerAppState();
}

class _RouterControllerAppState extends State<RouterControllerApp> {
  bool _isPaired = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkPairing();
  }

  Future<void> _checkPairing() async {
    final paired = await DeviceIdentityService.isPaired();
    setState(() {
      _isPaired = paired;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _isPaired
        ? const HomeScreen()
        : PairingScreen(onPaired: () => setState(() => _isPaired = true));
  }
}