// food_model.dart
// 第二阶段新增：食物气血滋养机制（增量文件，不动旧代码）。
// 设计原则：
//   - 100% 兼容旧存档：进食状态写入 player.flags['food_v2']，旧存档无键回退
//   - 不修改 Player 模型字段，仅通过 flags 存储饱食度等状态
//   - 食物效果：进食恢复气血真元、辅助伤势恢复、辅助毒素代谢
//   - 饥饿惩罚：长期不进食（每12世界小时检查）体魄衰减、真元恢复降低
//
// 食物来源：material.json 中带 effect.type='food' 的材料均可进食。
import 'dart:math' show max, min;
import 'player_model.dart';
import 'recipe_model.dart' show MatParser;

/// 单次进食的效果：heal_phy 体魄恢复、heal_zhen 真元恢复、
/// satiety 饱食小时（默认 12h）、heal_injure 辅助伤势（有概率移除 轻伤等）、
/// detox_power 辅助解毒（对 minor 有效）。
class FoodEffect {
  final int healPhy;
  final int healZhen;
  final double satiety;
  final double healInjureChance; // 0~1，每次进食有概率移除 1 个轻伤/内伤
  final int detoxPower; // 仅解 minor
  const FoodEffect({
    this.healPhy = 0,
    this.healZhen = 0,
    this.satiety = 12,
    this.healInjureChance = 0,
    this.detoxPower = 0,
  });

  /// 简要描述（用于 UI 展示）。
  String desc() {
    final parts = <String>[];
    if (healPhy > 0) parts.add('体魄+$healPhy');
    if (healZhen > 0) parts.add('真元+$healZhen');
    parts.add('饱食${satiety.toStringAsFixed(0)}h');
    if (healInjureChance > 0) parts.add('伤势缓愈${(healInjureChance * 100).toInt()}%');
    if (detoxPower > 0) parts.add('解毒$detoxPower');
    return parts.isEmpty ? '普通食物' : parts.join(' / ');
  }
}

/// 食物机制工具类。
class FoodSystem {
  // ---------- 饱食度 ----------
  /// 饱食度还剩多少小时（>0 表示处于饱食状态）。
  static double satietyHoursLeft(Player p) {
    final raw = p.flags['food_v2'];
    if (raw is Map) {
      final last = (raw['last_eat_hour'] as num?)?.toDouble() ?? -9999;
      final sat = (raw['satiety'] as num?)?.toDouble() ?? 0;
      final remain = sat - (p.worldTime - last);
      return remain.clamp(0.0, 99999.0);
    }
    return 0.0;
  }

  static bool isSatiated(Player p) => satietyHoursLeft(p) > 0;

  static bool isHungry(Player p) {
    final raw = p.flags['food_v2'];
    if (raw is! Map) return false; // 旧存档未启用不判饿
    return satietyHoursLeft(p) <= 0 && (raw['last_eat_hour'] != null);
  }

  /// 旧存档（无 food_v2 键）视为未启用严格模式。
  static bool strictMode(Player p) =>
      p.flags['food_v2'] is Map;

  /// 首次调用进入严格模式（饱食开始计时）。
  static void ensureStrictMode(Player p) {
    if (strictMode(p)) return;
    final m = Map<String, dynamic>.from(
        p.flags['food_v2'] is Map ? p.flags['food_v2'] as Map : {});
    // 初始化：未进食状态，但未触发饿（last_eat_hour 空）
    p.flags['food_v2'] = m;
  }

  static void _setSatiety(Player p, double hours) {
    final m = Map<String, dynamic>.from(
        p.flags['food_v2'] is Map ? p.flags['food_v2'] as Map : {});
    m['last_eat_hour'] = p.worldTime;
    m['satiety'] = hours;
    p.flags['food_v2'] = m;
  }

