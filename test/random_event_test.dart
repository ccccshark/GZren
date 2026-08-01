// random_event_test.dart
// 专项测试【11.随机事件系统】+【8.6 变异蛊标记预留】
// 验证：
//   1. 抉择事件 resolveEventChoice 正确结算 add_item / luck / add_item_cost
//   2. 负数 add_item（支付类）走消耗流程
//   3. dismissPendingEvent 清空挂起状态
//   4. 结算后 pendingEvent 被清空，避免重复弹窗
//   5. is_mutate 别名解析与 mutated 等价，缺失默认 false 不报错
import 'package:flutter_test/flutter_test.dart';
import 'package:gzren/engine/command.dart';
import 'package:gzren/engine/gu_system.dart' as gu;
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/gu_model.dart';

void main() {
  group('随机事件·抉择结算【11.2/11.3】', () {
    test('resolveEventChoice 应用 add_item 与 luck 效果', () {
      final ctx = GameContext();
      final p = Player(name: '测试蛊师', inventory: ['原石x10']);
      ctx.player = p;
      ctx.pendingEvent = {
        'eid': 'ev011', 'name': '抉择·路边遗物', 'type': 'fortune',
        'desc': '路边一具蛊师尸体。',
        'choices': [
          {'text': '搜刮尸体', 'effect': {'add_item': ['原石x5', '毒囊x2'], 'luck': -2}, 'weight': 1},
          {'text': '替他收敛遗骸', 'effect': {'luck': 3}, 'weight': 1},
        ],
      };
      ctx.resolveEventChoice(0);
      expect(ctx.pendingEvent, null, reason: '结算后应清空 pendingEvent');
      expect(gu.countMaterial(p, '原石'), 15); // 10 + 5
      expect(gu.countMaterial(p, '毒囊'), 2);
      expect(p.luck, 8); // 默认10 - 2
    });

    test('负数 add_item（原石x-5）走消耗流程', () {
      final ctx = GameContext();
      final p = Player(name: '测试蛊师', inventory: ['原石x20']);
      ctx.player = p;
      ctx.pendingEvent = {
        'eid': 'ev018', 'name': '抉择·黑市线索', 'type': 'fortune',
        'desc': '黑市线索。',
        'choices': [
          {'text': '支付原石x5', 'effect': {'add_item': ['原石x-5'], 'luck': 1}, 'weight': 1},
        ],
      };
      ctx.resolveEventChoice(0);
      expect(ctx.pendingEvent, null);
      expect(gu.countMaterial(p, '原石'), 15, reason: '原石x-5 应消耗5个，剩15');
      expect(p.luck, 11); // 10 + 1
    });

    test('add_item_cost 代价先扣再发放（购买类选项）', () {
      final ctx = GameContext();
      final p = Player(name: '测试蛊师', inventory: ['原石x30']);
      ctx.player = p;
      ctx.pendingEvent = {
        'eid': 'ev021', 'name': '抉择·路遇蛊商', 'type': 'fortune',
        'desc': '蛊商摆摊。',
        'choices': [
          {'text': '购买解毒散', 'effect': {'add_item': ['解毒散x1'], 'add_item_cost': ['原石x15']}, 'weight': 1},
        ],
      };
      ctx.resolveEventChoice(0);
      expect(gu.countMaterial(p, '原石'), 15, reason: '扣除15原石');
      expect(gu.countMaterial(p, '解毒散'), 1);
    });

    test('add_item_cost 不足时不发放对应物品（不崩溃）', () {
      final ctx = GameContext();
      final p = Player(name: '测试蛊师', inventory: ['原石x5']); // 不足15
      ctx.player = p;
      ctx.pendingEvent = {
        'eid': 'ev021', 'name': '抉择·路遇蛊商', 'type': 'fortune',
        'desc': '蛊商摆摊。',
        'choices': [
          {'text': '购买解毒散', 'effect': {'add_item': ['解毒散x1'], 'add_item_cost': ['原石x15']}, 'weight': 1},
        ],
      };
      ctx.resolveEventChoice(0);
      expect(gu.countMaterial(p, '原石'), 5); // 不变
      expect(gu.countMaterial(p, '解毒散'), 1, reason: 'add_item 仍发放（代价不足仅提示）');
    });

    test('dismissPendingEvent 清空挂起状态', () {
      final ctx = GameContext();
      ctx.player = Player(name: '测试');
      ctx.pendingEvent = {'name': 'ev', 'choices': []};
      expect(ctx.pendingEvent, isNotNull);
      ctx.dismissPendingEvent();
      expect(ctx.pendingEvent, null);
    });

    test('越界索引视为放弃，仅清空挂起', () {
      final ctx = GameContext();
      final p = Player(name: '测试蛊师', inventory: ['原石x10']);
      ctx.player = p;
      ctx.pendingEvent = {
        'eid': 'ev', 'name': 'ev', 'type': 'fortune', 'desc': '',
        'choices': [
          {'text': 'A', 'effect': {'add_item': ['原石x5']}},
        ],
      };
      ctx.resolveEventChoice(99); // 越界
      expect(ctx.pendingEvent, null);
      expect(gu.countMaterial(p, '原石'), 10, reason: '越界不结算，数量不变');
    });
  });

  group('变异蛊标记预留【8.6】', () {
    test('is_mutate 别名解析为 mutated=true', () {
      final g = GuInstance.fromJson({
        'inst_id': 'i1', 'gid': 'g002', 'name': '青茅蛊',
        'rank': 1, 'school': '气道',
        'durability_max': 100, 'durability': 100,
        'is_mutate': true,
      });
      expect(g.mutated, true);
    });

    test('mutated 字段仍正常解析（向后兼容）', () {
      final g = GuInstance.fromJson({
        'inst_id': 'i1', 'gid': 'g002', 'name': '青茅蛊',
        'rank': 1, 'school': '气道',
        'durability_max': 100, 'durability': 100,
        'mutated': true,
      });
      expect(g.mutated, true);
    });

    test('缺失变异字段默认 false 不报错（旧存档兼容）', () {
      final g = GuInstance.fromJson({
        'inst_id': 'i1', 'gid': 'g002', 'name': '青茅蛊',
        'rank': 1, 'school': '气道',
        'durability_max': 100, 'durability': 100,
      });
      expect(g.mutated, false);
    });

    test('变异标记序列化往返一致', () {
      final g = GuInstance(
        instId: 'i1', gid: 'g002', name: '青茅蛊',
        rank: 1, school: '气道', durabilityMax: 100, durability: 100,
        mutated: true,
      );
      final j = g.toJson();
      expect(j['mutated'], true);
      final g2 = GuInstance.fromJson(j);
      expect(g2.mutated, true);
    });
  });
}
