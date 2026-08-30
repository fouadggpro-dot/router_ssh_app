import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/lan_client_service.dart';
import '../../core/protocol/protocol_models.dart';

/// Full-screen approval prompt. This is launched either from within
/// the app or via a full-screen notification intent (see
/// FullScreenApprovalActivity.kt) when the app is backgrounded/locked.
/// The command text is always shown in full before either button is
/// enabled — there is no default / pre-selected action.
class ApprovalScreen extends StatefulWidget {
  final PendingCommand command;
  const ApprovalScreen({super.key, required this.command});

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  Timer? _tick;
  Duration _remaining = Duration.zero;
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  void _updateRemaining() {
    if (!mounted) return;
    final rem = widget.command.expiresAt.difference(DateTime.now());
    setState(() => _remaining = rem.isNegative ? Duration.zero : rem);
    if (rem.isNegative && !_decided) {
      _decided = true;
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _approve() {
    if (_decided) return;
    _decided = true;
    LanClientService().approveCommand(widget.command.commandId);
    Navigator.of(context).maybePop();
  }

  void _reject() {
    if (_decided) return;
    _decided = true;
    LanClientService().rejectCommand(widget.command.commandId);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final mins = _remaining.inMinutes;
    final secs = _remaining.inSeconds % 60;
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 56),
              const SizedBox(height: 16),
              const Text('طلب تنفيذ أمر',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  widget.command.describe(),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              const SizedBox(height: 12),
              Text('ينتهي تلقائيًا (يُرفض) خلال $mins:${secs.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _reject,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('رفض', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _approve,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('موافقة وتنفيذ', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