  // ---------- 饥饿惩罚（由 world_timer 每 12h 调用）----------
  /// 推进饥饿结算：饱食度空时每 12h 扣 5 体魄，真元恢复倍率降低。
  /// 返回日志行。
  static List<String> tickHunger(Player p, double hours) {
    final logs = <String>[];
    final raw = p.flags['food_v2'];
    if (raw is! Map || raw['last_eat_hour'] == null) return logs; // 未启用跳过

    final lastHungerTick = (raw['last_hunger_tick'] as num?)?.toDouble() ?? raw['last_eat_hour']!;
    final elapsed = p.worldTime - lastHungerTick;
    if (!isHungry(p) || elapsed < 12) return logs;

    // 饥饿结算
    final dmgPhy = 5;
    p.physique = max(1, p.physique - dmgPhy);
    final m = Map<String, dynamic>.from(raw);
    m['last_hunger_tick'] = p.worldTime;
    p.flags['food_v2'] = m;
    logs.add('【饥饿】你已许久未进食，饥肠辘辘，体魄 -$dmgPhy。');
    if (p.luck > 0 && p.physique < 20) {
      p.luck = max(0, p.luck - 1);
      logs.add('  饥饿使你气运受损，气运 -1。');
    }
    return logs;
  }

  /// 真元恢复倍率：饥饿时 0.5，饱食时 1.2。
  static double zhenRecoverMul(Player p) {
    if (isHungry(p)) return 0.5;
    if (isSatiated(p)) return 1.2;
    return 1.0;
  }

  // ---------- 进食 ----------
  /// 从材料的 `effect` 字段（Map<String, dynamic>）解析食物效果。
  /// 解析失败返回 null 表示非食物（不识别为食物）。
  static FoodEffect? parseFoodEffect(Map<String, dynamic>? effect) {
    if (effect == null) return null;
    if (effect['type'] != 'food') return null;
    return FoodEffect(
      healPhy: ((effect['heal_phy'] as num?) ?? 0).toInt(),
      healZhen: ((effect['heal_zhen'] as num?) ?? 0).toInt(),
      satiety: ((effect['satiety'] as num?) ?? 12).toDouble(),
      healInjureChance: ((effect['heal_injure_chance'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      detoxPower: ((effect['detox_power'] as num?) ?? 0).toInt(),
    );
  }

  /// 执行进食：返回日志行。由 command.dart 的 eat 指令调用。
  /// [detoxMinorByFoodOnly] 可选回调：仅清除轻微毒。为 null 时不解毒。
  static List<String> consume(Player p, String name, int materialCount,
      FoodEffect fe, { List<String> Function(int power)? detoxMinorByFoodOnly}) {
    final logs = <String>[];
    if (materialCount <= 0) {
      logs.add('没有 $name 可进食。');
      return logs;
    }
    // 恢复
    if (fe.healPhy > 0) {
      p.physique = min(p.physique + fe.healPhy, 200 + (p.physique ~/ 50) * 50);
      logs.add('你进食 $name，气血滋养，体魄 +${fe.healPhy}。');
    } else {
      logs.add('你进食 $name，胃中暖意上涌。');
    }
    if (fe.healZhen > 0) {
      p.recoverTrueyuan(fe.healZhen);
      logs.add('  真元回盈，真元 +${fe.healZhen}。');
    }
    // 饱食度
    _setSatiety(p, fe.satiety);
    // 伤势辅助恢复
    if (fe.healInjureChance > 0) {
      final r = DateTime.now().microsecondsSinceEpoch % 10000 / 10000;
      if (r < fe.healInjureChance) {
        for (final inj in ['轻伤', '内伤']) {
          if (p.injure.contains(inj)) {
            p.healInjure(inj);
            logs.add('  食物温补，伤势 $inj 略有好转。');
            break;
          }
        }
      }
    }
    // 辅助解毒（仅对 minor 有效）
    if (fe.detoxPower > 0 && detoxMinorByFoodOnly != null) {
      final removed = detoxMinorByFoodOnly(fe.detoxPower);
      if (removed.isNotEmpty) {
        logs.add('  食物药力化解了 ${removed.join('、')}（轻微毒素）。');
      }
    }
    return logs;
  }
}
