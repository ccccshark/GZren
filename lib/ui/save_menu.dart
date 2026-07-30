// save_menu.dart
// 存档/读档菜单：5 个存档槽，显示元信息。
import 'package:flutter/material.dart';
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
  GameContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await sv.listSlots();
    setState(() => slots = s);
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
          : ListView.builder(
              itemCount: 5,
              itemBuilder: (_, i) {
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
                        : Text('寿元${((info['life_left'] as num?) ?? 0).toDouble().toStringAsFixed(0)}年'),
                    trailing: widget.mode == SaveMenuMode.save
                        ? const Icon(Icons.save)
                        : (empty ? null : const Icon(Icons.folder_open)),
                    onTap: () => _onTap(slot, empty),
                  ),
                );
              },
            ),
    );
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
