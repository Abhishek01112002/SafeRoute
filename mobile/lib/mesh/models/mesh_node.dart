class MeshNode {
  final String userId;
  final String name;
  final bool connected;
  final DateTime lastSeen;
  final int? battery;
  final double? lat;
  final double? lng;
  final int rssi;

  MeshNode({
    required this.userId,
    required this.name,
    this.connected = false,
    required this.lastSeen,
    this.battery,
    this.lat,
    this.lng,
    required this.rssi,
  });

  factory MeshNode.fromScan(String id, String name, int rssi) {
    return MeshNode(
      userId: id,
      name: name,
      connected: true,
      lastSeen: DateTime.now(),
      rssi: rssi,
    );
  }
}
