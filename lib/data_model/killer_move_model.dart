// killer_move_model.dart
// 第二阶段新增：杀招构筑系统（增量文件，不动旧代码）。
// 设计原则：
//   - 100% 兼容旧存档：杀招储存于 player.flags['killer_moves_v2']，旧存档无键回退空列表
//   - 不修改 Player / GuInstance 模型，仅通过 flags 与空窍蛊联动
//   - 杀招构成：2~4 只蛊（来自空窍中）组合 + 命名 + 自定义释放
//   - 联动加成：同流派 ≥2 只 → 威力 +20%；道痕匹配 → 额外倍率
//   - 反噬风险：流派冲突（气道vs血道、月道vs毒道、寿道vs岁月道、地道vs星道）→ 反噬概率
//   - 储存多套：最多 6 套自定义杀招
import 'dart:math' show max, min, Random;
import 'player_model.dart';
import 'gu_model.dart';
import '../engine/player_core.dart' show conflictDaos;

final _rng = Random();

/// 单套杀招。
class KillerMove {
  final String kid;       // 唯一 ID（随机 hex）
  final String name;      // 玩家自定义名
  final List<String> guInstIds; // 组合蛊虫 instId 列表（来自 guInSlot）
  final int createdAt;

  KillerMove({
    required this.kid,
    required this.name,
    required this.guInstIds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'kid': kid, 'name': name,
    'gu_inst_ids': guInstIds,
    'created_at': createdAt,
  };

  factory KillerMove.fromJson(Map<String, dynamic> j) => KillerMove(
    kid: j['kid'] ?? '',
    name: j['name'] ?? '无名杀招',
    guInstIds: List<String>.from(j['gu_inst_ids'] ?? []),
    createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
  );

  /// 杀招描述。
  String brief(Player p) {
    final names = guInstIds.map((id) {
      for (final g in p.guInSlot) {
        if (g.instId == id) return g.name;
      }
      return '?';
    }).join('+');
    final combo = _comboBonus(p);
    final back = _backlashRisk(p);
    return '$name（$names）联动+${(combo*100).round()}% 反噬${(back*100).round()}%';
  }

  /// 蛊虫名称列表（用于 UI 展示）。
  List<String> guNames(Player p) {
    final out = <String>[];
    for (final id in guInstIds) {
      bool found = false;
      for (final g in [...p.guInSlot, ...p.guBag]) {
        if (g.instId == id) { out.add(g.name); found = true; break; }
      }
      if (!found) out.add('?$id');
    }
    return out;
  }

  /// 流派简述。
  String schoolsBrief() => '杀招';

  // ---------- 加成/反噬计算 ----------
  List<GuInstance> _gus(Player p) {
    final out = <GuInstance>[];
    for (final id in guInstIds) {
      for (final g in p.guInSlot) {
        if (g.instId == id) { out.add(g); break; }
      }
    }
    return out;
  }

  /// 联动加成倍率：1.0 基础，≥2 同流派 +0.2，每只同流派道痕 +0.01 每道痕。
  double _comboBonus(Player p) {
    final gus = _gus(p);
    if (gus.length < 2) return 1.0;
    // 流派计数
    final schoolCnt = <String, int>{};
    for (final g in gus) {
      schoolCnt[g.school] = (schoolCnt[g.school] ?? 0) + 1;
    }
    double bonus = 1.0;
    final topCnt = schoolCnt.values.isEmpty ? 0 : schoolCnt.values.reduce(max);
    if (topCnt >= 2) bonus += 0.2;
    // 道痕加成
    for (final s in schoolCnt.keys) {
      if (schoolCnt[s]! >= 2) {
        final d = p.daoMark[s] ?? 0;
        bonus += d * 0.01;
      }
    }
    return bonus.clamp(1.0, 3.0);
  }

  /// 反噬风险概率：0~1，基于冲突大道对数。
  double _backlashRisk(Player p) {
    final gus = _gus(p);
    double r = 0;
    for (final (a, b) in conflictDaos) {
      bool ha = gus.any((g) => g.school == a);
      bool hb = gus.any((g) => g.school == b);
      if (ha && hb) r += 0.2;
    }
    return r.clamp(0.0, 0.8);
  }

  /// 释放杀招：返回 (总威力, 日志列表, 反噬触发?)。
  /// 由战斗/非战斗调用端决定如何应用威力。
  (int, List<String>, bool) cast(Player p) {
    final logs = <String>[];
    final gus = _gus(p);
    if (gus.isEmpty) return (0, ['杀招 $name 组合蛊虫不在空窍中，无法释放。'], false);
    // 耐久 & 真元检查
    for (final g in gus) {
      if (g.durability <= 0) {
        logs.add('${g.name} 耐久耗尽，杀招无法成形。');
        return (0, logs, false);
      }
      if (p.trueyuan < g.costZhen) {
        logs.add('真元不足以催动 ${g.name}，杀招失败。');
        return (0, logs, false);
      }
    }
    // 消耗真元 & 耐久
    int totalZhen = 0;
    int rawPower = 0;
    for (final g in gus) {
      totalZhen += g.costZhen;
      g.durability = max(0, g.durability - 3);
      final pow = (g.combat['power'] as num? ?? 0).toInt();
      rawPower += pow;
      p.addDaoMark(g.school, 0.3);
    }
    p.spendTrueyuan(totalZhen);
    // 加成
    final combo = _comboBonus(p);
    int totalPower = (rawPower * combo).toInt();
    logs.add('你绽放杀招【$name】！${gus.map((g)=>g.name).join("、")}齐动');
    if (combo > 1.0) logs.add('  联动加成 ×${combo.toStringAsFixed(2)}，总威力 $totalPower。');
    // 反噬
    final back = _backlashRisk(p);
    final r = _rng.nextDouble();
    if (r < back) {
      final dmg = (totalPower * 0.25).toInt().clamp(3, 999);
      p.physique = max(1, p.physique - dmg);
      logs.add('  【反噬】道痕冲突，杀招失控反噬自身，体魄 -$dmg！');
      return (totalPower, logs, true);
    }
    return (totalPower, logs, false);
  }
}

/// 杀招储存工具。
class KillerMoveStore {
  static const int maxSlots = 6;

