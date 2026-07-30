// scene_model.dart
// 场景地图房间模型。
class Room {
  final String rid;
  final String name;
  final String description;
  final Map<String, String> exits; // north/south/east/west -> rid
  final Map<String, double> envEffect;
  final List<String> refreshResource;
  final List<String> wildGu; // gid 列表（可被捕捉后移除）
  final List<String> npcList; // nid 列表
  final String secret;

  Room({
    required this.rid,
    required this.name,
    required this.description,
    this.exits = const {},
    this.envEffect = const {},
    this.refreshResource = const [],
    this.wildGu = const [],
    this.npcList = const [],
    this.secret = '',
  });

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        rid: j['rid'],
        name: j['name'],
        description: j['description'],
        exits: Map<String, String>.from(j['exits'] ?? {}),
        envEffect: Map<String, double>.from(
            (j['env_effect'] ?? {}).map((k, v) => MapEntry(k, (v as num).toDouble()))),
        refreshResource: List<String>.from(j['refresh_resource'] ?? []),
        wildGu: List<String>.from(j['wild_gu'] ?? []),
        npcList: List<String>.from(j['npc_list'] ?? []),
        secret: j['secret'] ?? '',
      );
}
