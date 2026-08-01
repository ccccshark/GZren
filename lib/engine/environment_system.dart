// environment_system.dart
// V1.3 新增【昼夜、天气、副本BOSS定时刷新】核心环境系统。
// 设计原则：
//   - 纯上层逻辑，不改动 WorldTimer / CombatEngine 等核心引擎。
//   - 所有状态持久化于 player.flags（day_weather/boss_states），旧存档无键回退默认值，100%兼容。
//   - 游戏时间独立运行，基于 player.worldTime（小时）换算为游戏分钟，与现实时间无关。
//   - 赶路/采集/炼蛊/战斗结算都会推进 worldTime（由 command.tick 驱动），本系统据此推进昼夜天气。
import 'dart:math';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/scene_model.dart';

final _rng = Random();

/// 时段阶段配置。
class TimePhase {
  final String phase;
  final int start; // 游戏分钟（含）
  final int end;   // 游戏分钟（不含）
  final String desc;
  final Map<String, double> buff;     // 流派威力增益
  final Map<String, double> debuff;   // 如 捕捉成功率

  TimePhase(this.phase, this.start, this.end, this.desc, this.buff, this.debuff);
}

/// 天气配置。
class WeatherCfg {
  final String weather;
  final int weight;
  final Map<String, double> buff;
  final Map<String, dynamic> debuff;
  final String desc;

  WeatherCfg(this.weather, this.weight, this.buff, this.debuff, this.desc);
}

/// 环境系统：管理昼夜循环、区域天气、BOSS重生倒计时。
/// 所有静态配置在 EnvironmentSystem.init 时从 JSON 注入；运行时状态读写 player.flags。
class EnvironmentSystem {
  static int cycleTotalMinute = 480;
  static List<TimePhase> phases = [];
  static List<WeatherCfg> weatherList = [];
  static int weatherRefreshMinute = 120;
  // V1.5 新增【区域天气】：按区域独立配置天气（南疆/西漠），玩家跨区时切换天气表。
  // 旧存档兼容：无区域天气记录时回退到 weatherList（南疆默认）。
  static Map<String, List<WeatherCfg>> regionWeatherMap = {};
  static Map<String, int> regionWeatherRefresh = {};

