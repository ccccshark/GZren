// npc_model.dart
// NPC/异兽实体模型，基于模板生成，带运行时状态。
import 'gu_model.dart';

class NpcTemplate {
  final String nid;
  final String name;
  final String align;
  final String level;
  final double lifeLeft;
  final int trueyuan;
  final int trueyuanMax;
  final int physique;
  final int soulPower;
  final int slotMax;
  final List<String> guInSlot; // gid 列表
  final Map<String, double> daoMark;
  final List<String> inventory;
  final bool isHostile;
  final bool isMerchant;
  final bool isBeast;
  final List<String> dialogue;
  final Map<String, int> tradeGoods;
  // 第三阶段新增【10.三大势力NPC+AI行为】：AI类型与势力归属。
  // ai_type: aggressive(凶猛主动)/defend(防御自保)/calm(中立平和)/smart(高阶智能)。
  // faction: qingmao(青茅山宗族)/heiya(黑崖寨)/sanxiu(南疆散修联盟)/""(无势力)。
  // 旧JSON缺失时默认 'calm' / ''，不报错。
  final String aiType;
  final String faction;

  NpcTemplate({
    required this.nid,
    required this.name,
    this.align = '中立',
    this.level = '一转初阶',
    this.lifeLeft = 50,
    this.trueyuan = 50,
    this.trueyuanMax = 50,
    this.physique = 30,
    this.soulPower = 20,
    this.slotMax = 3,
    this.guInSlot = const [],
    this.daoMark = const {},
    this.inventory = const [],
    this.isHostile = false,
    this.isMerchant = false,
    this.isBeast = false,
    this.dialogue = const [],
    this.tradeGoods = const {},
    this.aiType = 'calm',
    this.faction = '',
  });

  factory NpcTemplate.fromJson(Map<String, dynamic> j) => NpcTemplate(
        nid: j['nid'],
        name: j['name'],
        align: j['align'] ?? '中立',
        level: j['level'] ?? '一转初阶',
        lifeLeft: (j['life_left'] ?? 50).toDouble(),
        trueyuan: j['trueyuan'] ?? 50,
        trueyuanMax: j['trueyuan_max'] ?? 50,
        physique: j['physique'] ?? 30,
        soulPower: j['soul_power'] ?? 20,
        slotMax: j['slot_max'] ?? 3,
        guInSlot: List<String>.from(j['gu_in_slot'] ?? []),
        daoMark: Map<String, double>.from(
            (j['dao_mark'] ?? {}).map((k, v) => MapEntry(k, (v as num).toDouble()))),
        inventory: List<String>.from(j['inventory'] ?? []),
        isHostile: j['is_hostile'] ?? false,
        isMerchant: j['is_merchant'] ?? false,
        isBeast: j['is_beast'] ?? false,
        dialogue: List<String>.from(j['dialogue'] ?? []),
        tradeGoods: Map<String, int>.from(
            (j['trade_goods'] ?? {}).map((k, v) => MapEntry(k, (v as num).toInt()))),
        aiType: j['ai_type'] ?? 'calm',
        faction: j['faction'] ?? '',
      );
}

class Npc {
  final String nid;
  final String name;
  final String align;
  String level;
  double lifeLeft;
  int trueyuan;
  int trueyuanMax;
  int physique;
  int physiqueMax;
  int soulPower;
  int slotMax;
  List<String> guInSlot; // gid 列表
  Map<String, double> daoMark;
  List<String> inventory;
  bool isHostile;
  bool isMerchant;
  bool isBeast;
  List<String> dialogue;
  Map<String, int> tradeGoods;
  // 第三阶段新增【10】：运行时 AI 类型与势力（从模板拷贝，供上层战斗日志/支援判定读取）。
  String aiType;
  String faction;
  String? homeRid;
  // 运行时
  bool alive;
  int hatePlayer;
  double? deathTime;
  String lastAction;
  // 初始蛊/背包快照（供重生使用）
  late List<String> origGuInSlot;
  late List<String> origInventory;

  // 用于战斗的临时蛊实例（由 combat 物化）
  List<GuInstance> combatGus = [];

  Npc.fromTemplate(NpcTemplate t)
      : nid = t.nid,
        name = t.name,
        align = t.align,
        level = t.level,
        lifeLeft = t.lifeLeft,
        trueyuan = t.trueyuan,
        trueyuanMax = t.trueyuanMax,
        physique = t.physique,
        physiqueMax = t.physique,
        soulPower = t.soulPower,
        slotMax = t.slotMax,
        guInSlot = List<String>.from(t.guInSlot),
        daoMark = Map<String, double>.from(t.daoMark),
        inventory = List<String>.from(t.inventory),
        isHostile = t.isHostile,
        isMerchant = t.isMerchant,
        isBeast = t.isBeast,
        dialogue = t.dialogue,
        tradeGoods = Map<String, int>.from(t.tradeGoods),
        aiType = t.aiType,
        faction = t.faction,
        alive = true,
        hatePlayer = 0,
        deathTime = null,
        lastAction = 'idle';

  Map<String, dynamic> toJson() => {
        'nid': nid,
        'alive': alive,
        'physique': physique,
        'trueyuan': trueyuan,
        'hate_player': hatePlayer,
        'death_time': deathTime,
        'gu_in_slot': guInSlot,
        'inventory': inventory,
        'last_action': lastAction,
      };

  void fromJson(Map<String, dynamic> j) {
    alive = j['alive'] ?? true;
    physique = j['physique'] ?? physique;
    trueyuan = j['trueyuan'] ?? trueyuan;
    hatePlayer = j['hate_player'] ?? 0;
    deathTime = j['death_time']?.toDouble();
    guInSlot = List<String>.from(j['gu_in_slot'] ?? guInSlot);
    inventory = List<String>.from(j['inventory'] ?? inventory);
    lastAction = j['last_action'] ?? 'idle';
  }

  void respawn() {
    physique = physiqueMax;
    trueyuan = trueyuanMax;
    guInSlot = List<String>.from(origGuInSlot);
    inventory = List<String>.from(origInventory);
    alive = true;
    hatePlayer = 0;
    deathTime = null;
  }

  void storeOriginals() {
    origGuInSlot = List<String>.from(guInSlot);
    origInventory = List<String>.from(inventory);
  }
}
