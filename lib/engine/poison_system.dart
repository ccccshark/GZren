// poison_system.dart
// 蛊真人原著【毒素中毒系统】引擎核心（增量文件，不动旧代码）。
//
// 职责：
//   1. 周期性毒发：由 world_timer.advance 调用 tick()，按每条毒素自身周期结算。
//   2. 解毒途径：静坐代谢 / 解毒草药 / 解毒蛊虫 / 燃烧寿元逼毒 / 以毒攻毒。
//   3. 联动伤势：毒发有概率加重伤势；道毒同步造成道伤（魂力损耗）。
//   4. 永久暗伤：累计毒发达到阈值且长期未清，留下永久 '暗伤' 标签。
//   5. 中毒触发器：供战斗/随机事件调用 applyPoison() 注入毒素。
//
// 与现有体系的接入点（均不改动旧代码）：
//   - world_timer.dart: 在 advance 末尾调用 PoisonSystem.tick(p, hours, log)
//   - gu_system.dart useGu(): switch 增加 case 'detox' 分支，调 detoxByGu()
//   - command.dart: 新增 doConsumeHerb / doBurnLife / doPoisonAttack 指令分支
//   - combat.dart: 攻击命中后调 applyPoison() 替代原 addInjure('毒伤')
//   - random_event: effect 增加 'poison' 字段
import 'dart:math';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/poison_model.dart';
import 'player_core.dart' show levelRank;

final _rng = Random();

// ---- 永久暗伤阈值（原著：毒素长期无法清除会留下永久暗伤）----
const int _permanentInjuryTickThreshold = 6; // 累计毒发 6 次以上长期未清 → 暗伤

class PoisonSystem {
  // ===================== 1. 周期性毒发（由 world_timer 调用）=====================

  /// 推进所有毒素计时。返回日志行（由调用方加入 log 列表）。
  /// 会修改玩家状态：扣气血、加重伤势、道毒扣魂力、累计毒发次数。
  static List<String> tick(Player p, double hours) {
    if (!p.alive) return const [];
    final ls = PoisonStore.list(p);
    if (ls.isEmpty) return const [];
    final logs = <String>[];
    final remain = <PoisonInstance>[];

    for (final x in ls) {
      var hoursLeft = x.hoursLeft - hours;
      var durationLeft = x.durationLeft;
      var tickCount = x.tickCount;

      // 计算本次推进触发的毒发次数（hoursLeft 跨越多个周期）
      int fired = 0;
      while (hoursLeft <= 0) {
        fired += 1;
        hoursLeft += x.tickHours;
        tickCount += 1;
      }

      // 自然消散：仅轻微毒素且总持续时间耗尽。
      if (x.rank == PoisonRank.minor && durationLeft < 999999) {
        durationLeft -= hours;
        if (durationLeft <= 0) {
          logs.add('【毒解】${x.name}（轻微毒素）已被你的体质自然代谢完毕。');
          continue;
        }
      } else if (durationLeft < 999999) {
        // 高阶毒素总持续时间也减少（但不会因此消散，仅记录）
        durationLeft = max(0, durationLeft - hours);
      }

      // 毒发结算（每次毒发扣气血、有概率加重伤势；道毒同步扣魂力）
      if (fired > 0) {
        final totalDmg = x.power * fired;
        p.physique = max(0, p.physique - totalDmg);
        logs.add('【毒发】${x.name}[${x.rank.cn}] 发作，气血 -$totalDmg'
            '${fired > 1 ? "（连续 $fired 次）" : ""}'
            '，剩余体魄 ${p.physique}。');

        // 加重伤势：烈性及以上毒发有概率加重 '毒伤'，并新增 '内伤'
        if (x.rank.value >= PoisonRank.fierce.value) {
          final injChance = x.rank == PoisonRank.fierce ? 0.18
              : (x.rank == PoisonRank.odd ? 0.32 : 0.5);
          if (_rng.nextDouble() < injChance * fired) {
            if (!p.injure.contains('内伤')) p.addInjure('内伤');
            logs.add('  毒气侵脏，新增伤势：内伤！仅疗伤不解毒将反复恶化。');
          }
        }
        // 道毒同步造成道伤（魂力损耗，与道痕冲突一致）
        if (x.rank == PoisonRank.dao) {
          final soulDmg = (x.power * 0.4 * fired).toInt();
          if (soulDmg > 0) {
            p.soulPower = max(1, p.soulPower - soulDmg);
            logs.add('  道毒侵蚀道基，魂力 -$soulDmg。');
          }
        }

        // 体魄归零死亡（不直接置 alive=false，交由 world_timer 检测寿元逻辑兜底）
        if (p.physique <= 0) {
          logs.add('【毒发身亡】你身中 ${x.name} 毒发过重，气血枯竭……');
        }
      }

      remain.add(PoisonInstance(
        pid: x.pid, name: x.name, rank: x.rank, power: x.power,
        tickHours: x.tickHours,
        hoursLeft: hoursLeft, durationLeft: durationLeft,
        tickCount: tickCount, source: x.source,
      ));
    }

    PoisonStore.save(p, remain);

    // 永久暗伤判定：累计毒发次数超过阈值且仍有高阶毒素 → 留下 '暗伤'
    if (remain.any((x) => x.tickCount >= _permanentInjuryTickThreshold
                        && x.rank.value >= PoisonRank.fierce.value)) {
      if (!p.injure.contains('暗伤')) {
        p.addInjure('暗伤');
        logs.add('【暗伤成疾】毒素长期盘踞不去，已在你体内留下永久暗伤，'
            '寿元流逝将加快，须尽快寻得高人彻底祛毒。');
      }
    }

    return logs;
  }