  /// 从 time_config.json / weather_config.json 注入静态配置（缺失时用默认值兜底）。
  static void init(Map<String, dynamic>? timeCfg, Map<String, dynamic>? weatherCfg) {
    // 时段配置
    if (timeCfg != null) {
      cycleTotalMinute = (timeCfg['cycle_total_minute'] as num?)?.toInt() ?? 480;
      final ps = timeCfg['phase_setting'] as List? ?? [];
      phases = ps.map((e) {
        final m = e as Map<String, dynamic>;
        final buff = <String, double>{};
        for (final entry in (m['buff'] as Map? ?? {}).entries) {
          // V1.3 兼容：buff 值可能为 num 或 bool（true→1.0）
          final v = entry.value;
          if (v is num) {
            buff[entry.key as String] = v.toDouble();
          } else if (v is bool && v) {
            buff[entry.key as String] = 1.0;
          }
        }
        final debuff = <String, double>{};
        for (final entry in (m['debuff'] as Map? ?? {}).entries) {
          final v = entry.value;
          if (v is num) {
            debuff[entry.key as String] = v.toDouble();
          } else if (v is bool && v) {
            debuff[entry.key as String] = 1.0;
          }
        }
        return TimePhase(
          m['phase'] as String? ?? '白天',
          (m['start'] as num?)?.toInt() ?? 0,
          (m['end'] as num?)?.toInt() ?? 0,
          m['desc'] as String? ?? '',
          buff, debuff,
        );
      }).toList();
    }
    if (phases.isEmpty) {
      // 兜底默认
      phases = [
        TimePhase('白天', 0, 180, '阳光洒落山林', {'气道': 1.10, '光道': 1.10}, {}),
        TimePhase('黄昏', 180, 240, '夕阳垂落', {}, {}),
        TimePhase('夜晚', 240, 400, '夜幕笼罩，鬼道蛊威力提升', {'鬼道': 1.15}, {'捕捉成功率': 0.80}),
        TimePhase('凌晨', 400, 480, '夜色最深，寒气弥漫', {'月道': 1.10}, {'捕捉成功率': 0.70}),
      ];
    }
    // 天气配置
    if (weatherCfg != null) {
      weatherRefreshMinute = (weatherCfg['weather_refresh_minute'] as num?)?.toInt() ?? 120;
      final ws = weatherCfg['weather_list'] as List? ?? [];
      weatherList = ws.map((e) {
        final m = e as Map<String, dynamic>;
        final buff = <String, double>{};
        for (final entry in (m['buff'] as Map? ?? {}).entries) {
          // V1.3 兼容：buff 值可能为 num（流派倍率）或 bool（标记类增益，true→1.0）
          final v = entry.value;
          if (v is num) {
            buff[entry.key as String] = v.toDouble();
          } else if (v is bool && v) {
            buff[entry.key as String] = 1.0;
          }
        }
        return WeatherCfg(
          m['weather'] as String? ?? '晴朗',
          (m['weight'] as num?)?.toInt() ?? 1,
          buff,
          Map<String, dynamic>.from(m['debuff'] as Map? ?? {}),
          m['desc'] as String? ?? '',
        );
      }).toList();
    }
    if (weatherList.isEmpty) {
      weatherList = [
        WeatherCfg('晴朗', 40, {}, {}, '万里晴空'),
        WeatherCfg('小雨', 25, {'水道': 1.05}, {}, '细雨蒙蒙'),
        WeatherCfg('浓雾', 20, {}, {'捕捉成功率': 0.85}, '大雾弥漫'),
        WeatherCfg('梅雨', 15, {'水道': 1.10}, {'真元缓慢消耗': true}, '连绵梅雨'),
      ];
    }
    // V1.5 新增：将 init 传入的天气配置注册为默认区域（南疆）天气。
    regionWeatherMap['南疆'] = List<WeatherCfg>.from(weatherList);
    regionWeatherRefresh['南疆'] = weatherRefreshMinute;
  }

  // ============ V1.5 区域天气 ============
  /// 注册一个区域的天气配置（由 command.loadStatic 调用，如西漠 weather_ximo.json）。
  static void addRegionWeather(String region, Map<String, dynamic>? cfg) {
    if (cfg == null) return;
    final refresh = (cfg['weather_refresh_minute'] as num?)?.toInt() ?? weatherRefreshMinute;
    final ws = cfg['weather_list'] as List? ?? [];
    final list = ws.map((e) {
      final m = e as Map<String, dynamic>;
      final buff = <String, double>{};
      for (final entry in (m['buff'] as Map? ?? {}).entries) {
        final v = entry.value;
        if (v is num) {
          buff[entry.key as String] = v.toDouble();
        } else if (v is bool && v) {
          buff[entry.key as String] = 1.0;
        }
      }
      return WeatherCfg(
        m['weather'] as String? ?? '晴朗',
        (m['weight'] as num?)?.toInt() ?? 1,
        buff,
        Map<String, dynamic>.from(m['debuff'] as Map? ?? {}),
        m['desc'] as String? ?? '',
      );
    }).toList();
    if (list.isEmpty) return;
    regionWeatherMap[region] = list;
    regionWeatherRefresh[region] = refresh;
  }

  /// 根据房间 rid 判断所属区域（用于天气切换）。
  static String regionOf(String rid) {
    if (rid.startsWith('ximo_')) return '西漠';
    if (rid.startsWith('beiyuan_')) return '北原';
    if (rid.startsWith('donghai_')) return '东海'; // V1.9 五地全面开放
    if (rid.startsWith('zhongzhou_')) return '中州'; // V1.9 五地全面开放
    return '南疆'; // 默认区域
  }

