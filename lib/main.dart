import 'package:flutter/material.dart';
import 'core/network/lan_client_service.dart';
import 'core/network/background_service.dart';
import 'core/security/device_identity.dart';
import 'ui/screens/pairing_screen.dart';
import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The isolate running inside the foreground service also runs
  // LanClientService().start() (see background_service.dart) so the
  // connection survives backgrounding; this call covers the
  // foreground/in-app case before the service isolate takes over.
  LanClientService().start();
  await initBackgroundService();
  runApp(const RouterControllerApp());
}

class RouterControllerApp extends StatefulWidget {
  const RouterControllerApp({super.key});

  @override
  State<RouterControllerApp> createState() => _RouterControllerAppState();
}

class _RouterControllerAppState extends State<RouterControllerApp> {
  bool _loading = true;
  bool _paired = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final paired = await DeviceIdentityService.isPaired();
    setState(() {
      _paired = paired;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Router Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo, scaffoldBackgroundColor: const Color(0xFFF8F9FA)),
      locale: const Locale('ar'),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _paired
              ? const HomeScreen()
              : PairingScreen(onPaired: () => setState(() => _paired = true)),
    );
  }
}
