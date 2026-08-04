// combat.dart
// 回合制战斗核心 + 天劫渡劫。玩家 VS NPC/异兽，绝无玩家对战。
// 采用状态机模型，由战斗 UI 逐步驱动。
import 'dart:math';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/gu_model.dart';
import 'package:gzren/data_model/npc_model.dart';
import 'gu_system.dart' show makeGuInstance;
import 'player_core.dart' show levelRank;
import 'poison_system.dart' show PoisonSystem;
import '../data_model/poison_model.dart' show PoisonRank;
import '../data_model/killer_move_model.dart' show KillerMoveStore; // V1.3：战斗内杀招一键释放

class CombatEngine {
  final Map<String, GuTemplate> guList;
  CombatEngine(this.guList);

  // ---------- 普通战斗 ----------
  CombatResult startCombat(Player p, Npc npc, Map<String, double> env) {
    npc.combatGus = npc.guInSlot.map((gid) => makeGuInstance(gid, guList)).toList();
    return CombatResult(
      player: p,
      npc: npc,
      env: env,
      round: 0,
      status: CombatStatus.ongoing,
      npcHpMax: npc.physique,
      playerPoison: 0,
      npcPoison: 0,
      log: ['═══ 战斗开始！${p.name} VS ${npc.name}（${npc.level}） ═══'],
    );
  }

  CombatResult playerAction(CombatResult s, String action, [String? guName]) {
    if (s.status != CombatStatus.ongoing) return s;
    final p = s.player;
    final npc = s.npc;
    s.round += 1;
    s.addLog('\n—— 第 ${s.round} 回合 ——');
    s.addLog('你：体魄 ${p.physique} | 真元 ${p.trueyuan}    敌：${npc.name} 体魄 ${npc.physique}');

    bool defending = false;
    final act = action.toLowerCase();

    if (act == 'defend' || act == '防御') {
      defending = true;
      s.addLog('你全力催动防御蛊护体。');
    } else if (act == 'flee' || act == '逃亡') {
      if (_tryFlee(p, npc)) {
        s.addLog('你成功逃离战斗！');
        s.status = CombatStatus.flee;
        return s;
      } else {
        s.addLog('逃亡失败！你承受了敌人的追击。');
        _npcAttack(s, freeHit: true);
        if (_checkEnd(s)) return s;
      }
    } else if (act.startsWith('attack') || act.startsWith('use')) {
      var attackGus = _attackGus(p.guInSlot);
      if (guName != null && guName.isNotEmpty) {
        attackGus = attackGus.where((g) => g.name == guName || g.instId == guName).toList();
      }
      if (attackGus.isEmpty) {
        s.addLog('你没有可用的攻击蛊！只能防御或逃亡。');
        defending = true;
      } else {
        final gu = attackGus.first;
        if (gu.durability <= 0) {
          s.addLog('${gu.name} 耐久耗尽，无法催动！');
          defending = true;
        } else if (p.trueyuan < gu.costZhen) {
          s.addLog('真元不足，无法催动 ${gu.name}！');
          defending = true;
        } else {
          p.spendTrueyuan(gu.costZhen);
          gu.durability = max(0, gu.durability - 2);
          final (dmg, isPoison) = _calcAttack(p, p.guInSlot, gu, npc, s.env, true);
          npc.physique = max(0, npc.physique - dmg);
          var msg = '你催动 ${gu.name}，对 ${npc.name} 造成 $dmg 点伤害！';
          if (isPoison) {
            s.npcPoison += 1;
            msg += '（附毒）';
          }
          s.addLog(msg);
          p.addDaoMark(gu.school, 0.5);
        }
      }
    } else if (act.startsWith('killmove') || act.startsWith('杀招')) {
      // V1.3 新增【战斗内杀招一键释放】：整套蛊虫组合释放，同流派协同加成。
      // guName 参数携带杀招名；cast() 消耗真元/耐久并返回综合伤害，此处套用到 NPC。
      final kmName = guName ?? '';
      final km = KillerMoveStore.find(p, kmName);
      if (km == null) {
        s.addLog('未找到杀招「$kmName」，无法释放。');
        defending = true;
      } else {
        final (kmDmg, kmLogs, backlash) = km.cast(p);
        for (final l in kmLogs) {
          s.addLog(l);
        }
        if (kmDmg > 0) {
          // 环境增益套用：场景环境对杀招总威力按主导流派倍率放大
          final schools = <String, int>{};
          for (final id in km.guInstIds) {
            for (final g in p.guInSlot) {
              if (g.instId == id) {
                schools[g.school] = (schools[g.school] ?? 0) + 1;
                break;
              }
            }
          }
          String? mainSchool;
          int mainCnt = 0;
          for (final e in schools.entries) {
            if (e.value > mainCnt) { mainCnt = e.value; mainSchool = e.key; }
          }
          double envMul = 1.0;
          if (mainSchool != null) {
            envMul = s.env[mainSchool] ?? 1.0;
          }
          final finalDmg = (kmDmg * envMul).toInt();
          npc.physique = max(0, npc.physique - finalDmg);
          s.addLog('你对 ${npc.name} 释放杀招【${km.name}】，造成 $finalDmg 点综合伤害！'
              '${envMul > 1.01 ? "（环境加成×${envMul.toStringAsFixed(2)}）" : ""}');
        }
        if (backlash) {
          s.addLog('【反噬】杀招失控，你体魄受损！');
          if (p.physique <= 0) {
            _onLose(s);
            return s;
          }
        }
      }
    } else {
      s.addLog('未知战斗指令，默认防御。');
      defending = true;
    }

    if (npc.physique <= 0) {
      _onWin(s);
      return s;
    }

    // 中毒结算
    if (s.npcPoison > 0) {
      final pdmg = s.npcPoison * 2;
      npc.physique = max(0, npc.physique - pdmg);
      s.addLog('${npc.name} 毒发，掉血 $pdmg。');
    }
    if (s.playerPoison > 0) {
      final pdmg = s.playerPoison * 2;
      p.physique = max(0, p.physique - pdmg);
      s.addLog('你毒发，掉血 $pdmg。');
      if (p.physique <= 0) {
        _onLose(s);
        return s;
      }
    }

    // NPC AI 行动
    if (npc.physique > 0) _npcTurn(s);

    // 替身蛊保命
    if (p.physique <= 0) {
      final sub = _substituteGus(p.guInSlot);
      if (sub.isNotEmpty) {
        final g = sub.first;
        p.guInSlot.remove(g);
        p.guBag.add(g);
        g.durability = 0;
        p.physique = 1;
        s.addLog('【替身】${g.name} 替你挡下致命一击后损毁！你勉强存活。');
      } else {
        _onLose(s);
        return s;
      }
    }

    if (npc.physique <= 0) _onWin(s);
    return s;
  }

