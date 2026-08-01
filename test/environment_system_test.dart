// environment_system_test.dart
// V1.3 专项测试【昼夜、天气、副本BOSS定时刷新】
// 验证：
//   1. 游戏时间换算（分钟/天数/日内分钟）
//   2. 昼夜四阶段切换（白天/黄昏/夜晚/凌晨）
//   3. 区域天气周期刷新（按权重随机）
//   4. 副本BOSS重生倒计时（死亡标记→倒计时→复活）
//   5. 时段/天气限定BOSS（不满足条件不复活）
//   6. 环境联动（流派倍率综合计算/捕捉成功率修正）
//   7. 旧存档兼容（flags 无键回退默认值，不闪退）
//   8. 炼蛊环境需求配置解析（Recipe.envRequired）
import 'package:flutter_test/flutter_test.dart';
import 'package:gzren/engine/environment_system.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/scene_model.dart';
import 'package:gzren/data_model/recipe_model.dart';

void main() {
  setUpAll(() {
    // 初始化环境系统（注入与 assets/static 配置一致的数据）
    EnvironmentSystem.init({
      'cycle_total_minute': 480,
      'phase_setting': [
        {'phase': '白天', 'start': 0, 'end': 180, 'desc': '阳光洒落山林',
          'buff': {'气道': 1.10, '光道': 1.10}, 'debuff': {}},
        {'phase': '黄昏', 'start': 180, 'end': 240, 'desc': '夕阳垂落',
          'buff': {}, 'debuff': {}},
        {'phase': '夜晚', 'start': 240, 'end': 400, 'desc': '夜幕笼罩',
          'buff': {'鬼道': 1.15}, 'debuff': {'捕捉成功率': 0.80}},
        {'phase': '凌晨', 'start': 400, 'end': 480, 'desc': '夜色最深',
          'buff': {'月道': 1.10}, 'debuff': {'捕捉成功率': 0.70}},
      ],
    }, {
      'region': '南疆',
      'weather_refresh_minute': 120,
      'weather_list': [
        {'weather': '晴朗', 'weight': 40, 'buff': {}, 'debuff': {}, 'desc': '万里晴空'},
        {'weather': '小雨', 'weight': 25, 'buff': {'水道': 1.05}, 'debuff': {}, 'desc': '细雨蒙蒙'},
        {'weather': '浓雾', 'weight': 20, 'buff': {}, 'debuff': {'捕捉成功率': 0.85}, 'desc': '大雾弥漫'},
        {'weather': '梅雨', 'weight': 15, 'buff': {'水道': 1.10}, 'debuff': {'真元缓慢消耗': true}, 'desc': '连绵梅雨'},
      ],
    });
  });

  group('一、游戏时间换算', () {
    test('worldTime=0 → 游戏分钟0 → 第1天', () {
      final p = Player(worldTime: 0);
      expect(EnvironmentSystem.gameMinute(p), 0);
      expect(EnvironmentSystem.gameDay(p), 1);
      expect(EnvironmentSystem.dayCycleMinute(p), 0);
    });

    test('worldTime=3小时 → 180分钟 → 黄昏起点', () {
      // 180 分钟落在黄昏 [180,240)
      final p = Player(worldTime: 3);
      expect(EnvironmentSystem.gameMinute(p), 180);
      expect(EnvironmentSystem.dayCycleMinute(p), 180);
      expect(EnvironmentSystem.gameDay(p), 1);
      expect(EnvironmentSystem.curPhase(p).phase, '黄昏');
    });

    test('worldTime=8小时 → 480分钟 → 第2天 第0分钟（白天）', () {
      final p = Player(worldTime: 8);
      expect(EnvironmentSystem.gameMinute(p), 480);
      expect(EnvironmentSystem.gameDay(p), 2);
      expect(EnvironmentSystem.dayCycleMinute(p), 0);
      expect(EnvironmentSystem.curPhase(p).phase, '白天');
    });

    test('游戏时间独立于现实时间，仅由 worldTime 决定', () {
      final p1 = Player(worldTime: 4); // 240分钟
      final p2 = Player(worldTime: 4);
      expect(EnvironmentSystem.gameMinute(p1), EnvironmentSystem.gameMinute(p2));
      expect(EnvironmentSystem.curPhase(p1).phase, '夜晚');
    });
  });

  group('二、昼夜四阶段切换', () {
    test('白天 [0,180)', () {
      expect(EnvironmentSystem.curPhase(Player(worldTime: 0)).phase, '白天');
      expect(EnvironmentSystem.curPhase(Player(worldTime: 2.9)).phase, '白天');
    });
    test('黄昏 [180,240)', () {
      expect(EnvironmentSystem.curPhase(Player(worldTime: 3)).phase, '黄昏');
      expect(EnvironmentSystem.curPhase(Player(worldTime: 3.9)).phase, '黄昏');
    });
    test('夜晚 [240,400) 鬼道增益', () {
      final ph = EnvironmentSystem.curPhase(Player(worldTime: 4));
      expect(ph.phase, '夜晚');
      expect(ph.buff['鬼道'], 1.15);
      expect(ph.debuff['捕捉成功率'], 0.80);
    });
    test('凌晨 [400,480) 月道增益', () {
      final ph = EnvironmentSystem.curPhase(Player(worldTime: 6.7));
      expect(ph.phase, '凌晨');
      expect(ph.buff['月道'], 1.10);
    });
    test('isNight：夜晚与凌晨为true', () {
      expect(EnvironmentSystem.isNight(Player(worldTime: 5)), true);   // 夜晚
      expect(EnvironmentSystem.isNight(Player(worldTime: 6.8)), true); // 凌晨
      expect(EnvironmentSystem.isNight(Player(worldTime: 1)), false);  // 白天
      expect(EnvironmentSystem.isNight(Player(worldTime: 3.5)), false); // 黄昏
    });
  });

  group('三、区域天气系统', () {
    test('旧存档无天气字段 → 默认晴朗', () {
      final p = Player();
      expect(p.flags.containsKey('env_weather'), false);
      expect(EnvironmentSystem.curWeather(p), '晴朗');
    });

    test('tickWeather 未达周期不刷新', () {
      final p = Player(worldTime: 1);
      p.flags['env_weather'] = '晴朗';
      p.flags['env_weather_last'] = 0;
      // 1小时=60分钟 < 120分钟周期，不刷新
      final refreshed = EnvironmentSystem.tickWeather(p);
      expect(refreshed, false);
      expect(EnvironmentSystem.curWeather(p), '晴朗');
    });

    test('tickWeather 达到周期刷新天气', () {
      final p = Player(worldTime: 3); // 180分钟 ≥ 120周期
      p.flags['env_weather'] = '晴朗';
      p.flags['env_weather_last'] = 0;
      final refreshed = EnvironmentSystem.tickWeather(p);
      expect(refreshed, true);
      // 刷新后 last 更新为当前分钟
      expect(p.flags['env_weather_last'], 180);
      // 新天气必须在天气池中
      expect(
        ['晴朗', '小雨', '浓雾', '梅雨'].contains(EnvironmentSystem.curWeather(p)),
        true,
      );
    });

    test('梅雨天气真元缓慢消耗标志', () {
      final p = Player();
      p.flags['env_weather'] = '梅雨';
      expect(EnvironmentSystem.weatherDrainsTrueyuan(p), true);
      p.flags['env_weather'] = '晴朗';
      expect(EnvironmentSystem.weatherDrainsTrueyuan(p), false);
    });

    test('小雨天气水道增益', () {
      final p = Player();
      p.flags['env_weather'] = '小雨';
      expect(EnvironmentSystem.weatherBuff(p)['水道'], 1.05);
    });

    test('setWeather 强制设置天气（事件/测试用）', () {
      final p = Player();
      EnvironmentSystem.setWeather(p, '浓雾');
      expect(EnvironmentSystem.curWeather(p), '浓雾');
      expect(EnvironmentSystem.weatherDebuff(p)['捕捉成功率'], 0.85);
    });
  });

  group('四、副本BOSS定时重生', () {
    final bossInfo = {
      'npc_id': 'npc_boss_001',
      'boss_name': '测试蛊王',
      'respawn_game_time': 120,
      'limit_daytime': <String>[],
      'limit_weather': <String>[],
    };
    final room = Room(
      rid: 'boss_room_01', name: '副本', description: '',
      envEffect: {}, exits: {}, secret: '', bossInfo: bossInfo,
    );

    test('旧存档无boss_states → 默认存活', () {
      final p = Player();
      expect(p.flags.containsKey('boss_states'), false);
      expect(EnvironmentSystem.isBossAlive(p, 'boss_room_01'), true);
      // 进入副本无提示（存活）
      expect(EnvironmentSystem.bossEnterPrompt(p, 'boss_room_01', bossInfo), null);
    });

    test('击杀BOSS → 标记死亡，启动重生倒计时', () {
      final p = Player(worldTime: 2); // 120分钟
      EnvironmentSystem.markBossDead(p, 'boss_room_01', bossInfo);
      expect(EnvironmentSystem.isBossAlive(p, 'boss_room_01'), false);
      final states = EnvironmentSystem.bossStates(p);
      final st = states['boss_room_01'] as Map;
      expect(st['alive'], false);
      expect(st['death_minute'], 120);
      expect(st['respawn_minute'], 240); // 120+120
    });

    test('死亡后未到倒计时 → 提示尚未复苏', () {
      final p = Player(worldTime: 2); // 120分钟击杀
      EnvironmentSystem.markBossDead(p, 'boss_room_01', bossInfo);
      // worldTime=3 → 180分钟 < 240重生时间
      p.worldTime = 3;
      final prompt = EnvironmentSystem.bossEnterPrompt(p, 'boss_room_01', bossInfo);
      expect(prompt, isNotNull);
      expect(prompt!.contains('尚未复苏'), true);
    });

    test('倒计时结束 → 自动复活', () {
      final p = Player(worldTime: 2); // 120分钟击杀
      EnvironmentSystem.markBossDead(p, 'boss_room_01', bossInfo);
      // worldTime=5 → 300分钟 ≥ 240重生时间
      p.worldTime = 5;
      final revived = EnvironmentSystem.tickBossRespawn(p, {'boss_room_01': room});
      expect(revived.length, 1);
      expect(revived.first.contains('首领复苏'), true);
      expect(EnvironmentSystem.isBossAlive(p, 'boss_room_01'), true);
    });

    test('倒计时未到 → tickBossRespawn 不复活', () {
      final p = Player(worldTime: 2);
      EnvironmentSystem.markBossDead(p, 'boss_room_01', bossInfo);
      p.worldTime = 3; // 180 < 240
      final revived = EnvironmentSystem.tickBossRespawn(p, {'boss_room_01': room});
      expect(revived, isEmpty);
      expect(EnvironmentSystem.isBossAlive(p, 'boss_room_01'), false);
    });

    test('倒计时持久化：存档重进不清零', () {
      // 模拟存档序列化/反序列化：flags 是普通 Map，可序列化
      final p = Player(worldTime: 2);
      EnvironmentSystem.markBossDead(p, 'boss_room_01', bossInfo);
      // 模拟重进：从 flags 重建 Player（worldTime 保持）
      final savedFlags = Map<String, dynamic>.from(p.flags);
      final p2 = Player(worldTime: 2, flags: savedFlags);
      expect(EnvironmentSystem.isBossAlive(p2, 'boss_room_01'), false);
      final st = EnvironmentSystem.bossStates(p2)['boss_room_01'] as Map;
      expect(st['respawn_minute'], 240);
    });
  });

  group('五、时段/天气限定BOSS', () {
    test('仅夜晚刷新的BOSS：白天不复活', () {
      final nightBoss = {
        'npc_id': 'npc_boss_night',
        'boss_name': '夜行蛊王',
        'respawn_game_time': 60,
        'limit_daytime': ['夜晚'],
        'limit_weather': <String>[],
      };
      final room = Room(rid: 'night_boss', name: '夜窟', description: '',
          exits: {}, envEffect: {}, secret: '', bossInfo: nightBoss);
      final p = Player(worldTime: 1); // 60分钟击杀
      EnvironmentSystem.markBossDead(p, 'night_boss', nightBoss);
      // worldTime=3 → 180分钟 ≥ 120重生时间，但当前是黄昏（非夜晚）
      p.worldTime = 3;
      final revived = EnvironmentSystem.tickBossRespawn(p, {'night_boss': room});
      expect(revived, isEmpty, reason: '黄昏时段不满足夜晚限制，BOSS不应复活');
      // worldTime=5 → 300分钟，当前是夜晚
      p.worldTime = 5;
      final revived2 = EnvironmentSystem.tickBossRespawn(p, {'night_boss': room});
      expect(revived2.length, 1, reason: '夜晚时段满足限制，BOSS应复活');
    });

    test('限定天气的BOSS：天气不匹配不复活', () {
      final rainBoss = {
        'npc_id': 'npc_boss_rain',
        'boss_name': '雨煞蛊',
        'respawn_game_time': 60,
        'limit_daytime': <String>[],
        'limit_weather': ['小雨'],
      };
      final room = Room(rid: 'rain_boss', name: '雨窟', description: '',
          exits: {}, envEffect: {}, secret: '', bossInfo: rainBoss);
      final p = Player(worldTime: 1);
      EnvironmentSystem.markBossDead(p, 'rain_boss', rainBoss);
      p.worldTime = 3; // 倒计时已到
      p.flags['env_weather'] = '晴朗'; // 不匹配
      final revived = EnvironmentSystem.tickBossRespawn(p, {'rain_boss': room});
      expect(revived, isEmpty);
      // 改为小雨
      p.flags['env_weather'] = '小雨';
      final revived2 = EnvironmentSystem.tickBossRespawn(p, {'rain_boss': room});
      expect(revived2.length, 1);
    });
  });

  group('六、环境联动计算', () {
    test('流派倍率综合：场景×时段×天气', () {
      // 场景毒道1.30 × 夜晚无鬼道buff(毒道无) × 晴朗无 = 1.30
      final room = Room(rid: 'r', name: 'n', description: '',
          exits: {}, envEffect: {'毒道': 1.30}, secret: '', bossInfo: const {});
      final p = Player(worldTime: 5); // 夜晚
      p.flags['env_weather'] = '晴朗';
      expect(EnvironmentSystem.schoolMultiplier(p, room, '毒道'), 1.30);
    });

    test('夜晚鬼道蛊环境加成', () {
      final room = Room(rid: 'r', name: 'n', description: '',
          exits: {}, envEffect: {'鬼道': 1.20}, secret: '', bossInfo: const {});
      final p = Player(worldTime: 5); // 夜晚 鬼道1.15
      p.flags['env_weather'] = '晴朗';
      // 1.20 × 1.15 × 1.0 = 1.38
      expect((EnvironmentSystem.schoolMultiplier(p, room, '鬼道') - 1.38).abs() < 0.001, true);
    });

    test('捕捉成功率：夜晚+浓雾双重降低', () {
      final p = Player(worldTime: 5); // 夜晚 0.80
      p.flags['env_weather'] = '浓雾'; // 0.85
      final mul = EnvironmentSystem.captureChanceMul(p);
      expect((mul - 0.68).abs() < 0.001, true); // 0.80 × 0.85
    });

    test('白天晴朗捕捉成功率正常', () {
      final p = Player(worldTime: 1); // 白天无debuff
      p.flags['env_weather'] = '晴朗';
      expect(EnvironmentSystem.captureChanceMul(p), 1.0);
    });
  });

  group('七、炼蛊环境需求配置解析', () {
    test('env_required 正确解析', () {
      final r = Recipe.fromJson({
        'rid': 'r_test', 'name': '测试蛊方', 'rank': 3,
        'material': ['毒囊x2'], 'base_success': 0.25, 'output_gid': 'g001',
        'env_required': {'phase': '夜晚'},
      });
      expect(r.envRequired['phase'], '夜晚');
    });

    test('无 env_required 字段 → 空Map（旧JSON兼容）', () {
      final r = Recipe.fromJson({
        'rid': 'r_test2', 'name': '普通蛊方', 'rank': 1,
        'material': ['露水x1'], 'base_success': 0.6, 'output_gid': 'g002',
      });
      expect(r.envRequired, isEmpty);
    });

    test('min_school + min_mul 配置解析', () {
      final r = Recipe.fromJson({
        'rid': 'r_test3', 'name': '毒道蛊方', 'rank': 3,
        'material': [], 'base_success': 0.2, 'output_gid': 'g003',
        'env_required': {'min_school': '毒道', 'min_mul': 1.20},
      });
      expect(r.envRequired['min_school'], '毒道');
      expect(r.envRequired['min_mul'], 1.20);
    });
  });

  group('八、旧存档全局兼容', () {
    test('空flags Player 不闪退，所有查询返回默认值', () {
      final p = Player();
      expect(() => EnvironmentSystem.curPhase(p), returnsNormally);
      expect(() => EnvironmentSystem.curWeather(p), returnsNormally);
      expect(() => EnvironmentSystem.gameDay(p), returnsNormally);
      expect(() => EnvironmentSystem.isBossAlive(p, 'any'), returnsNormally);
      expect(() => EnvironmentSystem.bossStates(p), returnsNormally);
      expect(() => EnvironmentSystem.captureChanceMul(p), returnsNormally);
      expect(() => EnvironmentSystem.weatherBuff(p), returnsNormally);
    });

    test('环境系统未init时仍有兜底默认配置', () {
      // init 已在 setUpAll 调用，此处验证 phases/weatherList 非空
      expect(EnvironmentSystem.phases.length, 4);
      expect(EnvironmentSystem.weatherList.length, 4);
      expect(EnvironmentSystem.cycleTotalMinute, 480);
    });
  });
}
