// phase2_core.dart
// 第二阶段核心系统钩子：把空窍容量/储物蛊/饥饿结算/暗伤结算统一推入 world_timer。
// 全增量，不修改原有 world_timer 字段结构，由 command.dart/world_timer.dart 显式调用。
import 'dart:math' show max, Random;
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/slot_capacity_model.dart' show SlotCapacity;
import 'package:gzren/data_model/food_model.dart' show FoodSystem;
import 'poison_system.dart' show PoisonSystem;

final _rng = Random();

/// 每小时/每日结算：返回日志列表。
/// 在 world_timer.advance 里调用（位于寿元流逝之后，耐久/天劫之前）。
List<String> phase2DailyTick(Player p, double hours) {
  if (!p.alive) return const [];
  final logs = <String>[];

  // ---- 1. 空窍超限结算（每 24h 一次）----
  final dailyKey = 'slot_last_daily_day';
  final curDay = (p.worldTime / 24).floor();
  final lastDay = ((p.flags[dailyKey] as num?) ?? -1).toInt();
  if (curDay > lastDay && SlotCapacity.strictMode(p)) {
    // 第一次进入严格模式日不判，避免旧装备直接爆
    final ratio = SlotCapacity.dailyDarkInjuryChance(p);
    if (ratio > 0 && _rng.nextDouble() < ratio) {
      if (!p.injure.contains('暗伤')) p.addInjure('暗伤');
      logs.add('【空窍过载】蛊虫塞满空窍，经脉受压，滋生暗伤！需拓窍或减负。');
    }
    // 真元恢复惩罚通过 Rest 结算时读取，不扣绝对值
    p.flags[dailyKey] = curDay;
  }
  // 进入严格模式初始化：首次进入新版就标记
  if (!SlotCapacity.strictMode(p)) {
    SlotCapacity.ensureStrictMode(p);
  }

  // ---- 2. 饥饿结算 ----
  final hungerLogs = FoodSystem.tickHunger(p, hours);
  logs.addAll(hungerLogs);
  // 食物系统启用标记（有进食过才判饿）
  if (p.flags['food_v2'] == null) {
    // 给初始角色一个轻微饱食时间（24h），避免刚开局就饿
    final m = <String, dynamic>{
      'last_eat_hour': p.worldTime,
      'satiety': 24.0,
    };
    p.flags['food_v2'] = m;
  }

  // ---- 3. 仅疗伤不解毒会反复恶化（原毒素系统已在 tick 结算，此处加：有伤+有毒时伤更重）----
  final hasPoison = (p.flags['poisons'] is List) &&
      (p.flags['poisons'] as List).isNotEmpty;
  final hasInj = p.injure.any((x) => x == '内伤' || x == '毒伤' || x == '暗伤');
  if (hasPoison && hasInj && _rng.nextDouble() < 0.02 * hours) {
    p.physique = max(1, p.physique - 2);
    logs.add('【伤势反复】体内毒素使伤势反复恶化，体魄 -2。（提示：先解毒再疗伤）');
  }

  return logs;
}

/// Rest 真元恢复倍率整合：空窍超限 + 饱食状态 → 综合倍率。
double restRecoverMultiplier(Player p) {
  final s1 = SlotCapacity.trueyuanRecoverMultiplier(p);
  final s2 = FoodSystem.zhenRecoverMul(p);
  return s1 * s2;
}

/// Rest 辅助解毒（给 minor 多一条解毒路径）：当饱食时额外代谢轻微毒素。
List<String> restFoodDetox(Player p, double hours) {
  final logs = <String>[];
  if (!FoodSystem.isSatiated(p)) return logs;
  // 饱食 → 轻微毒素辅助代谢
  final removed = PoisonSystem.detoxMinorByFoodOnly(p, (hours * 0.3).toInt().clamp(1, 5));
  for (final n in removed) {
    logs.add('  食物温补之力化解了 $n（轻微毒素）。');
  }
  return logs;
}