  void _npcTurn(CombatResult s) {
    final npc = s.npc;
    final p = s.player;
    final nRank = levelRank(npc.level);
    // V1.4 新增【3~6转NPC战术AI】：
    //  - 低血量（<25%）：高阶NPC优先逃亡；smart型若防御蛊可用则转为防御回血
    //  - smart型NPC：玩家真元见底时全力猛攻；玩家高血量时优先放毒消耗
    final lowHp = npc.physique < s.npcHpMax * 0.25;
    if (lowHp) {
      // 高阶NPC更倾向逃亡（rank>=3 逃亡概率提升）
      final fleeChance = nRank >= 3 ? 0.75 : 0.6;
      if (_fleeGus(npc.combatGus).isNotEmpty && Random().nextDouble() < fleeChance) {
        s.addLog('${npc.name} 催动遁蛊逃走了！');
        npc.physique = 0;
        s.status = CombatStatus.flee;
        return;
      }
      // smart型低血量优先防御回血
      if (npc.aiType == 'smart' && _defenseGus(npc.combatGus).isNotEmpty) {
        final defGu = _defenseGus(npc.combatGus).first;
        if (defGu.durability > 0) {
          defGu.durability = max(0, defGu.durability - 3);
          npc.trueyuan = min(npc.trueyuanMax, npc.trueyuan + 10);
          npc.physique = min(npc.physiqueMax, npc.physique + 8);
          s.addLog('${npc.name} 催动 ${defGu.name} 防御回血，体魄 +8、真元 +10。');
          return;
        }
      }
    }
    final attackGus = _attackGus(npc.combatGus).where((g) => g.durability > 0).toList();
    if (attackGus.isEmpty) {
      s.addLog('${npc.name} 无攻击蛊可用，转为防御。');
      return;
    }
    // V1.4 新增【smart型战术选择】：
    //  - 玩家真元 <20%：优先用最强蛊猛攻（趁虚）
    //  - 玩家体魄 >70% 且 smart型：优先用毒蛊消耗（rank>=3）
    //  - 其他：选最强攻击蛊
    GuInstance gu;
    if (npc.aiType == 'smart' && p.trueyuan < p.trueyuanMax * 0.2) {
      // 趁虚猛攻
      gu = attackGus.reduce((a, b) =>
          (b.combat['power'] as num? ?? 0) > (a.combat['power'] as num? ?? 0) ? b : a);
      s.addLog('${npc.name} 察觉你真元空虚，趁机猛攻！');
    } else if (npc.aiType == 'smart' && p.physique > p.lifeMax * 0.7 && nRank >= 3) {
      // 优先放毒消耗
      final poisonGus = attackGus.where((g) => g.combat['type'] == 'attack_poison').toList();
      gu = poisonGus.isNotEmpty
          ? poisonGus.reduce((a, b) =>
              (b.combat['power'] as num? ?? 0) > (a.combat['power'] as num? ?? 0) ? b : a)
          : attackGus.reduce((a, b) =>
              (b.combat['power'] as num? ?? 0) > (a.combat['power'] as num? ?? 0) ? b : a);
    } else {
      gu = attackGus.reduce((a, b) =>
          (b.combat['power'] as num? ?? 0) > (a.combat['power'] as num? ?? 0) ? b : a);
    }
    gu.durability = max(0, gu.durability - 2);
    final (dmg, isPoison) = _calcAttack(npc, npc.combatGus, gu, p, s.env, false);
    // V1.4 新增：高阶NPC攻击伤害随rank提升（rank>=3 额外+10%/rank）
    var finalDmg = dmg;
    if (nRank >= 3) {
      finalDmg = (dmg * (1 + (nRank - 2) * 0.1)).toInt();
    }
    final defense = (_defenseValue(p) * 0.3).toInt();
    final realDmg = max(1, finalDmg - defense);
    p.physique = max(0, p.physique - realDmg);
    var msg = '${npc.name} 催动 ${gu.name}，对你造成 $realDmg 点伤害！';
    if (isPoison) {
      msg += '（你中毒了！）';
      // 接入【毒素中毒系统】：根据攻击蛊威力注入对应等级毒素。
      // 蛊 rank<=2 → 轻微毒素；rank 3-4 → 烈性毒素；rank>=5 → 奇毒。
      final guRank = gu.rank;
      final pRank = guRank <= 2 ? PoisonRank.minor
          : (guRank <= 4 ? PoisonRank.fierce : PoisonRank.odd);
      final pPower = ((gu.combat['power'] as num? ?? 10).toDouble() * 0.5).toInt().clamp(2, 30);
      PoisonSystem.applyPoison(p,
        pid: 'combat_${npc.nid}_${gu.gid}',
        name: '${gu.name}之毒',
        rank: pRank,
        power: pPower,
        tickHours: 8,
        source: '${npc.name} 战斗命中',
      );
    }
    s.addLog(msg);
  }

