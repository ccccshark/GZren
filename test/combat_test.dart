// combat_test.dart
// 回合制战斗引擎测试：开战、攻击、防御、逃亡、胜负、搜尸、天劫。
import 'package:flutter_test/flutter_test.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/gu_model.dart';
import 'package:gzren/data_model/npc_model.dart';
import 'package:gzren/engine/combat.dart';
import 'package:gzren/engine/gu_system.dart' show makeGuInstance;

Map<String, GuTemplate> _guList() => {
  'g002': GuTemplate(
    gid: 'g002', name: '青茅蛊', rank: 1, school: '气道',
    costZhen: 4, durabilityMax: 100,
    combat: {'type': 'attack', 'power': 12},
  ),
  'g005': GuTemplate(
    gid: 'g005', name: '玉皮蛊', rank: 2, school: '气道',
    costZhen: 10, durabilityMax: 120,
    combat: {'type': 'defense', 'power': 30},
  ),
  'g019': GuTemplate(
    gid: 'g019', name: '草人蛊', rank: 2, school: '气道',
    costZhen: 10, durabilityMax: 90,
    combat: {'type': 'substitute', 'power': 0},
  ),
};

NpcTemplate _weakBeast() => NpcTemplate(
  nid: 'b1', name: '小野猪', level: '一转初阶',
  physique: 10, trueyuan: 50, trueyuanMax: 50,
  guInSlot: ['g002'], isHostile: true, isBeast: true,
  inventory: ['野草露水x2'],
);

