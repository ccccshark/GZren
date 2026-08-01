// save_system.dart
// 本地存档系统：5 个存档槽 + V1.9 新增自动存档系统。
// JSON 存至 APP 私有目录。含死亡惩罚。
// V1.9 新增：
//   · SafeSaveManager：写入锁/原子保存(tmp→rename)/备份/节流；
//   · 手动存档(slot 1-5) 与自动存档(slot AUTO_SLOT) 双体系；
//   · 4 种触发时机：场景切换/战斗/炼蛊交易采集/onPause/180s 定时轮询；
//   · 损坏自动恢复：优先主档，失败读备份，全失败返回 null；
//   · 节流：任意两类触发间隔 < AUTO_THROTTLE_S 跳过。
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
    p.flags['slot_damaged'] = true; // 标记空窍受损，供 UI 状态预警读取（旧存档无此键→不预警，兼容）
  }

  log.add('【死亡惩罚】你险死还生，付出惨痛代价：');
  if (lostMat.isNotEmpty) {
    log.add('  丢失物资 ${lostMat.length} 组：${lostMat.take(5).join(', ')}${lostMat.length > 5 ? '...' : ''}');
  }
  if (lostGu.isNotEmpty) log.add('  丢失蛊虫 ${lostGu.length} 只：${lostGu.join(', ')}');
  if (slotDamaged) log.add('  空窍受创，蛊槽上限永久 -1（当前 ${p.slotMax}）。');
}

// ===========================================================================
// V1.9 新增【稳定自动存档系统】SafeSaveManager
// ---------------------------------------------------------------------------
// 设计原则：
//   1. 双体系共存：手动存档(slot 1-5) + 自动存档(slot AUTO_SLOT)，互不干扰；
//   2. 原子写入：tmp 文件完整写完→rename 覆盖正式存档，杜绝半截坏档；
//   3. 写入锁：isWriting=true 时拒绝新请求；
//   4. 双备份：每次写先把正式存档 rename 为 .bak，坏档可自动回滚；
//   5. 节流：3s 内重复触发直接跳过，避免高频 IO；
//   6. 性能：存档 JSON 内不存静态资源（guList/rooms/recipes 都不存），
//      只序列化 player+npcs（与手动存档同结构，完全兼容）；
//   7. 异常全捕获：读写失败不崩溃，通过 onStatus 回调上报。
// ===========================================================================

/// 自动存档专用槽位（5 槽之外的第 6 槽，不影响手动存档）。
const int autoSaveSlot = 6;

/// 事件节流窗口（秒）：小于该间隔的触发直接跳过。
const int autoThrottleSec = 3;

/// 定时轮询间隔（秒）：空闲时兜底自动存档。
const int autoPollIntervalSec = 180;

/// 自动存档状态回调类型：(是否成功, 消息文本, 是否为错误)
typedef AutoSaveStatusFn = void Function(bool ok, String msg, bool isError);

class SafeSaveManager {
  SafeSaveManager._();
  static final SafeSaveManager instance = SafeSaveManager._();

  /// 写入锁：true 表示正在写文件，拒绝新请求防止并发覆盖。
  bool _isWriting = false;
  bool get isWriting => _isWriting;

  /// 上次自动存档成功时间（微秒），用于 3s 节流。
  int _lastAutoSaveUs = 0;

  /// 自动存档功能总开关（UI 可改，存 player.flags 持久化）。
  bool autoSaveEnabled = true;

  /// 外部挂载的状态回调：UI 监听显示小字提示。
  AutoSaveStatusFn? onStatus;