  void _npcAttack(CombatResult s, {bool freeHit = false}) {
    final npc = s.npc;
    final p = s.player;
    final attackGus = _attackGus(npc.combatGus);
    if (attackGus.isEmpty) return;
    final gu = attackGus.first;
    final (dmg, _) = _calcAttack(npc, npc.combatGus, gu, p, s.env, false);
    var realDmg = dmg;
    if (freeHit) realDmg = (dmg * 1.3).toInt();
    p.physique = max(0, p.physique - realDmg);
    s.addLog('${npc.name} 追击，对你造成 $realDmg 点伤害！');
  }

  bool _tryFlee(Player p, Npc npc) {
    double base = 0.3 + p.luck * 0.01;
    final fleeGus = _fleeGus(p.guInSlot);
    if (fleeGus.isNotEmpty) {
      base += 0.4;
      fleeGus.first.durability = max(0, fleeGus.first.durability - 5);
    }
    final pRank = levelRank(p.level);
    final nRank = levelRank(npc.level);
    base -= max(0, nRank - pRank) * 0.1;
    return Random().nextDouble() < base.clamp(0.05, 0.9);
  }

  void _onWin(CombatResult s) {
    s.status = CombatStatus.win;
    s.addLog('\n═══ 战斗结束：你击败了 ${s.npc.name}！ ═══');
    s.player.kills += 1;
    s.player.tribulation += 5;
    // 悬赏击杀计数：按击败的 NPC nid 逐只累计（用于 BountyBoard kill 类悬赏）
    final raw = s.player.flags['kill_counts'];
    final m = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final nid = s.npc.nid;
    if (nid.isNotEmpty) {
      m[nid] = ((m[nid] as num?) ?? 0).toInt() + 1;
      s.player.flags['kill_counts'] = m;
    }
    _loot(s);
  }