  // ===================== 2. 中毒触发器 =====================

  /// 注入一层毒素。供战斗/事件/炼蛊失败等场景调用。
  /// [pid] 唯一标识，[rank] 等级，[power] 威力（每次毒发扣气血），
  /// [tickHours] 毒发周期小时，[durationHours] 总持续小时（高阶传 999999 表示难自消）。
  static void applyPoison(Player p, {
    required String pid,
    required String name,
    required PoisonRank rank,
    required int power,
    int tickHours = 12,
    double? durationHours,
    required String source,
  }) {
    final dur = durationHours ?? switch (rank) {
      PoisonRank.minor  => 48.0,
      PoisonRank.fierce => 240.0,
      PoisonRank.odd    => 720.0,
      PoisonRank.dao    => 999999.0,
    };
    PoisonStore.add(p, PoisonInstance(
      pid: pid, name: name, rank: rank, power: power,
      tickHours: tickHours, hoursLeft: tickHours.toDouble(),
      durationLeft: dur, source: source,
    ));
  }

  // ===================== 3. 解毒途径 =====================

  // ---- 途径①：静坐休养（仅缓慢代谢轻微毒素，高阶仅延缓）----
  /// 返回日志行列表。hours 为本次静坐推进的世界小时数。
  static List<String> detoxByRest(Player p, double hours) {
    final logs = <String>[];
    final removed = PoisonStore.metabolize(p, hours, maxRank: PoisonRank.minor);
    for (final n in removed) {
      logs.add('【静坐祛毒】你运功调息，将 $n（轻微毒素）尽数化解。');
    }
    if (PoisonStore.hasRank(p, PoisonRank.fierce) ||
        PoisonStore.hasRank(p, PoisonRank.odd) ||
        PoisonStore.hasRank(p, PoisonRank.dao)) {
      logs.add('静坐仅延缓了体内高阶毒素的发作，无法根除，需寻解毒之物。');
    }
    return logs;
  }