  /// 玩家当前所在区域的天气列表（无区域配置时回退默认 weatherList）。
  static List<WeatherCfg> _weatherListOf(Player p) {
    final region = regionOf(p.location);
    return regionWeatherMap[region] ?? weatherList;
  }

  /// 当前区域天气刷新间隔（分钟）。
  static int _weatherRefreshOf(Player p) {
    final region = regionOf(p.location);
    return regionWeatherRefresh[region] ?? weatherRefreshMinute;
  }

  // ============ 游戏时间换算 ============
  /// 当前游戏分钟（一天=480分钟，可超出一整天）。
  static int gameMinute(Player p) => (p.worldTime * 60).round();

  /// 当前日内分钟（0~479）。
  static int dayCycleMinute(Player p) => gameMinute(p) % cycleTotalMinute;

  /// 当前游戏天数（从第1天开始）。
  static int gameDay(Player p) => (gameMinute(p) ~/ cycleTotalMinute) + 1;

  /// 当前时段。
  static TimePhase curPhase(Player p) {
    final m = dayCycleMinute(p);
    for (final ph in phases) {
      if (m >= ph.start && m < ph.end) return ph;
    }
    return phases.isNotEmpty ? phases.first : TimePhase('白天', 0, 480, '', {}, {});
  }

  /// 是否为夜晚时段（夜晚或凌晨）。
  static bool isNight(Player p) {
    final ph = curPhase(p).phase;
    return ph == '夜晚' || ph == '凌晨';
  }

  // ============ 天气 ============
  // V1.5 改造【区域天气】：天气状态按区域独立存储。
  //   - 南疆（默认区域）：沿用旧键 'env_weather' / 'env_weather_last'，100%兼容旧存档与既有逻辑。
  //   - 其他区域（如西漠）：使用 'env_weather_<region>' / 'env_weather_last_<region>' 独立存储。
  // 玩家跨区域时各区域保留各自天气，互不干扰。
  static String _weatherKey(Player p) {
    final region = regionOf(p.location);
    return region == '南疆' ? 'env_weather' : 'env_weather_$region';
  }
  static String _weatherLastKey(Player p) {
    final region = regionOf(p.location);
    return region == '南疆' ? 'env_weather_last' : 'env_weather_last_$region';
  }

  /// 当前区域天气（南疆存于 flags['env_weather']，其他区域存于 flags['env_weather_<region>']，缺失默认'晴朗'）。
  static String curWeather(Player p) =>
      p.flags[_weatherKey(p)] as String? ?? '晴朗';

  /// 上次刷新天气的游戏分钟（按区域独立存储）。
  static int _lastWeatherMinute(Player p) {
    final v = p.flags[_weatherLastKey(p)];
    if (v is num) return v.toInt();
    return 0;
  }

  static WeatherCfg? _findWeather(Player p, String name) {
    for (final w in _weatherListOf(p)) {
      if (w.weather == name) return w;
    }
    return null;
  }

  /// 推进天气：若距上次刷新达到区域 weatherRefreshMinute，按权重随机刷新区域天气。
  /// 由 command.tick 在 worldTime 推进后调用。返回是否刷新了天气。
  static bool tickWeather(Player p, {void Function(String, String)? onWeatherChange}) {
    final cur = gameMinute(p);
    final last = _lastWeatherMinute(p);
    if (cur - last < _weatherRefreshOf(p)) return false;
    _refreshWeather(p, onWeatherChange: onWeatherChange);
    p.flags[_weatherLastKey(p)] = cur;
    return true;
  }

  static void _refreshWeather(Player p, {void Function(String, String)? onWeatherChange}) {
    final list = _weatherListOf(p);
    if (list.isEmpty) return;
    int totalW = list.fold(0, (s, w) => s + w.weight);
    if (totalW <= 0) totalW = 1;
    int pick = _rng.nextInt(totalW);
    int acc = 0;
    String chosen = list.first.weather;
    for (final w in list) {
      acc += w.weight;
      if (pick < acc) { chosen = w.weather; break; }
    }
    final old = curWeather(p);
    p.flags[_weatherKey(p)] = chosen;
    if (onWeatherChange != null && old != chosen) onWeatherChange(old, chosen);
  }

