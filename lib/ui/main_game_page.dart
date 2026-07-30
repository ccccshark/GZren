// main_game_page.dart
// 主游戏界面：上方文字输出区、中部快捷指令按钮、底部输入框、悬浮存档/帮助按钮。
import 'package:flutter/material.dart';
import '../main.dart';
import '../engine/command.dart';
import 'combat_ui.dart';
import 'save_menu.dart';
import 'help_page.dart';

class MainGamePage extends StatefulWidget {
  final GameContext ctx;
  const MainGamePage({super.key, required this.ctx});
  @override
  State<MainGamePage> createState() => _MainGamePageState();
}

class _MainGamePageState extends State<MainGamePage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  GameContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    ctx.addListener(_onChanged);
  }

  @override
  void dispose() {
    ctx.removeListener(_onChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    }
  }

  Color _msgColor(MsgType t) {
    switch (t) {
      case MsgType.combat: return const Color(0xFFE74C3C); // 红
      case MsgType.fortune: return const Color(0xFF27AE60); // 绿
      case MsgType.danger: return const Color(0xFFE67E22); // 橙黄
      case MsgType.gu: return const Color(0xFF9B59B6); // 紫
      case MsgType.scene: return const Color(0xFF1ABC9C); // 青
      case MsgType.system: return Colors.white; // 白
    }
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    // 交易指令特殊处理
    if (text.toLowerCase().startsWith('buy') || text.toLowerCase().startsWith('sell') ||
        text.startsWith('购买') || text.startsWith('出售')) {
      ctx.doTradeAction(text);
      return;
    }
    ctx.handle(text);
    if (ctx.gameOver) _backToMenu();
  }

  void _backToMenu() {
    ctx.gameOver = false;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainMenuPage(ctx: ctx)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 战斗/渡劫弹窗
    if (ctx.inCombat && ctx.combat != null) {
      return CombatUIPage(ctx: ctx, isTribulation: false);
    }
    if (ctx.inTribulation && ctx.tribulation != null) {
      return CombatUIPage(ctx: ctx, isTribulation: true);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(ctx.player?.name ?? '蛊真人'),
        backgroundColor: const Color(0xFF2C1E3A),
        actions: [
          IconButton(icon: const Icon(Icons.save), tooltip: '存档', onPressed: _showSaveMenu),
          IconButton(icon: const Icon(Icons.folder_open), tooltip: '读档', onPressed: _showLoadMenu),
          IconButton(icon: const Icon(Icons.help_outline), tooltip: '帮助', onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage()))),
        ],
      ),
      body: Column(
        children: [
          // 上方文字输出区
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF0E0E0E),
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(10),
                itemCount: ctx.log.length,
                itemBuilder: (_, i) {
                  final m = ctx.log[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(m.text, style: TextStyle(color: _msgColor(m.type), fontSize: 14, height: 1.3)),
                  );
                },
              ),
            ),
          ),
          // 中部快捷指令按钮
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(children: [
              _btnRow(['查看场景', '状态', '背包', '空窍', '采集', '静坐'],
                  ['look', 'status', 'inventory', 'kuang', 'gather', 'rest']),
              const SizedBox(height: 4),
              _btnRow(['向北', '向南', '向东', '向西'],
                  ['go north', 'go south', 'go east', 'go west']),
            ]),
          ),
          // 底部输入框
          Container(
            color: const Color(0xFF2C1E3A),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: '输入指令…如 capture 青茅蛊',
                    hintStyle: TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFF27AE60)),
                onPressed: _send,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _btnRow(List<String> labels, List<String> cmds) {
    return Row(children: List.generate(labels.length, (i) =>
      Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2C1E3A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 6),
            textStyle: const TextStyle(fontSize: 13),
          ),
          onPressed: () { ctx.handle(cmds[i]); if (ctx.gameOver) _backToMenu(); },
          child: Text(labels[i]),
        ),
      )),
    ));
  }

  void _showSaveMenu() {
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        SaveMenuPage(ctx: ctx, mode: SaveMenuMode.save)));
  }

  void _showLoadMenu() {
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        SaveMenuPage(ctx: ctx, mode: SaveMenuMode.load)));
  }
}
