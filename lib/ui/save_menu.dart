// save_menu.dart
// 存档/读档菜单：5 个手动存档槽 + V1.9 自动存档槽（只读，禁止手动覆盖）。
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../engine/command.dart';
import '../engine/save_system.dart' as sv;
import 'main_game_page.dart';

enum SaveMenuMode { save, load }

class SaveMenuPage extends StatefulWidget {
  final GameContext ctx;
  final SaveMenuMode mode;
  const SaveMenuPage({super.key, required this.ctx, required this.mode});
  @override
  State<SaveMenuPage> createState() => _SaveMenuPageState();
}

class _SaveMenuPageState extends State<SaveMenuPage> {
  Map<String, dynamic>? slots;
  /// V1.9 自动存档槽信息：null=未加载，Map=已加载(含 empty/name/level/life_left/save_time/trigger/reason)。
  Map<String, dynamic>? autoSlotInfo;
  GameContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await sv.listSlots();
    final auto = await _loadAutoSlotInfo();
    if (!mounted) return;
    setState(() {
      slots = s;
      autoSlotInfo = auto;
    });
  }

  /// V1.9：读取自动存档槽的元信息（与 listSlots 返回格式兼容）。
  /// 不存在或损坏返回 {'empty': true}。
  Future<Map<String, dynamic>> _loadAutoSlotInfo() async {
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory('${doc.path}/save');
    final main = File('${dir.path}/save_autoslot.json');
    final bak = File('${dir.path}/save_autoslot.json.bak');
    File? f;
    if (main.existsSync()) f = main;
    else if (bak.existsSync()) f = bak;
    if (f == null) return {'empty': true};
    try {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final p = j['player'] as Map<String, dynamic>;
      final trigger = j['trigger'] as String? ?? '';
      return {
        'empty': false,
        'name': p['name'],
        'level': p['level'],
        'life_left': p['life_left'],
        'save_time': j['save_time'],
        'trigger': trigger,
        'from_backup': f.path.endsWith('.bak'),
      };
    } catch (_) {
      return {'empty': true};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == SaveMenuMode.save ? '存档' : '读档'),
        backgroundColor: const Color(0xFF2C1E3A),
      ),
      body: slots == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // V1.9 新增：自动存档槽（顶部突出显示）
                if (widget.mode == SaveMenuMode.load) _buildAutoSlotTile(),
                ...List.generate(5, (i) => _buildManualSlotTile(i)),
                const SizedBox(height: 16),
                if (widget.mode == SaveMenuMode.save)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '提示：手动存档保存到槽位 1-5；自动存档由系统后台保存，\n'
                      '触发时机：场景切换/战斗结算/炼蛊/交易/采集/切后台/每 180 秒。',
                      style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.5),
                    ),
                  ),
              ],
            ),
    );
  }

  /// V1.9：自动存档槽 UI（只读，仅在读档模式显示）。
  Widget _buildAutoSlotTile() {
    final info = autoSlotInfo ?? {'empty': true};
    final empty = info['empty'] == true;
    final trigger = info['trigger'] as String? ?? '';
    final triggerText = const {
      'scene_change': '场景切换',
      'combat': '战斗结算',
      'alchemy': '炼蛊结束',
      'trade': '交易完成',
      'collect': '采集完成',
      'on_pause': '切至后台',
      'poll': '定时轮询',
    }[trigger] ?? trigger;
    final fromBackup = info['from_backup'] == true;
    final subtitleParts = <String>[];
    if (!empty) {
      subtitleParts.add('寿元${((info['life_left'] as num?) ?? 0).toDouble().toStringAsFixed(0)}年');
      if (triggerText.isNotEmpty) subtitleParts.add('触发：$triggerText');
      if (fromBackup) subtitleParts.add('【备份恢复】');
      subtitleParts.add((info['save_time'] as String? ?? '').replaceFirst('T', ' '));
    }
    return Card(
      color: const Color(0xFF2A1F3C),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: const Color(0xFF9D5CD0).withOpacity(0.6), width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFF9D5CD0),
          child: Icon(Icons.auto_mode, color: Colors.white),
        ),
        title: Text(
          empty ? '自动存档（空）' : '自动存档：${info['name']} | ${info['level']}',
          style: const TextStyle(color: Color(0xFFF3ECFF), fontWeight: FontWeight.w600),
        ),
        subtitle: empty
            ? const Text('尚未产生自动存档', style: TextStyle(color: Colors.white54, fontSize: 12))
            : Text(subtitleParts.join('　'), style: const TextStyle(color: Colors.white60, fontSize: 11)),
        trailing: empty ? null : const Icon(Icons.folder_open, color: Color(0xFF9D5CD0)),
        onTap: () async {
          if (empty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('自动存档为空')),
            );
            return;
          }
          final ok = await _loadAutoSave();
          if (ok && mounted) {
            Navigator.pushAndRemoveUntil(context,
              MaterialPageRoute(builder: (_) => MainGamePage(ctx: ctx)), (_) => false);
          }
        },
      ),
    );
  }

  Widget _buildManualSlotTile(int i) {
    final slot = i + 1;
    final info = slots!['$slot'];
    final empty = info == null || info['empty'] == true;
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(child: Text('$slot')),
        title: Text(empty ? '存档$slot（空）' : '存档$slot：${info['name']} | ${info['level']}'),
        subtitle: empty
            ? null
            : Text('寿元${((info['life_left'] as num?) ?? 0).toDouble().toStringAsFixed(0)}年　${(info['save_time'] as String? ?? '').replaceFirst('T', ' ')}',
                style: const TextStyle(fontSize: 11)),
        trailing: widget.mode == SaveMenuMode.save
            ? const Icon(Icons.save)
            : (empty ? null : const Icon(Icons.folder_open)),
        onTap: () => _onTap(slot, empty),
      ),
    );
  }

  /// V1.9：加载自动存档（主档损坏时自动读备份，由 SafeSaveManager.loadAuto 保证）。
  Future<bool> _loadAutoSave() async {
    final (p, npcStates) = await sv.SafeSaveManager.instance.loadAuto();
    if (p == null) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: const Color(0xFF14101A),
            title: const Text('自动存档加载失败', style: TextStyle(color: Colors.white)),
            content: const Text('自动存档文件损坏且无可用备份。请选择手动存档槽加载。',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return false;
    }
    await ctx.installLoadedSave(p, npcStates);
    return true;
  }

  Future<void> _onTap(int slot, bool empty) async {
    if (widget.mode == SaveMenuMode.save) {
      await ctx.saveToSlot(slot);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已保存至存档位 $slot')));
        _refresh();
      }
    } else {
      if (empty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该存档位为空')));
        return;
      }
      await ctx.loadFromSlot(slot);
      if (mounted) {
        Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => MainGamePage(ctx: ctx)), (_) => false);
      }
    }
  }
}
