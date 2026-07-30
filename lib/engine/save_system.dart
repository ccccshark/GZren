// save_system.dart
// 本地存档系统：5 个存档槽，JSON 存至 APP 私有目录。含死亡惩罚。
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/npc_model.dart';

const int maxSlots = 5;

Future<Directory> _saveDir() async {
  final doc = await getApplicationDocumentsDirectory();
  final dir = Directory('${doc.path}/save');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

String _slotPath(int slot) => 'save_slot$slot.json';

Future<Map<String, dynamic>?> listSlots() async {
  final dir = await _saveDir();
  final result = <String, dynamic>{};
  for (var i = 1; i <= maxSlots; i++) {
    final f = File('${dir.path}/${_slotPath(i)}');
    if (f.existsSync()) {
      try {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final p = j['player'] as Map<String, dynamic>;
        result['$i'] = {
          'empty': false,
          'name': p['name'],
          'level': p['level'],
          'life_left': p['life_left'],
          'save_time': j['save_time'],
        };
      } catch (_) {
        result['$i'] = {'empty': true};
      }
    } else {
      result['$i'] = {'empty': true};
    }
  }
  return result;
}

Future<bool> saveGame(int slot, Player p, Map<String, Npc> npcs) async {
  if (slot < 1 || slot > maxSlots) return false;
  final dir = await _saveDir();
  final npcStates = npcs.values.map((n) => n.toJson()).toList();
  final data = {
    'player': p.toJson(),
    'npcs': npcStates,
    'save_time': DateTime.now().toIso8601String(),
    'version': 1,
  };
  final f = File('${dir.path}/${_slotPath(slot)}');
  f.writeAsStringSync(jsonEncode(data));
  return true;
}

/// 读取存档，返回 (player, npc状态列表)。NPC 状态由调用方合并到模板。
Future<(Player?, List<Map<String, dynamic>>)> loadGame(int slot) async {
  if (slot < 1 || slot > maxSlots) return (null as Player?, <Map<String, dynamic>>[]);
  final dir = await _saveDir();
  final f = File('${dir.path}/${_slotPath(slot)}');
  if (!f.existsSync()) return (null as Player?, <Map<String, dynamic>>[]);
  try {
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final player = Player.fromJson(j['player'] as Map<String, dynamic>);
    final npcStates = (j['npcs'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return (player, npcStates);
  } catch (_) {
    return (null as Player?, <Map<String, dynamic>>[]);
  }
}

/// 读取存档槽原始 JSON 对象（供存档码导出用）。空槽或损坏返回 null。
Future<Map<String, dynamic>?> readRawSlot(int slot) async {
  if (slot < 1 || slot > maxSlots) return null;
  final dir = await _saveDir();
  final f = File('${dir.path}/${_slotPath(slot)}');
  if (!f.existsSync()) return null;
  try {
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// 将原始存档对象写入指定槽（供存档码导入用）。返回是否成功。
Future<bool> writeRawSlot(int slot, Map<String, dynamic> data) async {
  if (slot < 1 || slot > maxSlots) return false;
  final dir = await _saveDir();
  final f = File('${dir.path}/${_slotPath(slot)}');
  try {
    f.writeAsStringSync(jsonEncode(data));
    return true;
  } catch (_) {
    return false;
  }
}

/// 死亡惩罚：随机丢失背包蛊虫、大量物资；一定概率永久损伤空窍。
void applyDeathPenalty(Player p, List<String> log) {
  final loseMat = max(1, (p.inventory.length * (0.3 + Random().nextDouble() * 0.3)).toInt());
  p.inventory.shuffle();
  final lostMat = p.inventory.take(loseMat).toList();
  final removeN = loseMat.clamp(0, p.inventory.length).toInt();
  p.inventory.removeRange(0, removeN);

  final lostGu = <String>[];
  if (p.guBag.isNotEmpty) {
    final n = min(p.guBag.length, 1 + Random().nextInt(2));
    p.guBag.shuffle();
    lostGu.addAll(p.guBag.take(n).map((g) => g.name));
    p.guBag.removeRange(0, n);
  }

  bool slotDamaged = false;
  if (Random().nextDouble() < 0.4 && p.slotMax > 1) {
    p.slotMax -= 1;
    slotDamaged = true;
  }

  log.add('【死亡惩罚】你险死还生，付出惨痛代价：');
  if (lostMat.isNotEmpty) {
    log.add('  丢失物资 ${lostMat.length} 组：${lostMat.take(5).join(', ')}${lostMat.length > 5 ? '...' : ''}');
  }
  if (lostGu.isNotEmpty) log.add('  丢失蛊虫 ${lostGu.length} 只：${lostGu.join(', ')}');
  if (slotDamaged) log.add('  空窍受创，蛊槽上限永久 -1（当前 ${p.slotMax}）。');
}
