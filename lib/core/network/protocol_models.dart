import 'dart:convert';

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

  Map<String, dynamic> toJson() => {
        'header': {
          'messageId': messageId,
          'deviceId': deviceId,
          'timestamp': timestamp,
          'type': type,
        },
        'payload': payload,
      };

  factory NetworkMessage.fromJson(Map<String, dynamic> json) {
    final header = json['header'] as Map<String, dynamic>;
    return NetworkMessage(
      messageId: header['messageId'] ?? '',
      deviceId: header['deviceId'] ?? '',
      type: header['type'] ?? '',
      timestamp: header['timestamp'] ?? 0,
      payload: json['payload'] as Map<String, dynamic>? ?? {},
    );
  }

  String encode() => jsonEncode(toJson());

  factory NetworkMessage.decode(String str) => NetworkMessage.fromJson(jsonDecode(str));
}