  /// 强制设置天气（测试/事件用）。
  static void setWeather(Player p, String w) {
    p.flags[_weatherKey(p)] = w;
  }

  /// 天气 buff（流派增益倍率）。
  static Map<String, double> weatherBuff(Player p) => _findWeather(p, curWeather(p))?.buff ?? {};

  /// 天气 debuff（如捕捉成功率、真元缓慢消耗）。
  static Map<String, dynamic> weatherDebuff(Player p) => _findWeather(p, curWeather(p))?.debuff ?? {};

  // ============ 环境效果综合计算 ============
  /// 综合环境流派增益倍率：场景 envEffect × 时段 buff × 天气 buff。
  /// 用于战斗/炼蛊威力计算。缺失流派默认 1.0。
  static double schoolMultiplier(Player p, Room room, String school) {
    double mul = room.envEffect[school] ?? 1.0;
    mul *= curPhase(p).buff[school] ?? 1.0;
    mul *= weatherBuff(p)[school] ?? 1.0;
    return mul;
  }

  /// 综合捕捉成功率倍率：时段 debuff × 天气 debuff × 场景藏匿加成。
  /// 基础 1.0，夜间/浓雾降低。返回值用于乘到 gu_system.capture 的 base 上。
  /// V1.6 加固【环境机制】：浓雾天气下，密林/洞窟/秘境类场景蛊虫藏匿概率大幅提升
  ///   （捕捉成功率额外×0.6），体现"雾深蛊隐"的生态；普通场景仅受全局雾 debuff 影响。
  static double captureChanceMul(Player p, {Room? room}) {
    double mul = 1.0;
    final pd = curPhase(p).debuff['捕捉成功率'];
    if (pd != null) mul *= pd;
    final wd = weatherDebuff(p)['捕捉成功率'];
    if (wd != null) mul *= (wd as num).toDouble();
    // 场景藏匿加成：浓雾 + 密林/洞窟/秘境 → 额外×0.6
    if (room != null && curWeather(p) == '浓雾' && _isFogHideScene(room)) {
      mul *= 0.6;
    }
    return mul.clamp(0.05, 1.0);
  }

  /// 判定场景是否为"浓雾藏匿"类型（密林/洞窟/秘境）。
  /// 依据房间名关键词识别，兼容旧场景与新增 qm2 场景，无需改 JSON。
  static bool _isFogHideScene(Room room) {
    final name = room.name;
    return name.contains('密林') ||
        name.contains('洞窟') ||
        name.contains('洞') ||
        name.contains('秘境') ||
        name.contains('瘴林');
  }

  /// 梅雨天气真元缓慢消耗（每小时）。
  static bool weatherDrainsTrueyuan(Player p) {
    final wd = weatherDebuff(p)['真元缓慢消耗'];
    return wd == true;
  }

