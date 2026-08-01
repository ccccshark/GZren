// storage_gu_model.dart
// 第二阶段新增：储物蛊背包体系（增量文件，不动旧代码）。
// 设计原则：
//   - 100% 兼容旧存档：储物状态写入 player.flags['storage_v2']，旧存档无键回退兼容
//   - 不修改 Player.inventory 字段，通过 flags 记录启用状态；启用后 addMaterial/consumeMaterial
//     会受容量限制，但允许超容量读（防止旧存档物资丢失）
//   - 取消无限背包：玩家必须持有储物蛊才能携带大量物资，高阶储物蛊容量更大
//   - 无储物蛊：仅能携带基础随身 10 件物资（原著：赤手空拳只能拿手上那点东西）
//
// 容量规则：
//   随身基础容量 = 10 件（任何材料数量不计堆叠，按条算；储物蛊内部按堆叠条算）
//   储物蛊容量 = 1 转 30、2 转 80、3 转 200、4 转 500、5 转 1500、6 转 5000
//   多只储物蛊容量叠加（最多 3 只生效：空窍中所有 combat.type='storage' 蛊）
//   背包总容量 = 随身10 + 所有生效储物蛊容量之和
import 'dart:math' show max, min;
import 'player_model.dart';
import 'gu_model.dart';
import 'recipe_model.dart' show MatParser;

/// 储物蛊等级容量映射（按蛊 rank，单位：堆叠条数）。
const Map<int, int> _storageRankCapacity = {
  1: 30, 2: 80, 3: 200, 4: 500, 5: 1500, 6: 5000,
};

/// 单只储物蛊提供的容量。
int storageGuCapacity(GuInstance g) {
  if ((g.combat['type'] ?? '') != 'storage') return 0;
  return _storageRankCapacity[g.rank] ?? 0;
}

int storageGuTplCapacity(GuTemplate t) {
  if ((t.combat['type'] ?? '') != 'storage') return 0;
  return _storageRankCapacity[t.rank] ?? 0;
}

/// 储物蛊背包容量工具（兼容旧存档）。
class StorageGu {
  // ---------- 容量 ----------
  /// 随身基础容量（10 件）。
  static const int carryBase = 10;

  /// 储物蛊提供的容量总和（空窍中最多 3 只生效）。
  static int storageBonus(Player p) {
    int n = 0;
    int cnt = 0;
    for (final g in p.guInSlot) {
      final c = storageGuCapacity(g);
      if (c > 0 && cnt < 3) {
        n += c;
        cnt += 1;
      }
    }
    return n;
  }

  /// 背包总容量上限。
  static int capacityMax(Player p) => carryBase + storageBonus(p);

  /// 当前背包使用容量（按堆叠条数计算，不看单条数量）。
  static int usedCapacity(Player p) => p.inventory.length;

  /// 剩余可用容量。
  static int freeCapacity(Player p) =>
      capacityMax(p) - usedCapacity(p);

  // ---------- 兼容旧存档 ----------
  /// 严格模式：启用后 addMaterial 会受容量限制。旧存档首次使用时不阻断
  /// （防止已超容量无法继续游戏），但每次添加会弹出提示，直到容量合规。
  static bool strictMode(Player p) {
    final raw = p.flags['storage_v2'];
    if (raw is Map) return raw['strict'] == true;
    return false;
  }

  static void ensureStrictMode(Player p) {
    final m = Map<String, dynamic>.from(
        p.flags['storage_v2'] is Map ? p.flags['storage_v2'] as Map : {});
    m['strict'] = true;
    m['enabled_at'] = DateTime.now().millisecondsSinceEpoch;
    p.flags['storage_v2'] = m;
  }

  // ---------- 可用性检查 ----------
  /// 是否有储物蛊装备（用于 UI 提示）。
  static bool hasStorageGu(Player p) => storageBonus(p) > 0;

  /// 能否添加 N 条新堆叠（不考虑已同名合并的情况，保守估计）。
  /// 同名合并不会消耗额外容量，因此仅当无同名材料且容量不足时返回 false。
  static (bool, String) canAdd(Player p, String materialName, int count) {
    if (count <= 0) return (true, '');
    // 先看是否已有同名材料，已有则不新增堆叠，无容量限制
    for (final it in p.inventory) {
      final (n, _) = MatParser.parse(it);
      if (n == materialName) return (true, '');
    }
    if (!strictMode(p)) return (true, ''); // 旧存档宽容
    final free = freeCapacity(p);
    if (free >= 1) return (true, '');
    return (false, '背包容量不足！添加 $materialName 需至少 1 格剩余容量。'
        '当前 ${usedCapacity(p)}/${capacityMax(p)}。需装备储物蛊或整理物资。');
  }

  // ---------- 状态描述（UI）----------
  /// 容量描述行："50/210（随身10 + 储物蛊200）"。
  static String describe(Player p) {
    return '${usedCapacity(p)}/${capacityMax(p)}'
        '（随身$carryBase${storageBonus(p) > 0 ? ' + 储物蛊${storageBonus(p)}' : ''}）';
  }

  /// 单只蛊提供的储物容量（便捷包装：同 storageGuCapacity）。
  static int storageCapOf(GuInstance g) => storageGuCapacity(g);
}
