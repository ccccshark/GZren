// slot_capacity_model.dart
// 第二阶段新增：空窍承载上限系统（增量文件，不动旧代码）。
// 设计原则：
//   - 100% 兼容旧存档：空窍容量状态写入 player.flags['slot_capacity_v2']，旧存档无键时回退兼容逻辑
//   - 不修改 Player 模型字段，仅通过 flags 与现有 guInSlot/guBag 联动计算
//   - 超限惩罚：真元恢复暴跌、持续滋生暗伤、无法继续装备新蛊
//   - 扩容途径：拓窍蛊（新 combat.type='expand_slot'）、境界突破同步扩容
//
// 容量规则（原著设定）：
//   一转 容量 = 50  ；二转 = 100 ；三转 = 180 ；四转 = 280 ；
//   五转 容量 = 420 ；六转 = 600 ；七转 = 850 ；八转 = 1200 ；九转 = 9999 。
//   每只蛊占用容量 = rank * 10 （高转蛊占用更大）。
//   储物蛊(combat.type='storage')占用容量打 5 折（其内部承载不算空窍容量）。
import 'player_model.dart';
import 'gu_model.dart';
import '../engine/player_core.dart' show levelRank;

/// 境界基准容量（不含蛊虫/拓窍加成）。
const Map<int, int> _rankBaseCapacity = {
  1: 50, 2: 100, 3: 180, 4: 280,
  5: 420, 6: 600, 7: 850, 8: 1200, 9: 9999,
};

/// 单蛊占用容量：rank*10，储物蛊打 5 折。
int guOccupancy(GuInstance g) {
  final base = g.rank * 10;
  final ctype = g.combat['type'];
  if (ctype == 'storage') return (base * 0.5).round();
  return base;
}

int guTplOccupancy(GuTemplate t) {
  final base = t.rank * 10;
  final ctype = t.combat['type'];
  if (ctype == 'storage') return (base * 0.5).round();
  return base;
}

/// 空窍容量工具类（全部静态，兼容旧存档）。
class SlotCapacity {
  // ---------- 基础容量 ----------
  static int baseCapacity(Player p) =>
      _rankBaseCapacity[levelRank(p.level)] ?? 50;

  /// 拓窍蛊带来的容量加成（flags['slot_capacity_v2']['expand_bonus']，旧存档 0）。
  static int expandBonus(Player p) {
    final raw = p.flags['slot_capacity_v2'];
    if (raw is Map) return ((raw['expand_bonus'] as num?) ?? 0).toInt();
    return 0;
  }

  static void addExpandBonus(Player p, int delta) {
    final cur = expandBonus(p);
    final next = cur + delta;
    final m = Map<String, dynamic>.from(p.flags['slot_capacity_v2'] is Map
        ? p.flags['slot_capacity_v2'] as Map : {});
    m['expand_bonus'] = next;
    p.flags['slot_capacity_v2'] = m;
  }

  /// 空窍总容量上限（基础 + 拓窍加成）。
  static int capacityMax(Player p) =>
      baseCapacity(p) + expandBonus(p);

  // ---------- 占用计算 ----------
  /// 空窍中所有蛊的占用总和。
  static int usedCapacity(Player p) {
    int s = 0;
    for (final g in p.guInSlot) s += guOccupancy(g);
    return s;
  }

  /// 背包寄存蛊的占用总和（不用于空窍超限判定，但用于储物蛊容量）。
  static int bagUsedCapacity(Player p) {
    int s = 0;
    for (final g in p.guBag) s += guOccupancy(g);
    return s;
  }

  /// 剩余可用容量（装备新蛊前检查）。
  static int freeCapacity(Player p) =>
      capacityMax(p) - usedCapacity(p);

  /// 是否超限（>=0 正常，<0 超限）。
  static bool isOverloaded(Player p) => freeCapacity(p) < 0;

  /// 超限比例（用于惩罚计算），超限越多惩罚越重，0~0.5 及以上封顶。
  static double overloadRatio(Player p) {
    final cmax = capacityMax(p);
    if (cmax <= 0) return 0.0;
    final over = usedCapacity(p) - cmax;
    if (over <= 0) return 0.0;
    return (over / cmax).clamp(0.0, 0.5);
  }

  // ---------- 惩罚 ----------
  /// 真元恢复倍率：超限越多倍率越低，最低 0.1 倍。
  static double trueyuanRecoverMultiplier(Player p) {
    final r = overloadRatio(p);
    if (r <= 0) return 1.0;
    return (1.0 - r * 1.8).clamp(0.1, 1.0);
  }

  /// 每世界日（24h）因超限产生的暗伤概率：r=0.5 时 80%。
  static double dailyDarkInjuryChance(Player p) {
    final r = overloadRatio(p);
    return (r * 1.6).clamp(0.0, 0.8);
  }

  // ---------- 兼容旧存档：旧存档无条件允许装备，直到首次超限后开始严格检查 ----------
  /// 旧存档（无 slot_capacity_v2 键）视为未启用严格模式，装备时不阻断，仅显示提示。
  static bool strictMode(Player p) =>
      p.flags['slot_capacity_v2'] is Map; // 只要写过一次容量数据就开启严格模式

  /// 在玩家首次使用新版时初始化 flags，进入严格模式但不惩罚既有装备。
  static void ensureStrictMode(Player p) {
    if (strictMode(p)) return;
    final m = Map<String, dynamic>.from(p.flags['slot_capacity_v2'] is Map
        ? p.flags['slot_capacity_v2'] as Map : {});
    m['expand_bonus'] = m['expand_bonus'] ?? 0;
    m['init_day'] = (p.worldTime / 24).floor();
    p.flags['slot_capacity_v2'] = m;
  }

  /// 可装备性检查：返回 (ok, reason)。用于 equip 调用端阻断。
  static (bool, String) canEquip(Player p, GuInstance g) {
    if (!strictMode(p)) return (true, '');
    final need = guOccupancy(g);
    final free = freeCapacity(p);
    if (free >= need) return (true, '');
    return (false, '空窍容量不足，装备 ${g.name} 需 $need 容量，仅余 $free。需拓窍或更换低转蛊。');
  }

  /// 便捷包装：单蛊占用容量（同 guOccupancy）。
  static int guUse(GuInstance g) => guOccupancy(g);
}
