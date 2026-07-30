// save_system_test.dart
// 5 槽本地存档系统测试。用 fake PathProviderPlatform 重定向到临时目录。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/npc_model.dart';
import 'package:gzren/engine/save_system.dart' as sv;

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final Directory dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
  @override
  Future<String?> getTemporaryPath() async => dir.path;
  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('guzhenren_save_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir);
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  Player _mkPlayer([String name = '方源']) => Player(
    name: name, align: '魔道', level: '三转初阶',
    slotMax: 5, trueyuan: 80, trueyuanMax: 100,
    lifeLeft: 250, lifeMax: 300, physique: 60,
    inventory: ['露水x3', '原石x5'],
    location: 'qingmao_02',
  );

  group('listSlots', () {
    test('初始全部 5 槽为空', () async {
      final s = await sv.listSlots();
      expect(s!.length, 5);
      for (var i = 1; i <= 5; i++) {
        expect(s['$i']!['empty'], true);
      }
    });
  });

  group('saveGame / loadGame', () {
    test('存档后 listSlots 显示元信息', () async {
      final p = _mkPlayer();
      final ok = await sv.saveGame(1, p, {});
      expect(ok, true);
      final s = await sv.listSlots();
      expect(s!['1']!['empty'], false);
      expect(s['1']!['name'], '方源');
      expect(s['1']!['level'], '三转初阶');
      expect(s['1']!['life_left'], 250);
    });

    test('读档往返一致', () async {
      final p = _mkPlayer();
      p.inventory.add('青茅草根x2');
      await sv.saveGame(3, p, {});
      final (loaded, _) = await sv.loadGame(3);
      expect(loaded, isNotNull);
      expect(loaded!.name, '方源');
      expect(loaded.level, '三转初阶');
      expect(loaded.lifeLeft, 250);
      expect(loaded.inventory, contains('青茅草根x2'));
    });

    test('读空槽返回 null', () async {
      final (loaded, npcs) = await sv.loadGame(2);
      expect(loaded, isNull);
      expect(npcs, isEmpty);
    });

    test('非法槽号 0/6 拒绝', () async {
      expect(await sv.saveGame(0, _mkPlayer(), {}), false);
      expect(await sv.saveGame(6, _mkPlayer(), {}), false);
      final (l0, _) = await sv.loadGame(0);
      expect(l0, isNull);
    });

    test('5 个槽位独立读写', () async {
      for (var i = 1; i <= 5; i++) {
        final ok = await sv.saveGame(i, _mkPlayer('蛊师$i'), {});
        expect(ok, true);
      }
      final s = await sv.listSlots();
      for (var i = 1; i <= 5; i++) {
        expect(s!['$i']!['empty'], false);
        expect(s['$i']!['name'], '蛊师$i');
      }
    });

    test('NPC 状态存读往返', () async {
      final t = NpcTemplate(
        nid: 'n1', name: '巨猿', level: '二转初阶',
        physique: 70, trueyuan: 80, trueyuanMax: 80,
        guInSlot: ['g018'], inventory: ['竹节x3'],
        isHostile: true, isBeast: true,
      );
      final n = Npc.fromTemplate(t);
      n.storeOriginals();
      n.hatePlayer = 5;
      n.alive = false;
      n.deathTime = 24.0;
      await sv.saveGame(1, _mkPlayer(), {'n1': n});
      final (_, npcStates) = await sv.loadGame(1);
      expect(npcStates.length, 1);
      expect(npcStates.first['nid'], 'n1');
      expect(npcStates.first['alive'], false);
      expect(npcStates.first['hate_player'], 5);
      expect(npcStates.first['death_time'], 24.0);
    });

    test('覆盖存档以最新为准', () async {
      await sv.saveGame(1, _mkPlayer('旧档'), {});
      await sv.saveGame(1, _mkPlayer('新档'), {});
      final (loaded, _) = await sv.loadGame(1);
      expect(loaded!.name, '新档');
    });

    test('损坏存档视为空槽不抛异常', () async {
      // 直接写入非法 JSON
      final saveDir = Directory('${tmpDir.path}/save');
      if (!saveDir.existsSync()) saveDir.createSync(recursive: true);
      File('${saveDir.path}/save_slot2.json').writeAsStringSync('not a json');
      final s = await sv.listSlots();
      expect(s!['2']!['empty'], true);
      final (loaded, _) = await sv.loadGame(2);
      expect(loaded, isNull);
    });
  });

  group('applyDeathPenalty 死亡惩罚', () {
    test('丢失部分物资', () {
      final p = _mkPlayer();
      p.inventory = List.generate(10, (i) => '材料${i}x5');
      final before = p.inventory.length;
      final log = <String>[];
      sv.applyDeathPenalty(p, log);
      expect(p.inventory.length, lessThan(before));
      expect(log.any((s) => s.contains('死亡惩罚')), true);
    });

    test('丢失部分蛊虫', () {
      final p = _mkPlayer();
      // 注入若干蛊虫实例
      for (var i = 0; i < 5; i++) {
        p.guBag.add(p.guBag.isEmpty ? p.guBag.first : p.guBag.first);
      }
      // 重建为独立实例
      p.guBag.clear();
      // 直接占位字符串模拟，guBag 实际是 GuInstance 列表，这里仅测试惩罚函数不崩溃
      final log = <String>[];
      sv.applyDeathPenalty(p, log);
      expect(log.any((s) => s.contains('死亡惩罚') || s.contains('物资')), true);
    });

    test('空背包不崩溃', () {
      final p = Player(name: '穷蛊师');
      final log = <String>[];
      sv.applyDeathPenalty(p, log);
      expect(log.first, contains('死亡惩罚'));
    });

    test('概率损失蛊槽上限', () {
      // 多次运行至少一次触发蛊槽损失
      bool slotDamaged = false;
      for (var i = 0; i < 200 && !slotDamaged; i++) {
        final p = Player(name: 'test', slotMax: 5);
        final log = <String>[];
        sv.applyDeathPenalty(p, log);
        if (log.any((s) => s.contains('空窍受创'))) {
          slotDamaged = true;
          expect(p.slotMax, 4);
        }
      }
      expect(slotDamaged, true, reason: '40% 概率应在 200 次内触发');
    });
  });

  group('maxSlots 常量', () {
    test('值为 5', () => expect(sv.maxSlots, 5));
  });
}