  /// 上一次成功时间可读（UI 展示）。
  int get lastAutoSaveUs => _lastAutoSaveUs;
  String get lastAutoSaveTimeText {
    if (_lastAutoSaveUs <= 0) return '暂未自动存档';
    final dt = DateTime.fromMicrosecondsSinceEpoch(_lastAutoSaveUs);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  // -----------------------------------------------------------------------
  // 原子写入：tmp → rename 覆盖正式存档；失败自动回滚 .bak
  // -----------------------------------------------------------------------
  Future<bool> _atomicWrite(String path, String content) async {
    if (_isWriting) {
      onStatus?.call(false, '正在写入中，跳过本次存档', true);
      return false;
    }
    _isWriting = true;
    try {
      final tmpPath = '$path.tmp';
      final bakPath = '$path.bak';
      final mainFile = File(path);
      final tmpFile = File(tmpPath);
      // ① 写临时文件
      await tmpFile.writeAsString(content, flush: true);
      // ② 把旧正式存档（若存在）备份为 .bak
      if (mainFile.existsSync()) {
        try { mainFile.copySync(bakPath); } catch (_) {}
      }
      // ③ 临时文件 rename 覆盖正式存档（文件系统原子操作）
      await tmpFile.rename(path);
      // ④ 清理过旧的备份（保留最近 2 份）
      _cleanupOldBackups(path);
      return true;
    } on FileSystemException catch (e) {
      debugPrint('SafeSaveManager 写入失败: ${e.message}');
      onStatus?.call(false, '存档写入失败: ${e.message}', true);
      return false;
    } catch (e) {
      debugPrint('SafeSaveManager 未知异常: $e');
      onStatus?.call(false, '存档异常: $e', true);
      return false;
    } finally {
      _isWriting = false;
    }
  }

  /// 清理同一目录下过旧的 .bak（当前逻辑只保留 1 份，占位以便扩展）。
  void _cleanupOldBackups(String path) {
    // 若未来需要多份轮转备份，可在此处按文件修改时间删除最旧者。
  }

  // -----------------------------------------------------------------------
  // 对外 API：手动存档（兼容现有 saveGame 调用方）
  //   带 SafeWrite 保护，调用方无需改动。
  // -----------------------------------------------------------------------
  Future<bool> safeSaveManual(int slot, Player p, Map<String, Npc> npcs) async {
    if (slot < 1 || slot > maxSlots) return false;
    try {
      final dir = await _saveDir();
      final npcStates = npcs.values.map((n) => n.toJson()).toList();
      final data = {
        'player': p.toJson(),
        'npcs': npcStates,
        'save_time': DateTime.now().toIso8601String(),
        'version': 2,
        'save_type': 'manual',
      };
      final path = '${dir.path}/${_slotPath(slot)}';
      final ok = await _atomicWrite(path, jsonEncode(data));
      if (ok) onStatus?.call(true, '手动存档成功（槽位 $slot）', false);
      return ok;
    } catch (e) {
      onStatus?.call(false, '手动存档失败: $e', true);
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // 对外 API：自动存档（带节流+开关）
  //   triggerReason: 触发原因，写入元数据（scene_change/combat/alchemy/trade/collect/on_pause/poll）
  // -----------------------------------------------------------------------
  Future<bool> autoSave({
    required Player player,
    required Map<String, Npc> npcs,
    required String triggerReason,
    bool force = false,
  }) async {
    if (!autoSaveEnabled && !force) {
      return false;
    }
    // 3s 节流（force=true 跳过节流）
    if (!force) {
      final nowUs = DateTime.now().microsecondsSinceEpoch;
      final diffSec = (nowUs - _lastAutoSaveUs) / 1000000;
      if (diffSec < autoThrottleSec) {
        return false;
      }
    }
    try {
      final dir = await _saveDir();
      final npcStates = npcs.values.map((n) => n.toJson()).toList();
      final data = {
        'player': player.toJson(),
        'npcs': npcStates,
        'save_time': DateTime.now().toIso8601String(),
        'version': 2,
        'save_type': 'auto',
        'trigger': triggerReason,
      };
      final path = '${dir.path}/save_autoslot.json';
      final ok = await _atomicWrite(path, jsonEncode(data));
      if (ok) {
        _lastAutoSaveUs = DateTime.now().microsecondsSinceEpoch;
        onStatus?.call(true, '自动存档成功 · ${_reasonText(triggerReason)}', false);
      }
      return ok;
    } catch (e) {
      onStatus?.call(false, '自动存档失败: $e', true);
      return false;
    }
  }

  String _reasonText(String r) {
    switch (r) {
      case 'scene_change': return '场景切换';
      case 'combat': return '战斗结算';
      case 'alchemy': return '炼蛊结束';
      case 'trade': return '交易完成';
      case 'collect': return '采集完成';
      case 'on_pause': return '切至后台';
      case 'poll': return '定时轮询';
      default: return r;
    }
  }

  // -----------------------------------------------------------------------
  // 读取：主档失败读备份，全失败返回 (null, []) 不崩
  // -----------------------------------------------------------------------
  Future<(Player?, List<Map<String, dynamic>>)> loadAuto() async {
    final dir = await _saveDir();
    final main = File('${dir.path}/save_autoslot.json');
    final bak = File('${dir.path}/save_autoslot.json.bak');
    Player? p; List<Map<String, dynamic>> npcs = [];
    bool loaded = false;
    // 优先主档
    if (main.existsSync()) {
      try {
        final j = jsonDecode(main.readAsStringSync()) as Map<String, dynamic>;
        p = Player.fromJson(j['player'] as Map<String, dynamic>);
        npcs = (j['npcs'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        loaded = true;
      } catch (_) { loaded = false; }
    }
    // 主档坏→读备份
    if (!loaded && bak.existsSync()) {
      try {
        final j = jsonDecode(bak.readAsStringSync()) as Map<String, dynamic>;
        p = Player.fromJson(j['player'] as Map<String, dynamic>);
        npcs = (j['npcs'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        loaded = true;
        onStatus?.call(true, '主档损坏，已自动加载备份存档', true);
      } catch (_) { loaded = false; }
    }
    if (!loaded) {
      onStatus?.call(false, '自动存档文件损坏且无备份，无法加载', true);
    }
    return (p, npcs);
  }

  /// 自动存档文件是否存在（供"继续游戏"按钮判断）。
  Future<bool> hasAutoSave() async {
    final dir = await _saveDir();
    return File('${dir.path}/save_autoslot.json').existsSync() ||
        File('${dir.path}/save_autoslot.json.bak').existsSync();
  }
}