  // ---- 途径②：解毒草药（解除轻微，压制烈性；重复使用效果衰减）----
  /// [herbPower] 草药解毒力度，[usesToday] 当日已使用次数（用于衰减）。
  /// 凡蛊/草药硬限制：无法解除奇毒与道毒。
  static List<String> detoxByHerb(Player p, int herbPower, {int usesToday = 0}) {
    final logs = <String>[];
    if (!PoisonStore.hasAny(p)) {
      logs.add('你体内无毒，服用解毒草药无益。');
      return logs;
    }
    // 重复使用效果衰减：每次衰减 15%，最低保留 30%
    final decay = (1 - usesToday * 0.15).clamp(0.3, 1.0);
    final effective = (herbPower * decay).toInt();
    logs.add('你服下解毒草药，药力 $effective（重复使用衰减至 ${(decay * 100).round()}%）。');
    final removed = PoisonStore.reduce(p, effective, maxRank: PoisonRank.fierce);
    for (final n in removed) {
      logs.add('【药到毒解】$n 被草药药力尽数化解！');
    }
    if (PoisonStore.hasRank(p, PoisonRank.odd) || PoisonStore.hasRank(p, PoisonRank.dao)) {
      logs.add('草药对奇毒、道毒无效，体内仍潜伏剧毒。');
    } else if (PoisonStore.hasRank(p, PoisonRank.fierce)) {
      logs.add('烈性毒素被压制，但未根除，需更强药力或解毒蛊。');
    }
    return logs;
  }

  // ---- 途径③：解毒蛊虫（主流手段；低阶无法解奇毒/道毒；强力蛊消耗气血真元）----
  /// [guRank] 解毒蛊转数，[power] 解毒力度。
  /// 低阶蛊（rank<=2）最高解 fierce；中阶（rank 3-4）可解 odd；高阶（rank>=5）可解 dao。
  /// 强力解毒蛊（rank>=3）使用消耗气血真元。
  static List<String> detoxByGu(Player p, int guRank, int power) {
    final logs = <String>[];
    if (!PoisonStore.hasAny(p)) {
      logs.add('你体内无毒，催动解毒蛊徒耗真元。');
      return logs;
    }
    // 强力蛊消耗
    if (guRank >= 3) {
      final hpCost = 5 + guRank * 2;
      final zhenCost = 10 + guRank * 5;
      p.physique = max(0, p.physique - hpCost);
      p.spendTrueyuan(zhenCost);
      logs.add('强力解毒蛊催动，反噬气血 -$hpCost、真元 -$zhenCost。');
    }
    final maxRank = guRank <= 2 ? PoisonRank.fierce
        : (guRank <= 4 ? PoisonRank.odd : PoisonRank.dao);
    final removed = PoisonStore.reduce(p, power, maxRank: maxRank);
    for (final n in removed) {
      logs.add('【蛊力祛毒】$n 被解毒蛊尽数驱除！');
    }
    if (maxRank == PoisonRank.fierce && PoisonStore.hasRank(p, PoisonRank.odd)) {
      logs.add('低阶解毒蛊对奇毒、道毒无能为力。');
    } else if (maxRank == PoisonRank.odd && PoisonStore.hasRank(p, PoisonRank.dao)) {
      logs.add('此蛊可解奇毒，但对道毒仍束手无策。');
    }
    if (PoisonStore.hasRank(p, PoisonRank.dao) && guRank < 5) {
      logs.add('道毒非凡蛊可解，唯有高阶解毒蛊或非常之法方能祛除。');
    }
    return logs;
  }

