// player_core_test.dart
// 玩家核心逻辑测试：境界、蛊槽、寿元基准、道痕冲突、突破。
import 'package:flutter_test/flutter_test.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/engine/player_core.dart';

void main() {
  group('levelRank 境界识别', () {
    test('一~九转准确识别', () {
      expect(levelRank('一转初阶'), 1);
      expect(levelRank('二转巅峰'), 2);
      expect(levelRank('五转中阶'), 5);
      expect(levelRank('九转巅峰'), 9);
    });
    test('未知境界默认 1', () {
      expect(levelRank('???'), 1);
    });
  });

  group('lifespanBase 寿元基准', () {
    test('一转 80 年', () => expect(lifespanBase('一转初阶'), 80));
    test('三转 300 年', () => expect(lifespanBase('三转高阶'), 300));
    test('九转近乎无尽', () => expect(lifespanBase('九转巅峰'), 999999));
    test('返回 double 类型', () {
      expect(lifespanBase('一转初阶'), isA<double>());
    });
  });

  group('levelSlot 蛊槽表', () {
    test('一转 3 槽', () => expect(levelSlot['一转初阶'], 3));
    test('五转 7 槽', () => expect(levelSlot['五转中阶'], 7));
    test('九转 11 槽', () => expect(levelSlot['九转巅峰'], 11));
  });

  group('canBreakthrough 是否可突破', () {
    test('一转初阶可突破', () => expect(canBreakthrough(Player(level: '一转初阶')), true));
    test('九转巅峰不可突破', () => expect(canBreakthrough(Player(level: '九转巅峰')), false));
  });

  group('breakthrough 境界突破', () {
    test('一转初阶→一转中阶（同转内）', () {
      final p = Player(level: '一转初阶');
      final log = breakthrough(p);
      expect(p.level, '一转中阶');
      expect(p.slotMax, 3); // 同转蛊槽不变
      expect(log.any((s) => s.contains('突破')), true);
    });

    test('一转巅峰→二转初阶（跨转）蛊槽+1', () {
      final p = Player(level: '一转巅峰', trueyuan: 50, trueyuanMax: 100);
      breakthrough(p);
      expect(p.level, '二转初阶');
      expect(p.slotMax, 4);
      // 跨转重置寿元为 150
      expect(p.lifeMax, 150);
      expect(p.lifeLeft, 150);
      // 跨转真元上限+50 且满
      expect(p.trueyuanMax, 150);
      expect(p.trueyuan, 150);
      // 体魄魂力+15
      expect(p.physique, 30 + 15);
      expect(p.soulPower, 30 + 15);
    });

    test('突破累积劫数 +30', () {
      final p = Player(level: '一转初阶', tribulation: 0);
      breakthrough(p);
      expect(p.tribulation, 30);
    });

    test('九转巅峰不可突破', () {
      final p = Player(level: '九转巅峰');
      final log = breakthrough(p);
      expect(p.level, '九转巅峰');
      expect(log.first, contains('九转巅峰'));
    });
  });

  group('daoConflictDamage 道痕冲突', () {
    test('无冲突返回 0', () {
      final p = Player(daoMark: {'气道': 10});
      expect(daoConflictDamage(p), 0);
    });

    test('气道 vs 血道 冲突产生道伤', () {
      final p = Player(daoMark: {'气道': 20, '血道': 10});
      // (20 + 10) * 0.02 = 0.6
      expect(daoConflictDamage(p), closeTo(0.6, 1e-9));
    });

    test('寿道 vs 岁月道 冲突产生道伤', () {
      final p = Player(daoMark: {'寿道': 50, '岁月道': 50});
      expect(daoConflictDamage(p), closeTo(2.0, 1e-9));
    });

    test('多对冲突累加', () {
      final p = Player(daoMark: {'气道': 10, '血道': 10, '月道': 10, '毒道': 10});
      // 两对冲突，各 0.4，合计 0.8
      expect(daoConflictDamage(p), closeTo(0.8, 1e-9));
    });

    test('单边有道痕不算冲突', () {
      final p = Player(daoMark: {'气道': 10}); // 缺血道
      expect(daoConflictDamage(p), 0);
    });
  });
}
