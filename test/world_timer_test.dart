// world_timer_test.dart
// 世界时间推进、寿元流逝、天劫触发测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/engine/world_timer.dart';
import 'package:gzren/engine/player_core.dart' show lifespanBase;

void main() {
  late WorldTimer timer;
  setUp(() {
    timer = WorldTimer();
  });

  test('advance 推进世界时间', () {
    final p = Player(worldTime: 0);
    final log = <String>[];
    timer.advance(p, 10, log);
    expect(p.worldTime, 10);
  });

  test('寿元随时间流逝（1440 小时 = 1 年）', () {
    final p = Player(level: '一转初阶', lifeLeft: 80, lifeMax: 80, worldTime: 0);
    final log = <String>[];
    timer.advance(p, 1440, log);
    // 1 年流逝
    expect(p.lifeLeft, closeTo(79, 1e-9));
    expect(p.alive, true);
  });

  test('寿元归零角色死亡并输出日志', () {
    final p = Player(level: '一转初阶', lifeLeft: 0.5, lifeMax: 80, worldTime: 0);
    final log = <String>[];
    timer.advance(p, 1440, log); // 流逝 1 年
    expect(p.alive, false);
    expect(p.lifeLeft, 0);
    expect(log.any((s) => s.contains('寿元耗尽')), true);
  });

  test('死亡后不再推进时间', () {
    final p = Player(lifeLeft: 0, lifeMax: 80, alive: false);
    final log = <String>[];
    final events = timer.advance(p, 100, log);
    expect(events, isEmpty);
    expect(log, isEmpty);
  });

  test('魂伤加速寿元流逝 1.5 倍', () {
    final p = Player(level: '一转初阶', lifeLeft: 80, lifeMax: 80, worldTime: 0, injure: ['魂伤']);
    final log = <String>[];
    timer.advance(p, 1440, log); // 应流逝 1.5 年
    expect(p.lifeLeft, closeTo(78.5, 1e-9));
  });

  test('空窍损伤加速寿元流逝 1.3 倍', () {
    final p = Player(level: '一转初阶', lifeLeft: 80, lifeMax: 80, worldTime: 0, injure: ['空窍损伤']);
    final log = <String>[];
    timer.advance(p, 1440, log);
    expect(p.lifeLeft, closeTo(78.7, 1e-9));
  });

  test('天劫阈值满足时返回 tribulation 事件并清零劫数', () {
    // 一转阈值 100 + 1*60 = 160
    final p = Player(level: '一转初阶', tribulation: 160, lifeLeft: 80, lifeMax: 80, worldTime: 0);
    final log = <String>[];
    final events = timer.advance(p, 1, log);
    expect(events, contains('tribulation'));
    expect(p.tribulation, 0); // 触发后清零
    expect(timer.lastTribulationRank, 1);
  });

  test('天劫未达阈值不触发', () {
    final p = Player(level: '一转初阶', tribulation: 100, lifeLeft: 80, lifeMax: 80, worldTime: 0);
    final log = <String>[];
    final events = timer.advance(p, 1, log);
    expect(events, isEmpty);
    expect(p.tribulation, 100);
  });

  test('reduceTribulation 减少劫数且不为负', () {
    final p = Player(tribulation: 30);
    timer.reduceTribulation(p, 50);
    expect(p.tribulation, 0);
  });

  test('actionHours 常量包含核心动作', () {
    expect(actionHours['move'], 2);
    expect(actionHours['rest'], 12);
    expect(actionHours['gather'], 6);
    expect(actionHours['refine'], 8);
    expect(actionHours['capture'], 3);
    expect(actionHours['combat_end'], 4);
  });

  test('hoursPerYear = 1440', () {
    expect(hoursPerYear, 1440.0);
  });

  test('lifespanBase 与 world_timer 配合：九转寿元近乎无尽', () {
    expect(lifespanBase('九转初阶'), 999999);
  });
}
