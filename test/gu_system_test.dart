// gu_system_test.dart
// 蛊虫系统逻辑测试：材料管理、捕捉、炼蛊、装备、催动。
import 'package:flutter_test/flutter_test.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/gu_model.dart';
import 'package:gzren/data_model/scene_model.dart';
import 'package:gzren/data_model/recipe_model.dart';
import 'package:gzren/engine/gu_system.dart' as gu;
import 'package:gzren/engine/player_core.dart' show levelRank;

// 测试用蛊虫模板表
Map<String, GuTemplate> _guList() => {
  'g002': GuTemplate(
    gid: 'g002', name: '青茅蛊', rank: 1, school: '气道',
    costZhen: 4, durabilityMax: 100,
    feedMaterial: ['青茅草根'], sideEffect: '无',
    combat: {'type': 'attack', 'power': 12},
  ),
  'g005': GuTemplate(
    gid: 'g005', name: '玉皮蛊', rank: 2, school: '气道',
    costZhen: 10, durabilityMax: 120,
    feedMaterial: ['玉髓'], sideEffect: '迟缓',
    combat: {'type': 'defense', 'power': 30},
  ),
  'g014': GuTemplate(
    gid: 'g014', name: '疗伤蛊', rank: 2, school: '气道',
    costZhen: 13, durabilityMax: 100,
    feedMaterial: ['野草露水'], sideEffect: '无',
    combat: {'type': 'heal_body', 'power': 25},
  ),
  'g015': GuTemplate(
    gid: 'g015', name: '空窍蛊', rank: 1, school: '气道',
    costZhen: 0, durabilityMax: 999,
    feedMaterial: ['露水'], sideEffect: '无',
    combat: {'type': 'passive', 'power': 0},
  ),
  'g017': GuTemplate(
    gid: 'g017', name: '春蝉蛊', rank: 6, school: '岁月道',
    costZhen: 80, costLife: 1, durabilityMax: 30,
    feedMaterial: ['寿桃'], sideEffect: '消耗寿元',
    combat: {'type': 'time_reversal', 'power': 0},
  ),
  'g019': GuTemplate(
    gid: 'g019', name: '草人蛊', rank: 2, school: '气道',
    costZhen: 10, durabilityMax: 90,
    feedMaterial: ['青茅草根'], sideEffect: '替死后损毁',
    combat: {'type': 'substitute', 'power': 0},
  ),
};

Recipe _recipe(String name, int rank, List<String> mat, double succ, String outGid) =>
    Recipe(rid: 'r', name: name, rank: rank, material: mat, baseSuccess: succ, outputGid: outGid);

