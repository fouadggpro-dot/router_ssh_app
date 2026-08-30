import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../security/device_identity.dart';
import '../protocol/protocol_models.dart';

/// Connects to the Controller found on the LAN and relays commands to
/// the UI for approval. This class NEVER executes a command itself —
/// it only ever calls into the SSH/update platform channel from
/// `approveCommand()`, which is only reachable from an explicit user
/// tap on the approval screen. There is no timer-based execution path
/// anywhere in this file.
class LanClientService {
  static final LanClientService _instance = LanClientService._internal();
  factory LanClientService() => _instance;
  LanClientService._internal();

  static const _sshPlatform = MethodChannel('com.routercontroller.agent/ssh');
  static const _updatePlatform =
      MethodChannel('com.routercontroller.agent/update');
  static const _notifyPlatform =
      MethodChannel('com.routercontroller.agent/notify');

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _discoveryTimer;
  Timer? _expiryTimer;

  String? _controllerIp;
  int _controllerPort = 8080;
  bool _isConnected = false;

  final Map<String, PendingCommand> _pending = {};

  /// UI callbacks.
  void Function(PendingCommand cmd)? onCommandPending;
  void Function(String commandId)? onCommandExpired;
  void Function(bool connected)? onConnectionChanged;
  void Function(String reason)? onPairingRejected;

  bool get isConnected => _isConnected;
  Map<String, PendingCommand> get pendingCommands => Map.unmodifiable(_pending);