  // ============ 副本 BOSS 重生 ============
  /// 读取 BOSS 状态表（存于 flags['boss_states']）。
  /// 结构：{ rid: { alive: bool, death_minute: int, respawn_minute: int } }
  static Map<String, dynamic> bossStates(Player p) {
    final raw = p.flags['boss_states'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  /// BOSS 是否存活（首次进入副本默认存活；击杀后标记死亡直到倒计时结束）。
  static bool isBossAlive(Player p, String rid) {
    final states = bossStates(p);
    final st = states[rid];
    if (st is! Map) return true; // 无记录默认存活
    return (st['alive'] as bool?) ?? true;
  }

  /// V1.6 新增【BOSS 在场判定】：BOSS 是否真正现身于场景。
  /// 需同时满足：① 存活状态为真 ② limit_daytime/limit_weather 限制条件满足。
  /// 用于 doLook 隐藏未现身的 BOSS、attack 拦截不可攻击的 BOSS（如寒雾蛇王仅夜晚+浓雾现身）。
  static bool isBossPresent(Player p, String rid, Map<String, dynamic> bossInfo) {
    if (!isBossAlive(p, rid)) return false;
    return _bossLimitsSatisfied(p, bossInfo);
  }

  /// 标记 BOSS 死亡，启动重生倒计时（基于配置的 respawn_game_time 分钟）。
  static void markBossDead(Player p, String rid, Map<String, dynamic> bossInfo) {
    final states = bossStates(p);
    final respawnGameMin = (bossInfo['respawn_game_time'] as num?)?.toInt() ?? 120;
    states[rid] = {
      'alive': false,
      'death_minute': gameMinute(p),
      'respawn_minute': gameMinute(p) + respawnGameMin,
    };
    p.flags['boss_states'] = states;
  }

  /// 副本BOSS重生判定：遍历所有 boss 房间，若死亡且倒计时结束且时段/天气条件满足，则复活。
  /// 由 command.tick 调用。返回复活的 BOSS 描述列表（供日志播报）。
  static List<String> tickBossRespawn(Player p, Map<String, Room> rooms) {
    final revived = <String>[];
    final states = bossStates(p);
    final curMin = gameMinute(p);
    bool changed = false;
    for (final entry in rooms.entries) {
      final room = entry.value;
      if (room.bossInfo.isEmpty) continue;
      final st = states[entry.key];
      if (st is! Map) continue;
      if ((st['alive'] as bool?) ?? true) continue; // 已存活
      final respawnAt = (st['respawn_minute'] as num?)?.toInt() ?? 0;
      if (curMin < respawnAt) continue;
      // 时段/天气限制校验
      if (!_bossLimitsSatisfied(p, room.bossInfo)) continue;
      states[entry.key] = {'alive': true, 'death_minute': st['death_minute'], 'respawn_minute': respawnAt};
      changed = true;
      revived.add('【首领复苏】${room.bossInfo['boss_name'] ?? '副本BOSS'} 已在 ${room.name} 重新现身！');
    }
    if (changed) p.flags['boss_states'] = states;
    return revived;
  }

  /// 校验 BOSS 时段/天气限制是否满足。
  static bool _bossLimitsSatisfied(Player p, Map<String, dynamic> bossInfo) {
    final limitDay = bossInfo['limit_daytime'];
    if (limitDay is List && limitDay.isNotEmpty) {
      final ph = curPhase(p).phase;
      if (!limitDay.contains(ph)) return false;
    }
    final limitW = bossInfo['limit_weather'];
    if (limitW is List && limitW.isNotEmpty) {
      final w = curWeather(p);
      if (!limitW.contains(w)) return false;
    }
    return true;
  }

  /// 进入副本房间时判定 BOSS 状态：返回提示文本（null=BOSS存活，无提示）。
  /// 死亡且未到复活时间 → '此处首领尚未复苏'；限制条件不满足 → '首领未在此时/此天气现身'。
  static String? bossEnterPrompt(Player p, String rid, Map<String, dynamic> bossInfo) {
    final states = bossStates(p);
    final st = states[rid];
    final alive = (st is Map) ? ((st['alive'] as bool?) ?? true) : true;
    if (alive) return null;
    final stMap = st as Map;
    final respawnAt = (stMap['respawn_minute'] as num?)?.toInt() ?? 0;
    if (gameMinute(p) < respawnAt) {
      final left = respawnAt - gameMinute(p);
      return '此处首领尚未复苏（约 $left 分钟后重生）。';
    }
    // 倒计时已到但限制条件不满足
    if (!_bossLimitsSatisfied(p, bossInfo)) {
      final limitDay = bossInfo['limit_daytime'];
      final limitW = bossInfo['limit_weather'];
      final parts = <String>[];
      if (limitDay is List && limitDay.isNotEmpty) parts.add('需${limitDay.join("/")}时段');
      if (limitW is List && limitW.isNotEmpty) parts.add('需${limitW.join("/")}天气');
      return '首领倒计时已到，但条件未满足（${parts.join("、")}）。';
    }
    return null;
  }
}