  // ---- 途径④a：燃烧寿元强行逼毒（永久削减寿元）----
  /// [burnYears] 燃烧寿元年数。成功概率随燃烧年数与境界提升。
  /// 成功：解除所有 fierce 及以下毒素，并对 odd/dao 造成重创；失败：毒素叠加。
  static List<String> detoxByBurnLife(Player p, double burnYears) {
    final logs = <String>[];
    if (!PoisonStore.hasAny(p)) {
      logs.add('你体内无毒，何须燃烧寿元。');
      return logs;
    }
    if (p.lifeLeft <= burnYears + 1) {
      logs.add('寿元将尽，不敢再燃烧，恐当场陨落。');
      return logs;
    }
    p.lifeLeft -= burnYears;
    p.tribulation += 30;
    logs.add('你咬牙燃烧寿元 $burnYears 年强行逼毒，劫数暗生……');

    final rank = levelRank(p.level);
    final successChance = (0.3 + burnYears * 0.05 + rank * 0.03).clamp(0.3, 0.85);
    if (_rng.nextDouble() < successChance) {
      // 成功：解除 fierce 及以下，对 odd/dao 削减威力
      final removed = PoisonStore.reduce(p, 9999, maxRank: PoisonRank.fierce);
      for (final n in removed) logs.add('【逼毒成功】$n 被寿元之火焚尽！');
      if (PoisonStore.hasRank(p, PoisonRank.odd) ||
          PoisonStore.hasRank(p, PoisonRank.dao)) {
        final heavy = PoisonStore.reduce(p, (burnYears * 5).toInt(), maxRank: PoisonRank.dao);
        for (final n in heavy) logs.add('【逼毒成功】寿元之火重创 $n，将其驱除！');
        if (PoisonStore.hasRank(p, PoisonRank.dao)) {
          logs.add('然而道毒深植道基，寿元之火只能压制，未能根除。');
        }
      }
    } else {
      // 失败：毒素叠加
      logs.add('【逼毒失败】寿元白白燃烧，毒气反扑，毒素叠加！');
      PoisonStore.add(p, PoisonInstance(
        pid: 'burn_backlash', name: '逼毒反噬毒', rank: PoisonRank.fierce,
        power: 8, tickHours: 8, hoursLeft: 8, durationLeft: 120,
        source: '燃烧寿元逼毒失败反噬',
      ));
    }
    return logs;
  }

  // ---- 途径④b：以毒攻毒（失败则毒素叠加）----
  /// [poisonPid] 使用何种毒素去攻（玩家需持有相应材料/蛊）。
  /// [poisonPower] 攻毒力度。成功：解除 1 种最高阶毒素；失败：叠加该攻毒毒素。
  static List<String> detoxByPoisonAttack(Player p, {
    required String attackPid,
    required String attackName,
    required PoisonRank attackRank,
    required int poisonPower,
  }) {
    final logs = <String>[];
    if (!PoisonStore.hasAny(p)) {
      logs.add('你体内无毒，以毒攻毒多此一举。');
      return logs;
    }
    // 选当前最高阶毒素作为攻击目标
    final ls = PoisonStore.list(p);
    if (ls.isEmpty) {
      logs.add('你体内无毒，以毒攻毒多此一举。');
      return logs;
    }
    final target = ls.reduce((a, b) => a.rank.value > b.rank.value ? a : b);
    final successChance = (0.5 + (poisonPower - target.power) * 0.02)
        .clamp(0.2, 0.8);
    logs.add('你以 $attackName 攻体内 ${target.name}，成败在此一举……');
    if (_rng.nextDouble() < successChance) {
      PoisonStore.removeByPid(p, target.pid);
      logs.add('【以毒攻毒·成功】${target.name} 被 $attackName 克制化解！');
    } else {
      logs.add('【以毒攻毒·失败】两毒相冲未能制衡，反叠加为患！');
      PoisonStore.add(p, PoisonInstance(
        pid: attackPid, name: attackName, rank: attackRank, power: poisonPower,
        tickHours: 12, hoursLeft: 12, durationLeft: 240,
        source: '以毒攻毒失败叠加',
      ));
    }
    return logs;
  }

  // ===================== 4. 工具：当日服用草药次数（存 flags）=====================

  static int herbUsesToday(Player p) {
    final raw = p.flags['herb_uses'] as Map?;
    if (raw == null) return 0;
    final day = (p.worldTime / 24).floor();
    if (raw['day'] != day) return 0;
    return (raw['count'] as num?)?.toInt() ?? 0;
  }

  static void incHerbUses(Player p) {
    final day = (p.worldTime / 24).floor();
    final cur = herbUsesToday(p);
    p.flags['herb_uses'] = {'day': day, 'count': cur + 1};
  }
}