  void start() {
    _startUdpDiscovery();
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sweepExpired());
  }

  void _startUdpDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_isConnected) return;
      try {
        final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;
        final deviceId = await DeviceIdentityService.getOrCreateDeviceId();
        socket.send('DISCOVER_CONTROLLER:$deviceId'.codeUnits,
            InternetAddress('255.255.255.255'), 8888);

        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final dg = socket.receive();
          if (dg == null) return;
          final response = String.fromCharCodes(dg.data);
          if (response.startsWith('CONTROLLER_OFFER')) {
            final parts = response.split(':');
            if (parts.length >= 3) {
              _controllerIp = parts[1];
              _controllerPort = int.tryParse(parts[2]) ?? 8080;
              socket.close();
              _connectWebSocket();
            }
          }
        });
      } catch (_) {
        // network unreachable this cycle; next timer tick retries
      }
    });
  }

  void _connectWebSocket() async {
    if (_controllerIp == null || _isConnected) return;
    final wsUrl = Uri.parse('ws://$_controllerIp:$_controllerPort/ws');
    try {
      _channel = IOWebSocketChannel.connect(wsUrl, connectTimeout: const Duration(seconds: 5));
      _isConnected = true;
      _discoveryTimer?.cancel();
      onConnectionChanged?.call(true);

      final paired = await DeviceIdentityService.isPaired();
      if (!paired) {
        // Pairing must be initiated explicitly by the user entering the
        // code shown on the Controller's dashboard — see PairingScreen.
        // We stay connected but do not register until that happens.
      } else {
        await _sendRegisterRequest();
        _startHeartbeat();
      }

      _channel!.stream.listen(
        (data) => _handleIncomingMessage(data),
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  /// Called by PairingScreen after the user types in the code shown on
  /// the Controller. This is the only way `deviceToken` gets set.
  Future<bool> submitPairingCode(String code) async {
    if (!_isConnected) return false;
    final deviceId = await DeviceIdentityService.getOrCreateDeviceId();
    final msg = NetworkMessage(
      messageId: 'pair_${DateTime.now().millisecondsSinceEpoch}',
      deviceId: deviceId,
      type: 'PAIR_REQUEST',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {'code': code},
    );
    final completer = Completer<bool>();
    _pairingCompleter = completer;
    _sendMessage(msg);
    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
  }

  Completer<bool>? _pairingCompleter;

  Future<void> _sendRegisterRequest() async {
    final deviceId = await DeviceIdentityService.getOrCreateDeviceId();
    final userName = await DeviceIdentityService.getUserName();
    final token = await DeviceIdentityService.getPairToken();
    final msg = NetworkMessage(
      messageId: 'reg_${DateTime.now().millisecondsSinceEpoch}',
      deviceId: deviceId,
      type: 'DEVICE_REGISTER',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: {'pairToken': token, 'userName': userName, 'appVersion': '1.0.0'},
    );
    _sendMessage(msg);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isConnected) return;
      final deviceId = await DeviceIdentityService.getOrCreateDeviceId();
      _sendMessage(NetworkMessage(
        messageId: 'hb_${DateTime.now().millisecondsSinceEpoch}',
        deviceId: deviceId,
        type: 'HEARTBEAT',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: {},
      ));
    });
  }

  void _handleIncomingMessage(dynamic raw) async {
    try {
      final msg = NetworkMessage.decode(raw.toString());
      switch (msg.type) {
        case 'PAIR_ACCEPTED':
          final token = msg.payload['deviceToken']?.toString() ?? '';
          await DeviceIdentityService.setPairToken(token);
          _pairingCompleter?.complete(true);
          await _sendRegisterRequest();
          _startHeartbeat();
          break;

        case 'PAIR_REJECTED':
          _pairingCompleter?.complete(false);
          onPairingRejected?.call(msg.payload['reason']?.toString() ?? '');
          break;

        case 'COMMAND_REQUEST':
          // Only ever queued for user review. Nothing executes here.
          final commandId = msg.payload['commandId']?.toString() ?? msg.messageId;
          final kind = commandKindFromString(msg.payload['kind']?.toString() ?? '');
          final params = (msg.payload['params'] is Map)
              ? Map<String, dynamic>.from(msg.payload['params'] as Map)
              : <String, dynamic>{};
          final expires = (msg.payload['expiresInSec'] is int)
              ? msg.payload['expiresInSec'] as int
              : 1800; // default 30 min, matches PROTOCOL.md
          final pc = PendingCommand(
            commandId: commandId,
            kind: kind,
            params: params,
            receivedAt: DateTime.now(),
            expiresInSec: expires,
          );
          _pending[commandId] = pc;
          _sendSimple('COMMAND_PENDING_ACK', {'commandId': commandId});
          onCommandPending?.call(pc);
          // Full-screen-intent notification: only ever surfaces the
          // request for review, never a "silently execute" action.
          _notifyPlatform.invokeMethod('showApprovalRequest', {
            'commandId': commandId,
            'summary': pc.describe(),
          }).catchError((_) {});
          break;
      }
    } catch (_) {
      // malformed frame; ignore
    }
  }

  /// The ONLY entry point that leads to real execution, and it is only
  /// ever called from the approval screen's "Approve" button handler.
  Future<void> approveCommand(String commandId) async {
    final cmd = _pending[commandId];
    if (cmd == null || cmd.isExpired) return;
    _pending.remove(commandId);
    _sendSimple('COMMAND_APPROVED', {'commandId': commandId});

    Map<String, dynamic> result;
    switch (cmd.kind) {
      case CommandKind.sshScript:
        result = await _executeSshCommand(cmd.params);
        break;
      case CommandKind.apkUpdate:
        result = await _executeApkUpdate(cmd.params);
        break;
      case CommandKind.unknown:
        result = {'success': false, 'error': 'unknown command kind'};
        break;
    }

    _sendSimple('COMMAND_RESULT', {
      'commandId': commandId,
      'success': result['success'] ?? false,
      'exitCode': result['exitCode'] ?? -1,
      'output': result['output'] ?? '',
      'error': result['error'] ?? '',
    });
  }

  void rejectCommand(String commandId, {String reason = 'user_rejected'}) {
    if (_pending.remove(commandId) == null) return;
    _sendSimple('COMMAND_REJECTED', {'commandId': commandId, 'reason': reason});
  }

  void _sweepExpired() {
    final expired = _pending.values.where((c) => c.isExpired).toList();
    for (final c in expired) {
      _pending.remove(c.commandId);
      _sendSimple('COMMAND_REJECTED', {'commandId': c.commandId, 'reason': 'expired'});
      onCommandExpired?.call(c.commandId);
    }
  }

  Future<Map<String, dynamic>> _executeSshCommand(Map<String, dynamic> params) async {
    final routerCfg = await DeviceIdentityService.getRouterConfig();
    try {
      final dynamic raw = await _sshPlatform.invokeMethod('executeScript', {
        'host': routerCfg['host'],
        'port': int.tryParse(routerCfg['port'] ?? '22') ?? 22,
        'username': routerCfg['username'],
        'password': routerCfg['password'],
        'command': params['command'] ?? '',
      }).timeout(const Duration(seconds: 15),
          onTimeout: () => {'success': false, 'error': 'timeout'});
      return Map<String, dynamic>.from(raw as Map);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _executeApkUpdate(Map<String, dynamic> params) async {
    try {
      final dynamic raw = await _updatePlatform.invokeMethod('installApk', {
        'url': params['url'] ?? '',
        'version': params['version'] ?? '',
      });
      return Map<String, dynamic>.from(raw as Map);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  void _sendSimple(String type, Map<String, dynamic> payload) async {
    final deviceId = await DeviceIdentityService.getOrCreateDeviceId();
    _sendMessage(NetworkMessage(
      messageId: '${type.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}',
      deviceId: deviceId,
      type: type,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: payload,
    ));
  }

  void _sendMessage(NetworkMessage msg) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(msg.encode());
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    onConnectionChanged?.call(false);
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _startUdpDiscovery();
  }

  /// User-initiated disconnect from the "unlink" button — always available.
  void disconnectAndForget() async {
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    await DeviceIdentityService.clearPairing();
    onConnectionChanged?.call(false);
    _startUdpDiscovery();
  }
}
