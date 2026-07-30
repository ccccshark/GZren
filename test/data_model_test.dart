// data_model_test.dart
// 数据模型 fromJson/toJson 往返测试，确保存档读写一致。
import 'package:flutter_test/flutter_test.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/gu_model.dart';
import 'package:gzren/data_model/npc_model.dart';
import 'package:gzren/data_model/scene_model.dart';
import 'package:gzren/data_model/recipe_model.dart';

void main() {
  group('GuTemplate / GuInstance', () {
    test('GuTemplate.fromJson 读取基本字段', () {
      final t = GuTemplate.fromJson({
        'gid': 'g002', 'name': '青茅蛊', 'rank': 1, 'school': '气道',
        'cost_zhen': 4, 'cost_life': 0, 'durability_max': 100,
        'feed_material': ['青茅草根'], 'side_effect': '无明显副作用',
        'desc': '草刃攻击', 'evolve_gid': 'g010', 'habitat': ['青茅山'],
        'combat': {'type': 'attack', 'power': 12},
      });
      expect(t.gid, 'g002');
      expect(t.name, '青茅蛊');
      expect(t.rank, 1);
      expect(t.feedMaterial, ['青茅草根']);
      expect(t.combat['power'], 12);
    });

    test('GuInstance.toJson/fromJson 往返一致', () {
      final inst = GuInstance(
        instId: 'abc', gid: 'g002', name: '青茅蛊', rank: 1, school: '气道',
        costZhen: 4, durabilityMax: 100, durability: 80, mutated: false,
        feedMaterial: ['青茅草根'],
        combat: {'type': 'attack', 'power': 12},
      );
      final j = inst.toJson();
      final back = GuInstance.fromJson(j);
      expect(back.instId, inst.instId);
      expect(back.gid, inst.gid);
      expect(back.name, inst.name);
      expect(back.durability, inst.durability);
      expect(back.mutated, inst.mutated);
      expect(back.combat['power'], 12);
    });

    test('缺失字段时使用默认值', () {
      final back = GuInstance.fromJson({'gid': 'gxxx'});
      expect(back.gid, 'gxxx');
      expect(back.rank, 1);
      expect(back.school, '气道');
      expect(back.durability, 100);
      expect(back.mutated, false);
    });
  });

  group('Player', () {
    test('toJson/fromJson 往返一致', () {
      final p = Player(
        name: '方源', align: '魔道', level: '三转初阶',
        slotMax: 5, slotBonus: 1,
        trueyuan: 80, trueyuanMax: 100,
        lifeLeft: 250, lifeMax: 300, physique: 60, soulPower: 40, luck: 15,
        location: 'qingmao_02',
        inventory: ['露水x3', '青茅草根x2'],
        injure: ['轻伤'],
        daoMark: {'气道': 10, '毒道': 5},
        worldTime: 1440,
        refineProficiency: 3.5,
        tribulation: 30,
        kills: 2,
      );
      final j = p.toJson();
      final back = Player.fromJson(j);
      expect(back.name, '方源');
      expect(back.align, '魔道');
      expect(back.level, '三转初阶');
      expect(back.slotMax, 5);
      expect(back.slotBonus, 1);
      expect(back.effectiveSlotMax, 6);
      expect(back.lifeLeft, 250);
      expect(back.lifeMax, 300);
      expect(back.inventory, ['露水x3', '青茅草根x2']);
      expect(back.injure, ['轻伤']);
      expect(back.daoMark['气道'], 10);
      expect(back.worldTime, 1440);
      expect(back.refineProficiency, 3.5);
      expect(back.kills, 2);
    });

    test('spendTrueyuan / recoverTrueyuan 不越界', () {
      final p = Player(trueyuan: 50, trueyuanMax: 100);
      p.spendTrueyuan(80);
      expect(p.trueyuan, 0); // 不为负
      p.recoverTrueyuan(200);
      expect(p.trueyuan, 100); // 不超过 max
    });

    test('addDaoMark 累加 / addInjure 去重', () {
      final p = Player();
      p.addDaoMark('气道', 5);
      p.addDaoMark('气道', 3);
      expect(p.daoMark['气道'], 8);
      p.addInjure('轻伤');
      p.addInjure('轻伤');
      expect(p.injure.where((x) => x == '轻伤').length, 1);
    });

    test('fromJson 缺字段使用默认值', () {
      final back = Player.fromJson({});
      expect(back.name, '无名蛊师');
      expect(back.align, '中立');
      expect(back.level, '一转初阶');
      expect(back.alive, true);
      expect(back.inventory, isEmpty);
    });
  });

  group('NpcTemplate / Npc', () {
    test('NpcTemplate.fromJson 读取字段', () {
      final t = NpcTemplate.fromJson({
        'nid': 'npc_trader_lao', 'name': '老槐翁', 'align': '中立', 'level': '三转中阶',
        'life_left': 120, 'trueyuan': 200, 'trueyuan_max': 200,
        'physique': 80, 'soul_power': 60, 'slot_max': 5,
        'gu_in_slot': ['g005', 'g007'],
        'dao_mark': {'气道': 30},
        'inventory': ['露水x10'],
        'is_hostile': false, 'is_merchant': true, 'is_beast': false,
        'dialogue': ['你好'],
        'trade_goods': {'露水': 1, '月光石': 8},
      });
      expect(t.nid, 'npc_trader_lao');
      expect(t.isMerchant, true);
      expect(t.tradeGoods['月光石'], 8);
      expect(t.guInSlot, ['g005', 'g007']);
    });

    test('Npc.fromTemplate 拷贝并保留原始快照用于重生', () {
      final t = NpcTemplate(
        nid: 'n1', name: '巨猿', level: '二转初阶',
        physique: 70, trueyuan: 80, trueyuanMax: 80,
        guInSlot: ['g018'], inventory: ['竹节x3'],
        isHostile: true, isBeast: true,
      );
      final n = Npc.fromTemplate(t);
      n.storeOriginals();
      n.physique = 0;
      n.alive = false;
      n.guInSlot.clear();
      n.inventory.clear();
      n.respawn();
      expect(n.alive, true);
      expect(n.physique, 70);
      expect(n.guInSlot, ['g018']);
      expect(n.inventory, ['竹节x3']);
    });

    test('Npc.toJson/fromJson 运行时状态往返', () {
      final t = NpcTemplate(nid: 'n1', name: '巨猿', physique: 70, trueyuan: 80, trueyuanMax: 80,
          guInSlot: ['g018'], inventory: ['竹节x3'], isHostile: true, isBeast: true);
      final n = Npc.fromTemplate(t);
      n.hatePlayer = 3;
      n.alive = false;
      n.deathTime = 12.0;
      final j = n.toJson();
      final n2 = Npc.fromTemplate(t);
      n2.fromJson(j);
      expect(n2.hatePlayer, 3);
      expect(n2.alive, false);
      expect(n2.deathTime, 12.0);
    });
  });

  group('Room', () {
    test('Room.fromJson 解析 exits/env/wild_gu/npc_list', () {
      final r = Room.fromJson({
        'rid': 'qingmao_01', 'name': '青茅山山脚',
        'description': '草木繁茂',
        'exits': {'north': 'qingmao_02', 'east': 'qingmao_village'},
        'env_effect': {'毒道': 1.05, '气道': 1.0},
        'refresh_resource': ['野草露水'],
        'wild_gu': ['g002', 'g004'],
        'npc_list': [],
        'secret': '',
      });
      expect(r.rid, 'qingmao_01');
      expect(r.exits['north'], 'qingmao_02');
      expect(r.envEffect['毒道'], 1.05);
      expect(r.wildGu, ['g002', 'g004']);
    });
  });

  group('Recipe / MatParser', () {
    test('Recipe.fromJson', () {
      final r = Recipe.fromJson({
        'rid': 'r002', 'name': '青茅蛊蛊方', 'rank': 1,
        'material': ['青茅草根x2', '野草露水x2'],
        'base_success': 0.70, 'output_gid': 'g002',
      });
      expect(r.name, '青茅蛊蛊方');
      expect(r.rank, 1);
      expect(r.material.length, 2);
      expect(r.outputGid, 'g002');
    });

    test('MatParser.parse 解析名称与数量', () {
      expect(MatParser.parse('露水x3'), ('露水', 3));
      expect(MatParser.parse('青茅草根'), ('青茅草根', 1));
      expect(MatParser.parse('原石x10'), ('原石', 10));
    });

    test('EvolveRecipe.fromJson', () {
      final e = EvolveRecipe.fromJson({
        'name': '青茅蛊→剑草蛊进化', 'base_gu': 'g002',
        'material': ['铁矿石x2'], 'output_gid': 'g010', 'base_success': 0.30,
      });
      expect(e.baseGu, 'g002');
      expect(e.outputGid, 'g010');
    });
  });
}