void main() {
  group('makeGuInstance', () {
    test('正常生成实例，复制模板字段', () {
      final list = _guList();
      final inst = gu.makeGuInstance('g002', list);
      expect(inst.gid, 'g002');
      expect(inst.name, '青茅蛊');
      expect(inst.rank, 1);
      expect(inst.durability, 100);
      expect(inst.durabilityMax, 100);
      expect(inst.combat['power'], 12);
      expect(inst.mutated, false);
    });

    test('变异蛊威力提升 1.4 倍且改名带前缀', () {
      final list = _guList();
      final inst = gu.makeGuInstance('g002', list, mutated: true);
      expect(inst.mutated, true);
      expect(inst.name, '变异·青茅蛊');
      expect(inst.combat['power'], (12 * 1.4).toInt());
      expect(inst.sideEffect, contains('变异反噬'));
    });

    test('未知 gid 返回兜底实例不抛异常', () {
      final inst = gu.makeGuInstance('unknown', _guList());
      expect(inst.name, '未知蛊');
      expect(inst.rank, 1);
    });
  });

  group('材料管理', () {
    test('addMaterial 累加同种材料', () {
      final p = Player();
      gu.addMaterial(p, '露水', 3);
      gu.addMaterial(p, '露水', 2);
      expect(p.inventory, ['露水x5']);
    });

    test('addMaterial 单个不附数量后缀', () {
      final p = Player();
      gu.addMaterial(p, '原石', 1);
      expect(p.inventory, ['原石']);
    });

    test('countMaterial 跨多格统计', () {
      final p = Player(inventory: ['露水x3', '青茅草根', '露水x2']);
      expect(gu.countMaterial(p, '露水'), 5);
      expect(gu.countMaterial(p, '青茅草根'), 1);
      expect(gu.countMaterial(p, '玉髓'), 0);
    });

    test('hasMaterial 判定', () {
      final p = Player(inventory: ['露水x3']);
      expect(gu.hasMaterial(p, '露水', 3), true);
      expect(gu.hasMaterial(p, '露水', 4), false);
    });

    test('consumeMaterial 部分扣除保留剩余', () {
      final p = Player(inventory: ['露水x5']);
      final ok = gu.consumeMaterial(p, '露水', 2);
      expect(ok, true);
      expect(p.inventory, ['露水x3']);
    });

    test('consumeMaterial 整格扣除', () {
      final p = Player(inventory: ['露水x2', '青茅草根']);
      final ok = gu.consumeMaterial(p, '露水', 2);
      expect(ok, true);
      expect(p.inventory, ['青茅草根']);
    });

    test('consumeMaterial 跨格扣除', () {
      final p = Player(inventory: ['露水x2', '露水x3']);
      final ok = gu.consumeMaterial(p, '露水', 4);
      expect(ok, true);
      expect(gu.countMaterial(p, '露水'), 1);
    });

    test('consumeMaterial 不足返回 false 且不修改背包', () {
      final p = Player(inventory: ['露水x2']);
      final ok = gu.consumeMaterial(p, '露水', 5);
      expect(ok, false);
      expect(p.inventory, ['露水x2']);
    });
  });

  group('capture 捕捉', () {
    test('场景无此野蛊返回失败日志', () {
      final room = Room(rid: 'r', name: 'r', description: '', wildGu: []);
      final log = gu.capture(Player(), 'g002', _guList(), room);
      expect(log.any((s) => s.contains('没有这种野生蛊虫')), true);
    });

    test('境界不足无法捕捉高转蛊', () {
      final room = Room(rid: 'r', name: 'r', description: '', wildGu: ['g017']);
      final p = Player(level: '一转初阶', trueyuan: 1000);
      final log = gu.capture(p, 'g017', _guList(), room);
      expect(log.any((s) => s.contains('境界高于你')), true);
      expect(p.guBag, isEmpty);
    });

    test('真元不足返回失败', () {
      final room = Room(rid: 'r', name: 'r', description: '', wildGu: ['g002']);
      final p = Player(level: '一转初阶', trueyuan: 1);
      final log = gu.capture(p, 'g002', _guList(), room);
      expect(log.any((s) => s.contains('真元不足')), true);
    });

    test('捕捉成功则背包获得实例且野蛊被移除', () {
      final list = _guList();
      final room = Room(rid: 'r', name: 'r', description: '', wildGu: ['g002']);
      // 用足够真元多次尝试直至成功
      bool caught = false;
      for (var i = 0; i < 200 && !caught; i++) {
        final p = Player(level: '一转初阶', trueyuan: 1000);
        final log = gu.capture(p, 'g002', list, room);
        if (p.guBag.isNotEmpty) {
          caught = true;
          expect(p.guBag.first.gid, 'g002');
          expect(log.any((s) => s.contains('捕捉成功')), true);
        }
      }
      expect(caught, true, reason: '概率事件应在 200 次内至少成功一次');
    });
  });

  group('refine 炼蛊', () {
    test('不存在蛊方返回失败', () {
      final p = Player();
      final log = gu.refine(p, '不存在的蛊方', [], _guList());
      expect(log.any((s) => s.contains('不存在蛊方')), true);
    });

    test('未持有蛊方返回失败', () {
      final list = _guList();
      final recipes = [_recipe('青茅蛊蛊方', 1, ['青茅草根x2'], 0.7, 'g002')];
      final p = Player();
      final log = gu.refine(p, '青茅蛊蛊方', recipes, list);
      expect(log.any((s) => s.contains('未持有')), true);
    });

    test('蛊材不足返回失败且不消耗蛊方', () {
      final list = _guList();
      final recipes = [_recipe('青茅蛊蛊方', 1, ['青茅草根x2'], 0.7, 'g002')];
      final p = Player(inventory: ['青茅草根x1']);
      p.inventory.add('青茅蛊蛊方');
      final log = gu.refine(p, '青茅蛊蛊方', recipes, list);
      expect(log.any((s) => s.contains('蛊材不足')), true);
      expect(p.inventory.contains('青茅蛊蛊方'), true);
    });

    test('成功率 1.0 必定成功产出蛊虫并消耗材料', () {
      final list = _guList();
      final recipes = [_recipe('青茅蛊蛊方', 1, ['青茅草根x2'], 1.0, 'g002')];
      final p = Player(inventory: ['青茅草根x5']);
      p.inventory.add('青茅蛊蛊方');
      final log = gu.refine(p, '青茅蛊蛊方', recipes, list);
      expect(p.guBag.length, 1);
      expect(p.guBag.first.gid, 'g002');
      expect(gu.countMaterial(p, '青茅草根'), 3);
      expect(log.any((s) => s.contains('炼蛊成功')), true);
    });

    test('成功率 0.0 必定失败且不产出蛊虫', () {
      final list = _guList();
      final recipes = [_recipe('青茅蛊蛊方', 1, ['青茅草根x2'], 0.0, 'g002')];
      final p = Player(inventory: ['青茅草根x5']);
      p.inventory.add('青茅蛊蛊方');
      final log = gu.refine(p, '青茅蛊蛊方', recipes, list);
      expect(p.guBag, isEmpty);
      expect(log.any((s) => s.contains('炼蛊失败')), true);
      expect(gu.countMaterial(p, '青茅草根'), 3);
    });
  });

  group('feed 投喂', () {
    test('无此蛊返回失败', () {
      final log = gu.feed(Player(), '不存在', '露水');
      expect(log.any((s) => s.contains('未拥有')), true);
    });

    test('蛊不吃该材料返回失败', () {
      final list = _guList();
      final p = Player();
      p.guBag.add(gu.makeGuInstance('g002', list));
      final log = gu.feed(p, '青茅蛊', '玉髓');
      expect(log.any((s) => s.contains('不吃')), true);
    });

    test('投喂成功恢复耐久', () {
      final list = _guList();
      final p = Player(inventory: ['青茅草根x5']);
      final inst = gu.makeGuInstance('g002', list);
      inst.durability = 50;
      p.guBag.add(inst);
      final log = gu.feed(p, '青茅蛊', '青茅草根');
      expect(inst.durability, 80); // 50 + 30
      expect(gu.countMaterial(p, '青茅草根'), 4);
      expect(log.any((s) => s.contains('耐久恢复')), true);
    });

    test('耐久不超过 max', () {
      final list = _guList();
      final p = Player(inventory: ['青茅草根x5']);
      final inst = gu.makeGuInstance('g002', list);
      inst.durability = 90;
      p.guBag.add(inst);
      gu.feed(p, '青茅蛊', '青茅草根');
      expect(inst.durability, 100);
    });
  });

  group('equip / unequip', () {
    test('空窍满时无法装备', () {
      final list = _guList();
      final p = Player(slotMax: 1, slotBonus: 0);
      p.guInSlot.add(gu.makeGuInstance('g002', list));
      p.guBag.add(gu.makeGuInstance('g014', list));
      final log = gu.equip(p, '疗伤蛊');
      expect(log.any((s) => s.contains('空窍已满')), true);
      expect(p.guInSlot.length, 1);
    });

    test('装备后从背包移入空窍', () {
      final list = _guList();
      final p = Player(slotMax: 3);
      p.guBag.add(gu.makeGuInstance('g002', list));
      final log = gu.equip(p, '青茅蛊');
      expect(p.guInSlot.length, 1);
      expect(p.guBag, isEmpty);
      expect(p.freeSlotCount, 2);
      expect(log.any((s) => s.contains('安入空窍')), true);
    });

    test('空窍蛊装备后增加蛊槽上限', () {
      final list = _guList();
      final p = Player(slotMax: 3, slotBonus: 0);
      p.guBag.add(gu.makeGuInstance('g015', list));
      final log = gu.equip(p, '空窍蛊');
      expect(p.slotBonus, 1);
      expect(p.effectiveSlotMax, 4);
      expect(log.any((s) => s.contains('蛊槽上限')), true);
    });

    test('取出空窍蛊恢复蛊槽上限', () {
      final list = _guList();
      final p = Player(slotMax: 3, slotBonus: 0);
      final inst = gu.makeGuInstance('g015', list);
      p.guBag.add(inst);
      gu.equip(p, '空窍蛊');
      expect(p.slotBonus, 1);
      gu.unequip(p, '空窍蛊');
      expect(p.slotBonus, 0);
      expect(p.guInSlot, isEmpty);
    });

    test('unequip 空窍无此蛊返回失败', () {
      final log = gu.unequip(Player(), '不存在');
      expect(log.any((s) => s.contains('空窍中没有')), true);
    });
  });

  group('useGu 非战斗催动', () {
    test('空窍无此蛊提示需先装备', () {
      final log = gu.useGu(Player(), '青茅蛊');
      expect(log.any((s) => s.contains('空窍中没有')), true);
    });

    test('耐久耗尽无法催动', () {
      final list = _guList();
      final p = Player(trueyuan: 1000);
      final inst = gu.makeGuInstance('g014', list);
      inst.durability = 0;
      p.guInSlot.add(inst);
      final log = gu.useGu(p, '疗伤蛊');
      expect(log.any((s) => s.contains('耐久耗尽')), true);
    });

    test('真元不足无法催动', () {
      final list = _guList();
      final p = Player(trueyuan: 1);
      p.guInSlot.add(gu.makeGuInstance('g014', list));
      final log = gu.useGu(p, '疗伤蛊');
      expect(log.any((s) => s.contains('真元不足')), true);
    });

    test('疗伤蛊催动恢复体魄并扣耐久与真元', () {
      final list = _guList();
      final p = Player(physique: 50, trueyuan: 100);
      p.guInSlot.add(gu.makeGuInstance('g014', list));
      final beforeDur = p.guInSlot.first.durability;
      final log = gu.useGu(p, '疗伤蛊');
      expect(p.physique, 75); // 50 + 25
      expect(p.trueyuan, 100 - 13);
      expect(p.guInSlot.first.durability, beforeDur - 2);
      expect(log.any((s) => s.contains('体魄恢复')), true);
    });

    test('春蝉蛊催动增加炼蛊造诣但耗寿增劫', () {
      final list = _guList();
      final p = Player(level: '六转初阶', trueyuan: 1000, lifeLeft: 100, lifeMax: 100);
      p.guInSlot.add(gu.makeGuInstance('g017', list));
      final log = gu.useGu(p, '春蝉蛊');
      expect(p.lifeLeft, 99);
      expect(p.refineProficiency, 5);
      expect(p.tribulation, 80);
      expect(log.any((s) => s.contains('岁月逆流')), true);
    });
  });

  group('levelRank 集成', () {
    test('一转~九转识别', () {
      expect(levelRank('一转初阶'), 1);
      expect(levelRank('三转中阶'), 3);
      expect(levelRank('九转巅峰'), 9);
    });
  });
}
