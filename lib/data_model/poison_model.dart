// poison_model.dart
// 蛊真人原著【毒素中毒系统】数据模型（增量文件，不动旧代码）。
// 设计原则：
//   - 100% 兼容旧存档：毒素状态存入 player.flags['poisons']，旧存档无键回退空列表
//   - 不修改 Player / GuTemplate 等现有模型字段，仅通过 flags 持久化
//   - 与现有 injure['毒伤'] 联动：只要还有毒素就保留 '毒伤' 标签
//
// 毒素分级（原著设定）：
//   minor  轻微毒素  —— 蛇瘴、虫毒等，静坐可缓慢代谢
//   fierce 烈性毒素  —— 蟒毒、剧毒蛊命中，静坐仅延缓，需解毒草药或解毒蛊
//   odd    奇毒      —— 罕见奇毒，凡蛊/草药无法解除，需强力解毒蛊
//   dao    道毒      —— 毒道高人/道痕冲突反噬，会同步造成道伤，凡蛊/草药绝对无法解除
//
// 多种毒素可叠加共存：flags['poisons'] 存 List<Map>，每种毒素独立计时。
import 'dart:math' show max, min;
import 'player_model.dart';

/// 毒素等级枚举。
enum PoisonRank {
  minor,   // 轻微毒素
  fierce,  // 烈性毒素
  odd,     // 奇毒
  dao;     // 道毒

  String get cn => switch (this) {
    PoisonRank.minor  => '轻微毒素',
    PoisonRank.fierce => '烈性毒素',
    PoisonRank.odd    => '奇毒',
    PoisonRank.dao    => '道毒',
  };

  /// 等级数值，用于比较。
  int get value => switch (this) {
    PoisonRank.minor  => 1,
    PoisonRank.fierce => 2,
    PoisonRank.odd    => 3,
    PoisonRank.dao    => 4,
  };

  static PoisonRank fromName(String? s) => switch (s) {
    'minor'  || '轻微' => PoisonRank.minor,
    'fierce' || '烈性' => PoisonRank.fierce,
    'odd'    || '奇'   => PoisonRank.odd,
    'dao'    || '道'   => PoisonRank.dao,
    _                 => PoisonRank.minor,
  };
}

/// 单一毒素实例（存于 flags['poisons'] 数组中，可被 JSON 序列化）。
class PoisonInstance {
  /// 毒素唯一标识（如 'snake_mist'、'python_venom'、'dao_poison'），同名不叠加层数，仅刷新强度。
  final String pid;
  /// 展示名（如 '蛇瘴毒'、'蟒毒'、'毒道反噬'）。
  final String name;
  /// 毒素等级。
  final PoisonRank rank;
  /// 每次毒发造成的气血损伤（已随等级放大）。
  final int power;
  /// 毒发周期（小时）。每经过该小时数毒发一次。
  final int tickHours;
  /// 距离下次毒发剩余小时（递减）。
  double hoursLeft;
  /// 总剩余持续时间（小时）。归零后自然消散（仅轻微毒素会自然消散；高阶不消散）。
  double durationLeft;
  /// 累计毒发次数（用于触发永久暗伤判定）。
  int tickCount;
  /// 来源描述（如 '蟒王攻击'、'毒瘴随机事件'、'燃烧寿元逼毒失败'）。
  final String source;

