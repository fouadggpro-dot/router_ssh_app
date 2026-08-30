import 'dart:convert';

/// Envelope for every message exchanged with the Controller.
/// See PROTOCOL.md for the full spec.
class NetworkMessage {
  final String messageId;
  final String deviceId;
  final String type;
  final int timestamp;
  final Map<String, dynamic> payload;

  NetworkMessage({
    required this.messageId,
    required this.deviceId,
    required this.type,
    required this.timestamp,
    required this.payload,
  });

  String encode() => jsonEncode({
        'messageId': messageId,
        'deviceId': deviceId,
        'type': type,
        'timestamp': timestamp,
        'payload': payload,
      });

  static NetworkMessage decode(String raw) {
    final Map<String, dynamic> m = jsonDecode(raw) as Map<String, dynamic>;
    return NetworkMessage(
      messageId: m['messageId']?.toString() ?? '',
      deviceId: m['deviceId']?.toString() ?? '',
      type: m['type']?.toString() ?? '',
      timestamp: (m['timestamp'] is int) ? m['timestamp'] as int : 0,
      payload: (m['payload'] is Map)
          ? Map<String, dynamic>.from(m['payload'] as Map)
          : <String, dynamic>{},
    );
  }
}

/// Kinds of commands the Controller may *request*. Every one of these
/// requires an explicit user approval before `LanClientService` will
/// ever invoke the platform channel that does real work.
enum CommandKind { sshScript, apkUpdate, unknown }

CommandKind commandKindFromString(String s) {
  switch (s) {
    case 'SSH_SCRIPT':
      return CommandKind.sshScript;
    case 'APK_UPDATE':
      return CommandKind.apkUpdate;
    default:
      return CommandKind.unknown;
  }
}

/// A command request waiting on the user, surfaced by the approval UI.
class PendingCommand {
  final String commandId;
  final CommandKind kind;
  final Map<String, dynamic> params;
  final DateTime receivedAt;
  final int expiresInSec;

  PendingCommand({
    required this.commandId,
    required this.kind,
    required this.params,
    required this.receivedAt,
    required this.expiresInSec,
  });

  DateTime get expiresAt => receivedAt.add(Duration(seconds: expiresInSec));
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Human-readable description shown on the approval screen —
  /// never auto-executed, always read by the user before they decide.
  String describe() {
    switch (kind) {
      case CommandKind.sshScript:
        final cmd = params['command'] ?? '(unknown command)';
        final host = params['host'] ?? 'router';
        return 'تنفيذ أمر صيانة على $host:\n$cmd';
      case CommandKind.apkUpdate:
        final version = params['version'] ?? '?';
        return 'تحديث التطبيق إلى الإصدار $version';
      case CommandKind.unknown:
        return 'أمر غير معروف';
    }
  }
}
