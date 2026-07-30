// player_model.dart
// 玩家蛊师数据模型，与单机MUD玩家存档结构完全一致。
import 'gu_model.dart';

class Player {
  String name;
  String title;
  String align; // 正道/魔道/中立
  String level; // 一转初阶 ~ 九转巅峰
  int slotMax;
  int slotBonus;
  int trueyuan;
  int trueyuanMax;
  double lifeLeft;
  double lifeMax;
  int physique;
  int soulPower;
  Map<String, double> daoMark;
  List<String> injure;
  int luck;
  String location;
  List<String> inventory;
  List<GuInstance> guInSlot;
  List<GuInstance> guBag;
  Map<String, dynamic> flags;
  double worldTime;
  double refineProficiency;
  double tribulation;
  int kills;
  bool alive;

  Player({
    this.name = '无名蛊师',
    this.title = '',
    this.align = '中立',
    this.level = '一转初阶',
    this.slotMax = 3,
    this.slotBonus = 0,
    this.trueyuan = 50,
    this.trueyuanMax = 100,
    this.lifeLeft = 80,
    this.lifeMax = 80,
    this.physique = 30,
    this.soulPower = 30,
    Map<String, double>? daoMark,
    List<String>? injure,
    this.luck = 10,
    this.location = 'qingmao_01',
    List<String>? inventory,
    List<GuInstance>? guInSlot,
    List<GuInstance>? guBag,
    Map<String, dynamic>? flags,
    this.worldTime = 0,
    this.refineProficiency = 0,
    this.tribulation = 0,
    this.kills = 0,
    this.alive = true,
  })  : daoMark = daoMark ?? {},
        injure = injure ?? [],
        inventory = inventory ?? [],
        guInSlot = guInSlot ?? [],
        guBag = guBag ?? [],
        flags = flags ?? {};

  int get effectiveSlotMax => slotMax + slotBonus;
  int get freeSlotCount => effectiveSlotMax - guInSlot.length;

  void spendTrueyuan(int n) {
    trueyuan = (trueyuan - n).clamp(0, trueyuanMax).toInt();
  }

  void recoverTrueyuan(int n) {
    trueyuan = (trueyuan + n).clamp(0, trueyuanMax).toInt();
  }

  void addDaoMark(String school, double amount) {
    daoMark[school] = (daoMark[school] ?? 0) + amount;
  }

  void addInjure(String inj) {
    if (!injure.contains(inj)) injure.add(inj);
  }

  void healInjure(String inj) {
    injure.remove(inj);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'align': align,
        'level': level,
        'slot_max': slotMax,
        'slot_bonus': slotBonus,
        'trueyuan': trueyuan,
        'trueyuan_max': trueyuanMax,
        'life_left': lifeLeft,
        'life_max': lifeMax,
        'physique': physique,
        'soul_power': soulPower,
        'dao_mark': daoMark,
        'injure': injure,
        'luck': luck,
        'location': location,
        'inventory': inventory,
        'gu_in_slot': guInSlot.map((g) => g.toJson()).toList(),
        'gu_bag': guBag.map((g) => g.toJson()).toList(),
        'flags': flags,
        'world_time': worldTime,
        'refine_proficiency': refineProficiency,
        'tribulation': tribulation,
        'kills': kills,
        'alive': alive,
      };

  factory Player.fromJson(Map<String, dynamic> j) {
    return Player(
      name: j['name'] ?? '无名蛊师',
      title: j['title'] ?? '',
      align: j['align'] ?? '中立',
      level: j['level'] ?? '一转初阶',
      slotMax: j['slot_max'] ?? 3,
      slotBonus: j['slot_bonus'] ?? 0,
      trueyuan: j['trueyuan'] ?? 50,
      trueyuanMax: j['trueyuan_max'] ?? 100,
      lifeLeft: (j['life_left'] ?? 80).toDouble(),
      lifeMax: (j['life_max'] ?? 80).toDouble(),
      physique: j['physique'] ?? 30,
      soulPower: j['soul_power'] ?? 30,
      daoMark: Map<String, double>.from(
          (j['dao_mark'] ?? {}).map((k, v) => MapEntry(k, (v as num).toDouble()))),
      injure: List<String>.from(j['injure'] ?? []),
      luck: j['luck'] ?? 10,
      location: j['location'] ?? 'qingmao_01',
      inventory: List<String>.from(j['inventory'] ?? []),
      guInSlot: (j['gu_in_slot'] as List? ?? [])
          .map((g) => GuInstance.fromJson(g as Map<String, dynamic>))
          .toList(),
      guBag: (j['gu_bag'] as List? ?? [])
          .map((g) => GuInstance.fromJson(g as Map<String, dynamic>))
          .toList(),
      flags: Map<String, dynamic>.from(j['flags'] ?? {}),
      worldTime: (j['world_time'] ?? 0).toDouble(),
      refineProficiency: (j['refine_proficiency'] ?? 0).toDouble(),
      tribulation: (j['tribulation'] ?? 0).toDouble(),
      kills: j['kills'] ?? 0,
      alive: j['alive'] ?? true,
    );
  }
}