  void _onLose(CombatResult s) {
    s.status = CombatStatus.lose;
    s.addLog('【你被击败了！】');
  }

  void _loot(CombatResult s) {
    final npc = s.npc;
    final p = s.player;
    s.addLog('\n你搜查 ${npc.name} 的遗物：');
    for (final it in npc.inventory) {
      p.inventory.add(it);
      s.addLog('  获得材料：$it');
    }
    for (final gid in List<String>.from(npc.guInSlot)) {
      if (Random().nextDouble() < 0.5) {
        final inst = makeGuInstance(gid, guList, durability: 40 + Random().nextInt(51));
        p.guBag.add(inst);
        s.addLog('  掠夺蛊虫：${inst.name}（耐久 ${inst.durability}）');
      }
    }
    npc.inventory.clear();
    npc.guInSlot.clear();
  }

  bool _checkEnd(CombatResult s) {
    if (s.player.physique <= 0) {
      final sub = _substituteGus(s.player.guInSlot);
      if (sub.isEmpty) {
        _onLose(s);
        return true;
      }
    }
    return s.status != CombatStatus.ongoing;
  }

  // ---------- 计算 ----------
  (int, bool) _calcAttack(dynamic attacker, List<GuInstance> attackerGus,
      GuInstance gu, dynamic defender, Map<String, double> env, bool isPlayer) {
    double base = (gu.combat['power'] ?? 0).toDouble();
    final school = gu.school;
    final dao = (attacker is Player)
        ? (attacker.daoMark[school] ?? 0)
        : (attacker is Npc ? (attacker.daoMark[school] ?? 0) : 0.0);
    base *= (1 + dao * 0.01);
    if (env.containsKey(school)) base *= env[school]!;
    if (school == '月道') base *= 0.5; // 简化白昼减半
    final phys = (attacker is Player) ? attacker.physique : (attacker as Npc).physique;
    base += phys * 0.1;
    final defense = _defenseValue(defender) * 0.3;
    final dmg = max(1, (base - defense).toInt());
    final isPoison = gu.combat['type'] == 'attack_poison';
    return (dmg, isPoison);
  }

  double _defenseValue(dynamic c) {
    final gus = (c is Player) ? c.guInSlot : (c as Npc).combatGus;
    double val = 0;
    for (final g in gus) {
      if (g.combat['type'] == 'defense') val += (g.combat['power'] ?? 0) * 0.6;
    }
    final phys = (c is Player) ? c.physique : (c as Npc).physique;
    val += phys * 0.2;
    return val;
  }

  List<GuInstance> _attackGus(List<GuInstance> gus) =>
      gus.where((g) => g.combat['type'] == 'attack' || g.combat['type'] == 'attack_poison').toList();
  List<GuInstance> _defenseGus(List<GuInstance> gus) =>
      gus.where((g) => g.combat['type'] == 'defense').toList();
  List<GuInstance> _fleeGus(List<GuInstance> gus) =>
      gus.where((g) => g.combat['type'] == 'flee').toList();
  List<GuInstance> _substituteGus(List<GuInstance> gus) =>
      gus.where((g) => g.combat['type'] == 'substitute').toList();