  PoisonInstance({
    required this.pid,
    required this.name,
    required this.rank,
    required this.power,
    required this.tickHours,
    required this.hoursLeft,
    required this.durationLeft,
    this.tickCount = 0,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
    'pid': pid,
    'name': name,
    'rank': rank.name,
    'power': power,
    'tick_hours': tickHours,
    'hours_left': hoursLeft,
    'duration_left': durationLeft,
    'tick_count': tickCount,
    'source': source,
  };

  factory PoisonInstance.fromJson(Map<String, dynamic> j) => PoisonInstance(
    pid: j['pid'] ?? 'unknown',
    name: j['name'] ?? '未知毒素',
    rank: PoisonRank.fromName(j['rank'] as String?),
    power: (j['power'] as num? ?? 0).toInt(),
    tickHours: (j['tick_hours'] as num? ?? 12).toInt(),
    hoursLeft: (j['hours_left'] as num? ?? 12).toDouble(),
    durationLeft: (j['duration_left'] as num? ?? 24).toDouble(),
    tickCount: (j['tick_count'] as num? ?? 0).toInt(),
    source: j['source'] ?? '未知',
  );

  /// 简要描述（用于 UI 展示）。
  String brief() {
    final next = hoursLeft <= 0 ? 0 : hoursLeft;
    return '$name[${rank.cn}] 威力${power} 下次毒发${next.toStringAsFixed(0)}h后'
        '${durationLeft < 999999 ? ' 存续${durationLeft.toStringAsFixed(0)}h' : ' 难以自消'}'
        ' 累计毒发${tickCount}次';
  }
}

/// 毒素系统对 Player（flags）的读写封装。
/// 所有方法都是静态的，传入 Player 即可操作，无需扩展 Player 类。
class PoisonStore {
  /// 读取玩家当前所有毒素（旧存档无 key 返回空）。
  static List<PoisonInstance> list(Player p) {
    final raw = p.flags['poisons'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => PoisonInstance.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// 写回毒素列表到 flags 并联动伤势标签。
  static void save(Player p, List<PoisonInstance> poisons) {
    p.flags['poisons'] = poisons.map((x) => x.toJson()).toList();
    // 联动旧伤势体系：只要还有毒素就保留 '毒伤' 标签；毒素清空且无其它毒源则移除。
    if (poisons.isNotEmpty) {
      if (!p.injure.contains('毒伤')) p.addInjure('毒伤');
    } else {
      // 仅当没有 '毒伤' 来源时移除；保留旧事件添加的 '毒伤' 兼容性。
      p.healInjure('毒伤');
    }
  }

  /// 当前是否中毒。
  static bool hasAny(Player p) => list(p).isNotEmpty;

  /// 是否存在指定等级毒素。
  static bool hasRank(Player p, PoisonRank r) =>
      list(p).any((x) => x.rank == r);

  /// 是否存在道毒（特殊判定：道毒会同步造成道伤）。
  static bool hasDaoPoison(Player p) => hasRank(p, PoisonRank.dao);

  /// 中毒总等级（用于 UI 标签颜色/严重度排序）。
  static int maxRankValue(Player p) {
    final ls = list(p);
    if (ls.isEmpty) return 0;
    return ls.map((x) => x.rank.value).reduce(max);
  }

  /// 添加或刷新一层毒素。同名 pid 已存在则取更强者并刷新持续时间。
  static void add(Player p, PoisonInstance ins) {
    final ls = list(p);
    final idx = ls.indexWhere((x) => x.pid == ins.pid);
    if (idx >= 0) {
      final old = ls[idx];
      // 取威力更高者，但刷新持续与下次毒发计时。
      final stronger = ins.power >= old.power ? ins : old;
      ls[idx] = PoisonInstance(
        pid: old.pid,
        name: stronger.name,
        rank: stronger.rank.value >= old.rank.value ? stronger.rank : old.rank,
        power: max(old.power, ins.power),
        tickHours: stronger.tickHours,
        hoursLeft: ins.hoursLeft, // 刷新计时
        durationLeft: max(old.durationLeft, ins.durationLeft),
        tickCount: old.tickCount,
        source: ins.source.isNotEmpty ? ins.source : old.source,
      );
    } else {
      ls.add(ins);
    }
    save(p, ls);
  }

  /// 减少某毒素的剩余持续时间（用于静坐代谢）。
  /// 仅 [rank] <= [maxRank] 的毒素会被代谢；返回被代谢的毒素名列表。
  static List<String> metabolize(Player p, double hours, {PoisonRank? maxRank}) {
    final ls = list(p);
    if (ls.isEmpty) return const [];
    final removed = <String>[];
    final remain = <PoisonInstance>[];
    for (final x in ls) {
      if (maxRank != null && x.rank.value > maxRank.value) {
        // 高阶毒素仅延缓毒发计时，不消耗总持续时间。
        remain.add(PoisonInstance(
          pid: x.pid, name: x.name, rank: x.rank, power: x.power,
          tickHours: x.tickHours,
          hoursLeft: min(x.hoursLeft + hours * 0.5, x.tickHours.toDouble()),
          durationLeft: x.durationLeft, tickCount: x.tickCount, source: x.source,
        ));
        continue;
      }
      final newDur = x.durationLeft - hours;
      if (newDur <= 0) {
        removed.add(x.name);
      } else {
        remain.add(PoisonInstance(
          pid: x.pid, name: x.name, rank: x.rank, power: x.power,
          tickHours: x.tickHours,
          hoursLeft: x.hoursLeft, durationLeft: newDur,
          tickCount: x.tickCount, source: x.source,
        ));
      }
    }
    save(p, remain);
    return removed;
  }

  /// 解毒：尝试解除 [maxRank] 及以下毒素，降低 [power] 点威力。
  /// 威力归零的毒素被清除。返回被解除的毒素名列表。
  /// 注意：凡蛊/草药调用本方法时 maxRank 必须为 odd 以下，dao 永不解除。
  static List<String> reduce(Player p, int power, {required PoisonRank maxRank}) {
    final ls = list(p);
    if (ls.isEmpty) return const [];
    final removed = <String>[];
    final remain = <PoisonInstance>[];
    for (final x in ls) {
      if (x.rank.value > maxRank.value) {
        // 超过可解等级，仅轻微压制（延后下次毒发）。
        remain.add(PoisonInstance(
          pid: x.pid, name: x.name, rank: x.rank, power: x.power,
          tickHours: x.tickHours,
          hoursLeft: min(x.hoursLeft + power * 0.5, x.tickHours.toDouble()),
          durationLeft: x.durationLeft, tickCount: x.tickCount, source: x.source,
        ));
        continue;
      }
      final np = x.power - power;
      if (np <= 0) {
        removed.add(x.name);
      } else {
        remain.add(PoisonInstance(
          pid: x.pid, name: x.name, rank: x.rank, power: np,
          tickHours: x.tickHours,
          hoursLeft: min(x.hoursLeft + power * 0.5, x.tickHours.toDouble()),
          durationLeft: x.durationLeft, tickCount: x.tickCount, source: x.source,
        ));
      }
    }
    save(p, remain);
    return removed;
  }

  /// 移除指定 pid 的毒素（用于以毒攻毒失败叠加的特殊处理）。
  static void removeByPid(Player p, String pid) {
    final ls = list(p).where((x) => x.pid != pid).toList();
    save(p, ls);
  }
}
