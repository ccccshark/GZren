// gu_model.dart
// 蛊虫模板与蛊虫实例模型。
class GuTemplate {
  final String gid;
  final String name;
  final int rank;
  final String school;
  final int costZhen;
  final int costLife;
  final int durabilityMax;
  final List<String> feedMaterial;
  final String sideEffect;
  final String desc;
  final String evolveGid;
  final List<String> habitat;
  final Map<String, dynamic> combat;
  // V1.4 新增【蛊虫变异机制】：is_mutate=true 标记此蛊为易变异蛊，
  // 炼制时变异概率显著提升（5%→15%），变异后威力加成更高。旧JSON无此字段默认 false。
  final bool isMutate;

  GuTemplate({
    required this.gid,
    required this.name,
    required this.rank,
    required this.school,
    this.costZhen = 0,
    this.costLife = 0,
    this.durabilityMax = 100,
    this.feedMaterial = const [],
    this.sideEffect = '无明显副作用',
    this.desc = '',
    this.evolveGid = '',
    this.habitat = const [],
    this.combat = const {},
    this.isMutate = false,
  });

  factory GuTemplate.fromJson(Map<String, dynamic> j) => GuTemplate(
        gid: j['gid'],
        name: j['name'],
        rank: j['rank'],
        school: j['school'],
        costZhen: j['cost_zhen'] ?? 0,
        costLife: j['cost_life'] ?? 0,
        durabilityMax: j['durability_max'] ?? 100,
        feedMaterial: List<String>.from(j['feed_material'] ?? []),
        sideEffect: j['side_effect'] ?? '无明显副作用',
        desc: j['desc'] ?? '',
        evolveGid: j['evolve_gid'] ?? '',
        habitat: List<String>.from(j['habitat'] ?? []),
        combat: Map<String, dynamic>.from(j['combat'] ?? {}),
        isMutate: j['is_mutate'] ?? false,
      );
}

class GuInstance {
  final String instId;
  final String gid;
  String name;
  final int rank;
  final String school;
  final int costZhen;
  final int costLife;
  final int durabilityMax;
  int durability;
  final List<String> feedMaterial;
  String sideEffect;
  final Map<String, dynamic> combat;
  bool mutated;

  GuInstance({
    required this.instId,
    required this.gid,
    required this.name,
    required this.rank,
    required this.school,
    this.costZhen = 0,
    this.costLife = 0,
    required this.durabilityMax,
    required this.durability,
    this.feedMaterial = const [],
    this.sideEffect = '无明显副作用',
    this.combat = const {},
    this.mutated = false,
  });

  Map<String, dynamic> toJson() => {
        'inst_id': instId,
        'gid': gid,
        'name': name,
        'rank': rank,
        'school': school,
        'cost_zhen': costZhen,
        'cost_life': costLife,
        'durability_max': durabilityMax,
        'durability': durability,
        'feed_material': feedMaterial,
        'side_effect': sideEffect,
        'combat': combat,
        'mutated': mutated,
      };

  factory GuInstance.fromJson(Map<String, dynamic> j) => GuInstance(
        instId: j['inst_id'] ?? '',
        gid: j['gid'] ?? '',
        name: j['name'] ?? '',
        rank: j['rank'] ?? 1,
        school: j['school'] ?? '气道',
        costZhen: j['cost_zhen'] ?? 0,
        costLife: j['cost_life'] ?? 0,
        durabilityMax: j['durability_max'] ?? 100,
        durability: j['durability'] ?? 100,
        feedMaterial: List<String>.from(j['feed_material'] ?? []),
        sideEffect: j['side_effect'] ?? '无明显副作用',
        combat: Map<String, dynamic>.from(j['combat'] ?? {}),
        // 第三阶段新增【8.6 变异蛊标记预留】：兼容 mutated 与 is_mutate 两种字段名，
        // 缺失时默认 false，旧存档/旧JSON无此字段不报错，适配后续变异系统。
        mutated: (j['mutated'] ?? j['is_mutate'] ?? false) as bool,
      );
}
