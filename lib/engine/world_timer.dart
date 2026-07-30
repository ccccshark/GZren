// world_timer.dart
// 全局世界计时器：世界时间持续流逝，寿元随时间减少。
import 'dart:math' show max;
import 'package:gzren/data_model/player_model.dart';
import 'player_core.dart' show levelRank, daoConflictDamage;

const double hoursPerYear = 1440.0;

const Map<String, double> actionHours = {
  'move': 2,
  'rest': 12,
  'gather': 6,
  'combat_round': 1,
  'combat_end': 4,
  'refine': 8,
  'capture': 3,
  'use_gu': 1,
  'talk': 1,
  'trade': 1,
};

class WorldTimer {
  int lastTribulationRank = 0;

  /// 推进世界时间。返回触发的特殊事件列表，如 ['tribulation']。
  /// [out] 用于输出寿元/道伤等日志行。
  List<String> advance(Player p, double hours, List<String> log, {double accel = 1.0}) {
    if (!p.alive) return [];
    final events = <String>[];
    p.worldTime += hours;

    // 自然寿元流逝
    double years = (hours / hoursPerYear) * accel;
    if (p.injure.contains('魂伤')) years *= 1.5;
    if (p.injure.contains('空窍损伤')) years *= 1.3;
    if (years > 0) {
      p.lifeLeft -= years;
      if (p.lifeLeft <= 0) {
        p.lifeLeft = 0;
        p.alive = false;
        log.add('【寿元耗尽】你的寿元已尽，大限将至，魂归天地……');
        return events;
      }
    }

    // 道痕冲突持续道伤（每旬结算）
    final daoDmg = daoConflictDamage(p);
    if (daoDmg > 0 && p.worldTime.floor() % 240 < hours) {
      p.soulPower = max(1, p.soulPower - daoDmg).toInt();
      log.add('道痕冲突反噬，魂力 -${daoDmg.toStringAsFixed(1)}（同修冲突大道必有道伤）。');
    }

    // 耐久自然损耗
    if (p.worldTime.floor() % 24 < hours) {
      for (final g in p.guInSlot) {
        if (g.gid != 'g015' && g.durability > 0) {
          g.durability = max(0, g.durability - 1);
        }
      }
    }

    // 天劫检测
    if (_checkTribulation(p)) events.add('tribulation');
    return events;
  }

  bool _checkTribulation(Player p) {
    final rank = levelRank(p.level);
    final threshold = 100 + rank * 60;
    if (p.tribulation >= threshold) {
      p.tribulation = 0;
      lastTribulationRank = rank;
      return true;
    }
    return false;
  }

  void reduceTribulation(Player p, double amount) {
    p.tribulation = max(0.0, p.tribulation - amount);
  }
}