void main() {
  late CombatEngine engine;

  setUp(() {
    engine = CombatEngine(_guList());
  });

  group('startCombat', () {
    test('初始化战斗状态', () {
      final p = Player(level: '一转初阶', trueyuan: 100, physique: 50);
      final npc = Npc.fromTemplate(_weakBeast());
      final s = engine.startCombat(p, npc, {});
      expect(s.status, CombatStatus.ongoing);
      expect(s.round, 0);
      expect(s.npcHpMax, npc.physique);
      expect(s.playerPoison, 0);
      expect(s.npcPoison, 0);
      expect(s.log.first, contains('战斗开始'));
      // NPC 蛊物化
      expect(npc.combatGus.length, 1);
      expect(npc.combatGus.first.gid, 'g002');
    });
  });

  group('playerAction 攻击', () {
    test('攻击扣减敌人血量并扣自身真元与蛊耐久', () {
      final p = Player(level: '一转初阶', trueyuan: 100, physique: 50);
      final g = makeGuInstance('g002', _guList());
      p.guInSlot.add(g);
      final npc = Npc.fromTemplate(_weakBeast());
      var s = engine.startCombat(p, npc, {});
      final npcBefore = npc.physique;
      final trueyuanBefore = p.trueyuan;
      final durBefore = g.durability;
      s = engine.playerAction(s, 'attack');
      expect(npc.physique, lessThan(npcBefore));
      expect(p.trueyuan, lessThan(trueyuanBefore));
      expect(g.durability, lessThan(durBefore));
      expect(s.round, 1);
    });

    test('无攻击蛊时强制防御', () {
      final p = Player(level: '一转初阶', trueyuan: 100, physique: 50);
      final npc = Npc.fromTemplate(_weakBeast());
      var s = engine.startCombat(p, npc, {});
      s = engine.playerAction(s, 'attack');
      expect(s.log.any((l) => l.contains('没有可用的攻击蛊') || l.contains('防御')), true);
    });

    test('真元不足无法催动攻击蛊', () {
      final p = Player(level: '一转初阶', trueyuan: 1, physique: 50);
      p.guInSlot.add(makeGuInstance('g002', _guList()));
      final npc = Npc.fromTemplate(_weakBeast());
      var s = engine.startCombat(p, npc, {});
      s = engine.playerAction(s, 'attack');
      expect(s.log.any((l) => l.contains('真元不足')), true);
    });

    test('蛊耐久耗尽无法催动', () {
      final p = Player(level: '一转初阶', trueyuan: 100, physique: 50);
      final g = makeGuInstance('g002', _guList());
      g.durability = 0;
      p.guInSlot.add(g);
      final npc = Npc.fromTemplate(_weakBeast());
      var s = engine.startCombat(p, npc, {});
      s = engine.playerAction(s, 'attack');
      expect(s.log.any((l) => l.contains('耐久耗尽')), true);
    });

    test('击杀敌人触发胜利并搜尸', () {
      final p = Player(level: '一转初阶', trueyuan: 1000, physique: 1000);
      p.guInSlot.add(makeGuInstance('g002', _guList()));
      // 弱到一击必杀
      final beast = NpcTemplate(
        nid: 'b', name: '雏蛊', level: '一转初阶',
        physique: 1, trueyuan: 1, trueyuanMax: 1,
        guInSlot: [], isHostile: true, isBeast: true,
        inventory: ['野草露水x3'],
      );
      final npc = Npc.fromTemplate(beast);
      var s = engine.startCombat(p, npc, {});
      s = engine.playerAction(s, 'attack');
      expect(s.status, CombatStatus.win);
      expect(s.npc.physique, 0);
      expect(s.log.any((l) => l.contains('击败')), true);
      expect(s.log.any((l) => l.contains('搜查')), true);
      // 搜尸：物资转入玩家背包
      expect(p.inventory.any((i) => i.contains('野草露水')), true);
      expect(p.kills, 1);
      // 击杀累积劫数
      expect(p.tribulation, 5);
    });
  });

  group('playerAction 防御与逃亡', () {
    test('defend 不攻击仅防御', () {
      final p = Player(level: '一转初阶', trueyuan: 100, physique: 50);
      final npc = Npc.fromTemplate(_weakBeast());
      var s = engine.startCombat(p, npc, {});
      s = engine.playerAction(s, 'defend');
      expect(s.log.any((l) => l.contains('防御蛊护体')), true);
    });

    test('逃亡成功结束战斗状态 flee', () {
      final p = Player(level: '九转初阶', trueyuan: 1000, physique: 1000, luck: 100);
      final npc = Npc.fromTemplate(_weakBeast());
      var s = engine.startCombat(p, npc, {});
      // 高境界高气运，应能逃走
      bool fled = false;
      for (var i = 0; i < 50 && !fled; i++) {
        s = engine.startCombat(p, npc, {});
        s = engine.playerAction(s, 'flee');
        if (s.status == CombatStatus.flee) fled = true;
      }
      expect(fled, true, reason: '九转打一转，逃亡概率应极高');
    });
  });

  group('替身蛊保命', () {
    test('致命一击由替身蛊挡下且蛊损毁', () {
      final p = Player(level: '一转初阶', trueyuan: 1000, physique: 5);
      p.guInSlot.add(makeGuInstance('g019', _guList())); // 替身蛊
      // 强力异兽一击致命
      final beast = NpcTemplate(
        nid: 'b', name: '魔神', level: '九转巅峰',
        physique: 9999, trueyuan: 9999, trueyuanMax: 9999,
        guInSlot: ['g002'], isHostile: true, isBeast: true,
      );
      final npc = Npc.fromTemplate(beast);
      var s = engine.startCombat(p, npc, {});
      s = engine.playerAction(s, 'defend'); // 触发 NPC 攻击
      // 替身蛊应挡下
      expect(p.physique, greaterThan(0));
      expect(p.guInSlot.where((g) => g.gid == 'g019').length, 0);
      expect(p.guBag.any((g) => g.gid == 'g019' && g.durability == 0), true);
      expect(s.log.any((l) => l.contains('替身')), true);
    });
  });

  group('天劫渡劫', () {
    test('startTribulation 按境界确定轮数', () {
      final p = Player(level: '三转初阶');
      final t = engine.startTribulation(p);
      expect(t.rank, 3);
      expect(t.totalRounds, 3 + 3); // 3 + rank
      expect(t.survived, true);
      expect(t.finished, false);
      expect(t.log.first, contains('天劫降临'));
    });

    test('撑过全部轮次渡劫成功，体魄魂力气运增长', () {
      final p = Player(level: '一转初阶', physique: 1000, trueyuan: 1000);
      final defense = makeGuInstance('g005', _guList());
      p.guInSlot.add(defense);
      var t = engine.startTribulation(p);
      // 一转 4 轮
      final rounds = t.totalRounds;
      final physBefore = p.physique;
      final soulBefore = p.soulPower;
      final luckBefore = p.luck;
      for (var i = 0; i < rounds; i++) {
        t = engine.tribulationAction(t, 'defend');
        if (t.finished) break;
      }
      expect(t.finished, true);
      expect(t.survived, true);
      expect(p.physique, greaterThan(physBefore));
      expect(p.soulPower, greaterThan(soulBefore));
      expect(p.luck, greaterThan(luckBefore));
      expect(t.log.any((l) => l.contains('渡劫成功')), true);
    });

    test('天劫致死则渡劫失败', () {
      final p = Player(level: '九转初阶', physique: 1); // 高转天劫伤害高，1血必死
      var t = engine.startTribulation(p);
      t = engine.tribulationAction(t, 'defend');
      expect(t.finished, true);
      expect(t.survived, false);
      expect(p.alive, false);
      expect(t.log.any((l) => l.contains('渡劫失败')), true);
    });

    test('替身蛊在天劫中也生效', () {
      final p = Player(level: '九转初阶', physique: 1);
      p.guInSlot.add(makeGuInstance('g019', _guList()));
      var t = engine.startTribulation(p);
      t = engine.tribulationAction(t, 'defend');
      // 替身挡下，未死亡
      expect(p.guInSlot.where((g) => g.gid == 'g019').length, 0);
      expect(t.log.any((l) => l.contains('替身')), true);
    });
  });
}
