// reputation_model.dart
// 第二阶段新增：势力声望系统（增量文件，不动旧代码）。
// 设计原则：
//   - 100% 兼容旧存档：声望写入 player.flags['reputation_v2']，旧存档无键回退中立
//   - 三大势力：青茅山宗族、黑崖寨、南疆散修；独立声望值：-100 ~ +100
//   - 声望影响：
//       >=80 崇敬：交易 7 折、专属资源解锁、地图准入（山寨核心/宗族秘境）
//       >=30 友好：交易 9 折、可接悬赏
//       >=-30 中立：正常交易、无准入限制
//       >=-70 冷淡：交易 1.3 倍、部分 NPC 拒绝对话
//       < -70 敌对：见面触发伏击、禁止进入势力领地
//
// 声望变更途径：完成势力悬赏、击杀敌对 NPC、赠送礼物、随机事件选择。
import 'dart:math' show max, min;
import 'player_model.dart';

class Faction {
  static const qingmao = 'qingmao';   // 青茅山宗族
  static const heiya  = 'heiya';      // 黑崖寨
  static const sanxiu = 'sanxiu';    // 南疆散修

  static const names = <String, String>{
    qingmao: '青茅山宗族',
    heiya:  '黑崖寨',
    sanxiu: '南疆散修',
  };

  static const all = [qingmao, heiya, sanxiu];
}

/// 声望等级划分。
String reputationLabel(int v) {
  if (v >= 80)  return '崇敬';
  if (v >= 30)  return '友好';
  if (v >= -30) return '中立';
  if (v >= -70) return '冷淡';
  return '敌对';
}

/// 交易价格倍率：崇敬 0.7，友好 0.9，中立 1.0，冷淡 1.3，敌对 2.0（不卖）。
double reputationPriceMul(int v) {
  if (v >= 80)  return 0.7;
  if (v >= 30)  return 0.9;
  if (v >= -30) return 1.0;
  if (v >= -70) return 1.3;
  return 2.0;
}

/// 声望工具类。
class Reputation {
  static Map<String, int> _raw(Player p) {
    final raw = p.flags['reputation_v2'];
    if (raw is Map) {
      return Map<String, int>.from(raw.map((k, v) =>
          MapEntry(k.toString(), (v as num).toInt().clamp(-100, 100))));
    }
    return {for (final k in Faction.all) k: 0};
  }

  static void _save(Player p, Map<String, int> m) {
    p.flags['reputation_v2'] = Map<String, dynamic>.from(m);
  }

  static int of(Player p, String faction) =>
      _raw(p)[faction] ?? 0;

  static Map<String, int> all(Player p) => _raw(p);

  static void add(Player p, String faction, int delta) {
    final m = _raw(p);
    m[faction] = ((m[faction] ?? 0) + delta).clamp(-100, 100);
    _save(p, m);
  }

  /// 能否进入某势力场景（领地）：敌对 (< -70) 禁止。
  static bool canEnter(Player p, String faction) => of(p, faction) > -70;

  /// 是否敌对（见面即攻）。
  static bool isHostile(Player p, String faction) => of(p, faction) < -70;

  /// 交易折扣：传入势力对应声望值。
  static double priceMul(Player p, String faction) =>
      reputationPriceMul(of(p, faction));

  /// 描述行（UI）。
  static String describe(Player p) {
    final r = _raw(p);
    return r.entries.map((e) =>
        '${Faction.names[e.key] ?? e.key}：${reputationLabel(e.value)}(${e.value})'
    ).join('　');
  }

  /// 声望等级（UI）：崇敬/友好/中立/冷淡/敌对。
  static String gradeLabel(int v) => reputationLabel(v);

  /// 是否解锁专属资源：声望 >= 80 解锁。
  static bool canUnlockExclusive(Player p, String faction) =>
      of(p, faction) >= 80;

  /// 总览简览（用于 status）：仅显示非中立。
  static String summary(Player p) {
    final r = _raw(p);
    final parts = <String>[];
    for (final e in r.entries) {
      if (e.value == 0) continue;
      final n = Faction.names[e.key] ?? e.key;
      parts.add('$n ${e.value > 0 ? '+' : ''}${e.value}(${reputationLabel(e.value)})');
    }
    return parts.join(' / ');
  }
}
