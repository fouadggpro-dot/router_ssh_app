import 'package:flutter/material.dart';
import '../../core/network/lan_client_service.dart';
import '../../core/security/device_identity.dart';
import '../../core/protocol/protocol_models.dart';
import 'approval_screen.dart';
import 'settings_screen.dart';

/// Always shows, front and center, which Controller (if any) this
/// device is linked to and offers a one-tap "unlink" — the visibility
/// this design promised in exchange for building it at all.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isConnected = false;
  String _controllerName = '';
  String _userName = '';
  final List<PendingCommand> _pendingList = [];

  @override
  void initState() {
    super.initState();
    _load();
    LanClientService().onConnectionChanged = (c) {
      if (mounted) setState(() => _isConnected = c);
    };
    LanClientService().onCommandPending = (cmd) {
      if (!mounted) return;
      setState(() => _pendingList.add(cmd));
      // Also pop the full-screen approval prompt immediately so the
      // user doesn't have to hunt for it in the list.
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ApprovalScreen(command: cmd),
        fullscreenDialog: true,
      )).then((_) => _refreshPendingList());
    };
    LanClientService().onCommandExpired = (id) {
      if (mounted) _refreshPendingList();
    };
  }

  Future<void> _load() async {
    final name = await DeviceIdentityService.getUserName();
    final ctrl = await DeviceIdentityService.getControllerName();
    setState(() {
      _userName = name ?? '';
      _controllerName = ctrl ?? '';
      _isConnected = LanClientService().isConnected;
    });
  }

  void _refreshPendingList() {
    setState(() {
      _pendingList
        ..clear()
        ..addAll(LanClientService().pendingCommands.values);
    });
  }

  Future<void> _confirmUnlink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قطع الاتصال؟'),
        content: const Text('رح ينفصل الجهاز عن لوحة التحكم ويحتاج كود إقران جديد للاتصال مرة تانية.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('قطع الاتصال')),
        ],
      ),
    );
    if (confirmed == true) {
      LanClientService().disconnectAndForget();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Router Controller'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(_isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _isConnected ? Colors.green : Colors.grey),
              title: Text(_isConnected
                  ? 'متصل بلوحة تحكم: ${_controllerName.isEmpty ? "?" : _controllerName}'
                  : 'غير متصل حاليًا'),
              subtitle: Text('المستخدم: $_userName'),
              trailing: TextButton(onPressed: _confirmUnlink, child: const Text('قطع الاتصال')),
            ),
          ),
          const SizedBox(height: 16),
          const Text('طلبات بانتظار موافقتك', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (_pendingList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('ما في طلبات معلّقة حاليًا', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._pendingList.map((cmd) => Card(
                  child: ListTile(
                    title: Text(cmd.describe()),
                    trailing: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ApprovalScreen(command: cmd),
                          fullscreenDialog: true,
                        )).then((_) => _refreshPendingList());
                      },
                      child: const Text('مراجعة'),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}