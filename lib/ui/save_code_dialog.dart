// save_code_dialog.dart
// 存档码导入导出 UI：功能选择 → 导出（选槽位→展示存档码→复制） / 导入（粘贴→校验→二次确认→选写入槽位）。
//
// 作为本地存档之外的补充备份手段，原有本地存档系统保留不变。
// 仅读取/写入存档槽的原始 JSON 对象，不修改存档实体类、JSON 结构。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engine/command.dart';
import '../engine/save_system.dart' as sv;
import '../engine/save_codec.dart';

const Color _bg = Color(0xFF1E1E1E);
const Color _itemBg = Color(0xFF2C1E3A);
const Color _accent = Color(0xFF8E44AD);
const Color _danger = Color(0xFFE74C3C);
const Color _ok = Color(0xFF27AE60);

/// 存档码备份入口：弹出功能选择【导出存档码】/【导入存档码】。
Future<void> showSaveCodeBackup(BuildContext context, GameContext ctx) async {
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _bg,
      title: const Text('存档码备份', style: TextStyle(color: Colors.white, fontSize: 18)),
      content: const Text(
        '作为本地存档之外的补充备份手段，可跨手机迁移/分享存档。\n请选择操作：',
        style: TextStyle(color: Colors.white70, fontSize: 13),
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        ElevatedButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('导出存档码'),
          style: ElevatedButton.styleFrom(backgroundColor: _ok, foregroundColor: Colors.white),
          onPressed: () { Navigator.pop(c); _showExport(context); },
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.upload),
          label: const Text('导入存档码'),
          style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
          onPressed: () { Navigator.pop(c); _showImport(context); },
        ),
      ],
    ),
  );
}

// ===================== 导出流程 =====================

void _showExport(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const _ExportPage()));
}

class _ExportPage extends StatefulWidget {
  const _ExportPage();
  @override
  State<_ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<_ExportPage> {
  Map<String, dynamic>? slots;
  int? selectedSlot;
  String? code;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await sv.listSlots();
    if (mounted) setState(() => slots = s);
  }

  Future<void> _generate(int slot) async {
    final raw = await sv.readRawSlot(slot);
    if (raw == null) {
      _toast('存档位 $slot 为空，无法导出。');
      return;
    }
    try {
      final c = encodeSaveCode(raw);
      if (mounted) setState(() { selectedSlot = slot; code = c; });
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导出存档码'), backgroundColor: _itemBg),
      body: slots == null
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : ListView(padding: const EdgeInsets.all(12), children: [
              const Text('1. 选择要导出的存档槽：',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...List.generate(5, (i) {
                final slot = i + 1;
                final info = slots!['$slot'];
                final empty = info == null || info['empty'] == true;
                return Card(
                  color: selectedSlot == slot ? _accent : _itemBg,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('$slot')),
                    title: Text(empty ? '存档$slot（空）' : '存档$slot：${info['name']} | ${info['level']}',
                        style: const TextStyle(color: Colors.white)),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: empty ? Colors.grey : _ok, foregroundColor: Colors.white),
                      onPressed: empty ? null : () => _generate(slot),
                      child: const Text('生成存档码'),
                    ),
                  ),
                );
              }),
              if (code != null) ...[
                const SizedBox(height: 16),
                const Text('2. 存档码（请妥善保存）：',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accent)),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: SelectableText(code!, style: const TextStyle(color: Colors.greenAccent, fontSize: 12, height: 1.4)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: ElevatedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('一键复制'),
                    style: ElevatedButton.styleFrom(backgroundColor: _ok, foregroundColor: Colors.white),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code!));
                      _toast('存档码已复制到剪贴板，请粘贴保存。');
                    },
                  )),
                ]),
                const SizedBox(height: 4),
                const Text('提示：存档码较长，请通过笔记/聊天软件保存；切勿篡改，否则将无法导入。',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ]),
    );
  }
}

// ===================== 导入流程 =====================

void _showImport(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const _ImportPage()));
}

class _ImportPage extends StatefulWidget {
  const _ImportPage();
  @override
  State<_ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<_ImportPage> {
  final TextEditingController _input = TextEditingController();
  DecodedSave? decoded;
  String? error;

  void _verify() {
    setState(() { decoded = null; error = null; });
    try {
      final d = decodeSaveCode(_input.text);
      setState(() => decoded = d);
    } on SaveCodeException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = '存档码损坏或格式错误。');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入存档码'), backgroundColor: _itemBg),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Text('1. 粘贴存档码：',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _input,
          maxLines: 6,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: '在此粘贴存档码…',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true, fillColor: _bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _accent)),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.verified),
          label: const Text('校验存档码'),
          style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
          onPressed: _verify,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8), border: Border.all(color: _danger)),
            child: Row(children: [
              const Icon(Icons.error_outline, color: _danger, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
            ]),
          ),
        ],
        if (decoded != null) ...[
          const SizedBox(height: 12),
          const Text('2. 校验通过，请选择写入的存档槽：',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('存档版本：v${decoded!.version}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          ...List.generate(5, (i) {
            final slot = i + 1;
            return Card(
              color: _itemBg,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(child: Text('$slot')),
                title: Text('覆盖存档位 $slot',
                    style: const TextStyle(color: Colors.white)),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _danger, foregroundColor: Colors.white),
                  child: const Text('写入此槽'),
                  onPressed: () => _confirmAndWrite(slot),
                ),
              ),
            );
          }),
        ],
      ]),
    );
  }

  /// 高危二次确认：覆盖当前存档进度。
  void _confirmAndWrite(int slot) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _bg,
        title: const Text('高危确认', style: TextStyle(color: _danger, fontSize: 18)),
        content: const Text('导入存档将覆盖当前存档进度，确定继续吗？',
            style: TextStyle(color: Colors.white, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _danger, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(c);
              await _write(slot);
            },
            child: const Text('确定覆盖'),
          ),
        ],
      ),
    );
  }

  Future<void> _write(int slot) async {
    final ok = await sv.writeRawSlot(slot, decoded!.data);
    if (!mounted) return;
    if (ok) {
      _toast('导入成功：已写入存档位 $slot。');
      Navigator.pop(context);
    } else {
      _toast('导入失败：写入存档位 $slot 失败。');
    }
  }
}