  // ---------- 天劫渡劫 ----------
  TribulationResult startTribulation(Player p) {
    final rank = levelRank(p.level);
    final rounds = 3 + rank;
    return TribulationResult(
      player: p, rank: rank, totalRounds: rounds, round: 0, survived: true, finished: false,
      log: ['⚡⚡⚡ 【天劫降临】劫数已满，第 $rank 转天劫雷罚降临！需撑过 $rounds 轮雷劫 ⚡⚡⚡'],
    );
  }

  TribulationResult tribulationAction(TribulationResult t, String action) {
    if (t.finished) return t;
    final p = t.player;
    t.round += 1;
    t.addLog('\n—— 天劫第 ${t.round}/${t.totalRounds} 轮 ——');
    final act = action.toLowerCase();
    final defending = act.contains('defend') || act.contains('防御');
    var baseDmg = 15 + t.rank * 8 + (t.round - 1) * 6;
    final defense = _defenseValue(p) * (defending ? 1.2 : 0.4);
    final dmg = max(1, (baseDmg - defense).toInt());
    if (defending) {
      for (final g in _defenseGus(p.guInSlot)) {
        g.durability = max(0, g.durability - 5);
      }
    }
    p.physique = max(0, p.physique - dmg);
    t.addLog('天雷轰顶！造成 $dmg 点伤害，你剩余体魄 ${p.physique}。');
    if (p.physique <= 0) {
      final sub = _substituteGus(p.guInSlot);
      if (sub.isNotEmpty) {
        final g = sub.first;
        p.guInSlot.remove(g);
        p.guBag.add(g);
        g.durability = 0;
        p.physique = 1;
        t.addLog('【替身】${g.name} 替你挡下天雷后损毁！');
      } else {
        t.survived = false;
        t.finished = true;
        t.addLog('\n💀【渡劫失败】天劫之威非你所能抗，魂飞魄散，就此陨落……');
        p.alive = false;
        return t;
      }
    }
    if (t.round >= t.totalRounds) {
      t.finished = true;
      t.survived = true;
      t.addLog('\n🌟【渡劫成功】你扛过天劫，劫数消散，道心更坚！体魄与魂力大涨。');
      p.physique += 20 + t.rank * 5;
      p.soulPower += 10 + t.rank * 3;
      p.luck += 2;
    }
    return t;
  }
}

enum CombatStatus { ongoing, win, flee, lose }

/// 战斗/渡劫日志最大保存条数，超出自动丢弃旧记录。
const int maxCombatLogEntries = 200;

class CombatResult {
  final Player player;
  final Npc npc;
  final Map<String, double> env;
  int round;
  CombatStatus status;
  final int npcHpMax;
  int playerPoison;
  int npcPoison;
  List<String> log;
  CombatResult({
    required this.player,
    required this.npc,
    required this.env,
    required this.round,
    required this.status,
    required this.npcHpMax,
    required this.playerPoison,
    required this.npcPoison,
    required this.log,
  });

  /// 追加战斗日志，超过上限自动丢弃最旧记录。
  void addLog(String line) {
    log.add(line);
    if (log.length > maxCombatLogEntries) {
      log.removeRange(0, log.length - maxCombatLogEntries);
    }
  }
}

class TribulationResult {
  final Player player;
  final int rank;
  final int totalRounds;
  int round;
  bool survived;
  bool finished;
  List<String> log;
  TribulationResult({
    required this.player,
    required this.rank,
    required this.totalRounds,
    required this.round,
    required this.survived,
    required this.finished,
    required this.log,
  });

  /// 追加渡劫日志，超过上限自动丢弃最旧记录。
  void addLog(String line) {
    log.add(line);
    if (log.length > maxCombatLogEntries) {
      log.removeRange(0, log.length - maxCombatLogEntries);
    }
  }
}