  static List<KillerMove> list(Player p) {
    final raw = p.flags['killer_moves_v2'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => KillerMove.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  static void save(Player p, List<KillerMove> moves) {
    p.flags['killer_moves_v2'] = moves.take(maxSlots).map((m) => m.toJson()).toList();
  }

  /// 新增杀招。超过 maxSlots 返回 false。
  /// [guKeys] 可以是蛊名（含空格）或 instId，自动从空窍 + 背包中查找。
  static bool add(Player p, String name, List<String> guKeys) {
    final cur = list(p);
    if (cur.length >= maxSlots) return false;
    if (guKeys.length < 2 || guKeys.length > 4) return false;
    // 将 guKeys (名称或instId) 解析为 instId 列表
    final ids = <String>[];
    final all = [...p.guInSlot, ...p.guBag];
    for (final k in guKeys) {
      final key = k.trim();
      if (key.isEmpty) continue;
      // 先按 instId 精确匹配
      GuInstance? hit;
      for (final g in all) {
        if (g.instId == key) { hit = g; break; }
      }
      // 再按 name 匹配
      hit ??= all.cast<GuInstance?>().firstWhere(
          (g) => g?.name == key || (g?.name ?? '').contains(key),
          orElse: () => null);
      if (hit == null) return false; // 未找到，整体失败
      ids.add(hit.instId);
    }
    if (ids.length < 2) return false;
    cur.add(KillerMove(
      kid: _rng.nextInt(0xffffff).toRadixString(16),
      name: name,
      guInstIds: ids,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    save(p, cur);
    return true;
  }

  /// 删除杀招：支持 kid / name / 索引（字符串化的数字）。
  static bool remove(Player p, String key) {
    final cur = list(p);
    final idx = int.tryParse(key);
    int target = -1;
    if (idx != null && idx >= 0 && idx < cur.length) {
      target = idx;
    } else {
      for (int i = 0; i < cur.length; i++) {
        if (cur[i].kid == key || cur[i].name == key) { target = i; break; }
      }
    }
    if (target < 0) return false;
    cur.removeAt(target);
    save(p, cur);
    return true;
  }

  /// 按 kid/name/索引 查找。
  static KillerMove? find(Player p, String key) {
    final all = list(p);
    final idx = int.tryParse(key);
    if (idx != null && idx >= 0 && idx < all.length) return all[idx];
    for (final m in all) {
      if (m.kid == key || m.name == key) return m;
    }
    return null;
  }
}

// ===========================================================================
// V1.9 专项新增【仙道杀招·原著预设系统】
// ---------------------------------------------------------------------------
// 设计目标：在保留原有"玩家自定义组合杀招"（KillerMove/KillerMoveStore）
//   的基础上，新增"原著预设仙道杀招"（PresetKillerMove/PresetKillerMoveStore）
//   一套独立机制，两者共存互不冲突。
// 核心规则（严格遵循原著）：
//   ① 启动读取 kill_move.json 的 preset_killer_moves 数组；
//   ② 检测玩家背包+空窍蛊虫，集齐全套 required_gu 自动解锁；
//   ③ 缺任意一只蛊 → 杀招锁定，无法释放；
//   ④ 释放校验：真元足够、冷却已过；触发后扣真元+进冷却+原著反噬副作用；
//   ⑤ 不改动 combat.dart 战斗结算底层，副作用在 cast() 内直接作用于 player。
// 持久化：解锁状态与冷却时间戳存于 player.flags['preset_km_state']，
//   旧存档无键 → 视为未解锁/无冷却，100% 兼容。
// ===========================================================================

/// 原著预设仙道杀招（静态配置，从 kill_move.json 加载）。
class PresetKillerMove {
  final String moveId;          // 唯一ID
  final String name;            // 杀招名
  final String source;          // 原著参考
  final List<String> requiredGu; // 必备蛊虫 gid 清单（缺一不可）
  final int costZhen;           // 瞬时真元消耗
  final int sustainZhen;        // 持续维持消耗（每回合，0=无）
  final int cooldown;           // 冷却时间（游戏分钟）
  final String effect;          // 战斗效果描述
  final String backlash;        // 副作用反噬描述（空串=无）
  final int backlashDmg;        // 反噬体魄伤害（0=无）
  final String scope;           // 作用范围

  PresetKillerMove({
    required this.moveId,
    required this.name,
    required this.source,
    required this.requiredGu,
    required this.costZhen,
    required this.sustainZhen,
    required this.cooldown,
    required this.effect,
    required this.backlash,
    required this.backlashDmg,
    required this.scope,
  });

  factory PresetKillerMove.fromJson(Map<String, dynamic> j) => PresetKillerMove(
    moveId: j['move_id'] ?? '',
    name: j['name'] ?? '无名杀招',
    // V1.9 专项：适配用户新字段名 source_chapter，兼容旧字段 source
    source: j['source_chapter'] ?? j['source'] ?? '',
    requiredGu: List<String>.from(j['required_gu'] ?? []),
    // V1.9 专项：适配新字段名 instant_yuan_cost / hold_yuan_cost，兼容旧 cost_zhen / sustain_zhen
    costZhen: (j['instant_yuan_cost'] as num?)?.toInt() ??
        (j['cost_zhen'] as num?)?.toInt() ?? 0,
    sustainZhen: (j['hold_yuan_cost'] as num?)?.toInt() ??
        (j['sustain_zhen'] as num?)?.toInt() ?? 0,
    cooldown: (j['cooldown'] as num?)?.toInt() ?? 0,
    effect: j['effect'] ?? '',
    backlash: j['backlash'] ?? '',
    // backlash_dmg 保留读取（旧格式兼容）；新格式无此字段时为 0，由 cast() 自动计算
    backlashDmg: (j['backlash_dmg'] as num?)?.toInt() ?? 0,
    // V1.9 专项：适配新字段名 range，兼容旧字段 scope
    scope: j['range'] ?? j['scope'] ?? '',
  );
}

/// 原著预设杀招运行时存储（静态配置 + 玩家解锁/冷却状态）。
class PresetKillerMoveStore {
  /// 静态配置表（启动时从 kill_move.json 加载，全局共享）。
  static List<PresetKillerMove> _presets = const [];
  static List<PresetKillerMove> get presets => _presets;

  /// 启动加载（由 command.loadStatic 调用）。
  static void load(List<dynamic> raw) {
    _presets = raw
        .whereType<Map>()
        .map((m) => PresetKillerMove.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// 玩家解锁/冷却状态：{ moveId: { unlocked: 0/1, last_cast: 游戏分钟 } }
  static Map<String, Map<String, dynamic>> _state(Player p) {
    final raw = p.flags['preset_km_state'];
    if (raw is! Map) return {};
    final out = <String, Map<String, dynamic>>{};
    for (final e in raw.entries) {
      if (e.value is Map) {
        out[e.key.toString()] = Map<String, dynamic>.from(e.value as Map);
      }
    }
    return out;
  }

  static void _save(Player p, Map<String, Map<String, dynamic>> state) {
    p.flags['preset_km_state'] = state;
  }

  /// 判定玩家是否集齐某杀招全部必备蛊虫（空窍 + 背包）。
  static bool hasAllGu(Player p, PresetKillerMove m) {
    final all = [...p.guInSlot, ...p.guBag];
    for (final gid in m.requiredGu) {
      if (!all.any((g) => g.gid == gid)) return false;
    }
    return true;
  }

  /// 是否已解锁（集齐全套蛊虫即自动解锁，状态持久化）。
  static bool isUnlocked(Player p, PresetKillerMove m) {
    final st = _state(p);
    return (st[m.moveId]?['unlocked'] as num?)?.toInt() == 1;
  }

  /// 刷新解锁状态：集齐则解锁，返回本次新解锁的杀招名（用于播报）。
  static String? refreshUnlock(Player p) {
    for (final m in _presets) {
      if (!isUnlocked(p, m) && hasAllGu(p, m)) {
        final st = _state(p);
        st[m.moveId] = {'unlocked': 1, 'last_cast': 0};
        _save(p, st);
        return m.name;
      }
    }
    return null;
  }

  /// 当前是否处于冷却中。
  static bool isCoolingDown(Player p, PresetKillerMove m) {
    final st = _state(p);
    final last = (st[m.moveId]?['last_cast'] as num?)?.toInt() ?? 0;
    if (last <= 0 || m.cooldown <= 0) return false;
    final nowMin = (p.worldTime * 60).toInt();
    return (nowMin - last) < m.cooldown;
  }

  /// 剩余冷却分钟数。
  static int cooldownLeft(Player p, PresetKillerMove m) {
    final st = _state(p);
    final last = (st[m.moveId]?['last_cast'] as num?)?.toInt() ?? 0;
    if (last <= 0 || m.cooldown <= 0) return 0;
    final nowMin = (p.worldTime * 60).toInt();
    final left = m.cooldown - (nowMin - last);
    return left > 0 ? left : 0;
  }

  /// 释放预设杀招：返回 (威力, 日志, 是否反噬)。
  /// 校验顺序：解锁 → 蛊虫在身 → 冷却 → 真元 → 扣耗 → 反噬。
  static (int, List<String>, bool) cast(Player p, PresetKillerMove m) {
    final logs = <String>[];
    // 1. 解锁校验
    if (!isUnlocked(p, m)) {
      if (!hasAllGu(p, m)) {
        logs.add('【${m.name}】缺少配套蛊虫，无法催动。');
        logs.add('  所需：${m.requiredGu.join("、")}（集齐方可解锁）');
      } else {
        logs.add('【${m.name}】尚未解锁。');
      }
      return (0, logs, false);
    }
    // 2. 蛊虫在身校验（解锁后蛊虫可能被丢弃/喂食，需复核）
    if (!hasAllGu(p, m)) {
      logs.add('【${m.name}】配套蛊虫不在身上（空窍或背包），无法催动。');
      return (0, logs, false);
    }
    // 3. 冷却校验
    if (isCoolingDown(p, m)) {
      final left = cooldownLeft(p, m);
      logs.add('【${m.name}】冷却中，剩余 $left 分钟（游戏时间）。');
      return (0, logs, false);
    }
    // 4. 真元校验
    if (p.trueyuan < m.costZhen) {
      logs.add('真元不足（需 ${m.costZhen}，当前 ${p.trueyuan}），【${m.name}】无法催动。');
      return (0, logs, false);
    }
    // 5. 扣耗真元 + 进冷却
    p.spendTrueyuan(m.costZhen);
    final st = _state(p);
    st[m.moveId] = {
      'unlocked': 1,
      'last_cast': (p.worldTime * 60).toInt(),
    };
    _save(p, st);
    // 6. 威力计算：基于必备蛊虫 combat.power 之和
    final all = [...p.guInSlot, ...p.guBag];
    int rawPower = 0;
    for (final gid in m.requiredGu) {
      final g = all.firstWhere((x) => x.gid == gid, orElse: () => all.first);
      rawPower += (g.combat['power'] as num? ?? 0).toInt();
      g.durability = max(0, g.durability - 3);
    }
    // 预设杀招基础倍率 1.5（多蛊联动加成）
    final totalPower = (rawPower * 1.5).toInt();
    logs.add('你绽放仙道杀招【${m.name}】！${m.effect}');
    logs.add('  消耗真元 ${m.costZhen}，造成 $totalPower 点综合伤害。');
    if (m.sustainZhen > 0) {
      logs.add('  持续维持每回合消耗真元 ${m.sustainZhen}。');
    }
    // 7. 原著反噬副作用
    // V1.9 专项：backlash 非空但 backlashDmg==0 时（新格式无 backlash_dmg 字段），
    //   按瞬时真元消耗的 50% 自动计算反噬体魄伤害，确保反噬机制生效。
    bool back = false;
    if (m.backlashDmg > 0 || m.backlash.isNotEmpty) {
      back = true;
      final dmg = m.backlashDmg > 0
          ? m.backlashDmg
          : (m.costZhen * 0.5).toInt().clamp(1, 999);
      if (dmg > 0) {
        p.physique = max(1, p.physique - dmg);
        logs.add('  【反噬】${m.backlash} 体魄 -$dmg！');
      } else {
        logs.add('  【反噬】${m.backlash}');
      }
    }
    return (totalPower, logs, back);
  }

  /// 按 moveId/name 查找预设杀招。
  static PresetKillerMove? find(String key) {
    for (final m in _presets) {
      if (m.moveId == key || m.name == key) return m;
    }
    return null;
  }
}
