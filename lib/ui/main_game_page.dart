// main_game_page.dart
// 主游戏界面：上方文字输出区、中部快捷指令按钮、底部输入框（进阶模式）、悬浮存档/帮助按钮。
// 移动端大众化：默认图形触屏模式（隐藏指令输入框），所有带参数指令通过弹窗选择；
// 进阶模式（设置内开启）显示底部 EditText 指令输入框，兼容传统 MUD 指令。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../engine/command.dart';
import '../data_model/npc_model.dart';
import 'action_dialogs.dart';
import 'combat_ui.dart';
import 'save_menu.dart';
import 'save_code_dialog.dart';
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
          IconButton(
            icon: Icon(ctx.advancedMode ? Icons.keyboard : Icons.touch_app),
            tooltip: ctx.advancedMode ? '当前：进阶模式（点按切换）' : '当前：图形模式（点按切换）',
            onPressed: _showSettings,
          ),
          IconButton(icon: const Icon(Icons.help_outline), tooltip: '帮助', onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage()))),
        ],
      ),
      body: Column(
        children: [
          // 上方文字输出区（NPC/野生蛊行可点击）
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF0E0E0E),
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(10),
                itemCount: ctx.log.length,
                itemBuilder: (_, i) => _logLine(ctx.log[i]),
              ),
            ),
          ),
          // 中部快捷指令按钮（仅保留高频功能）
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(children: [
              _btnRow(['场景', '状态', '背包', '空窍', '采集', '静坐'],
                  ['look', 'status', 'inventory', 'kuang', 'gather', 'rest']),
              const SizedBox(height: 4),
              _btnRow(['向北', '向南', '向东', '向西', '更多操作'],
                  ['go north', 'go south', 'go east', 'go west', '__more__']),
            ]),
          ),
          // 底部输入框：仅进阶模式显示（默认隐藏）
          if (ctx.advancedMode)
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

  /// 渲染单条日志；对 NPC 行与野生蛊行做可点击处理。
  Widget _logLine(Msg m) {
    final color = _msgColor(m.type);
    // NPC 行形如：  [敌对] 名字（境界）  /  [商人] 名字（境界）  /  [NPC] 名字（境界）
    final npc = _matchNpcLine(m.text);
    if (npc != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: _clickableLine(m.text, color, npc.name, () => showNpcActionDialog(context, ctx, npc)),
      );
    }
    // 野生蛊行：  野生蛊虫：青茅蛊, 月光蛊
    final wildLine = _matchWildGuLine(m.text);
    if (wildLine != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: _wildGuSpan(m.text, color, wildLine),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(m.text, style: TextStyle(color: color, fontSize: 14, height: 1.3)),
    );
  }

  /// 匹配 NPC 行，返回对应 Npc（仅当该 NPC 在当前场景且名字出现在行中）。
  Npc? _matchNpcLine(String text) {
    if (!text.startsWith('  [')) return null;
    try {
      for (final n in ctx.npcsInCurRoom()) {
        if (n.alive && text.contains(n.name)) return n;
      }
    } catch (_) {}
    return null;
  }

  /// 匹配野生蛊行，返回野生蛊名称列表。
  List<String>? _matchWildGuLine(String text) {
    if (!text.contains('野生蛊虫')) return null;
    final idx = text.indexOf('：');
    if (idx < 0) return null;
    final names = text.substring(idx + 1).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return names.isEmpty ? null : names;
  }

  Widget _clickableLine(String fullText, Color color, String clickWord, VoidCallback onTap) {
    final idx = fullText.indexOf(clickWord);
    if (idx < 0) {
      return Text(fullText, style: TextStyle(color: color, fontSize: 14, height: 1.3));
    }
    return _ClickableRichText(
      baseStyle: TextStyle(color: color, fontSize: 14, height: 1.3),
      segments: [
        TextSegment(fullText.substring(0, idx), null),
        TextSegment(clickWord, onTap),
        TextSegment(fullText.substring(idx + clickWord.length), null),
      ],
    );
  }

  Widget _wildGuSpan(String fullText, Color color, List<String> guNames) {
    // 在整行中为每个出现的蛊名加可点击 span
    final segments = <TextSegment>[];
    var remaining = fullText;
    while (true) {
      int bestIdx = -1;
      String? bestName;
      for (final name in guNames) {
        final i = remaining.indexOf(name);
        if (i >= 0 && (bestIdx < 0 || i < bestIdx)) {
          bestIdx = i;
          bestName = name;
        }
      }
      if (bestName == null) {
        segments.add(TextSegment(remaining, null));
        break;
      }
      if (bestIdx > 0) segments.add(TextSegment(remaining.substring(0, bestIdx), null));
      final captured = bestName;
      segments.add(TextSegment(captured, () => ctx.handle('capture $captured')));
      remaining = remaining.substring(bestIdx + captured.length);
    }
    return _ClickableRichText(
      baseStyle: TextStyle(color: color, fontSize: 14, height: 1.3),
      segments: segments,
    );
  }

  Widget _btnRow(List<String> labels, List<String> cmds) {
    return Row(children: List.generate(labels.length, (i) =>
      Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: cmds[i] == '__more__' ? const Color(0xFF8E44AD) : const Color(0xFF2C1E3A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 6),
            textStyle: const TextStyle(fontSize: 13),
          ),
          onPressed: () {
            if (cmds[i] == '__more__') {
              _showMoreActions();
            } else {
              ctx.handle(cmds[i]);
              if (ctx.gameOver) _backToMenu();
            }
          },
          child: Text(labels[i]),
        ),
      )),
    ));
  }

  /// “更多操作”展开菜单弹窗：收纳次级功能，避免主界面堆砌按钮。
  void _showMoreActions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 4),
                child: Text('更多操作', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.4,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _moreBtn(c, '捕捉野蛊', Icons.bug_report, () => showCaptureDialog(context, ctx)),
                  _moreBtn(c, '炼蛊', Icons.science, () => showRefineDialog(context, ctx)),
                  _moreBtn(c, '投喂蛊虫', Icons.restaurant, () => showFeedDialog(context, ctx)),
                  _moreBtn(c, '装备蛊', Icons.bolt, () => showEquipDialog(context, ctx)),
                  _moreBtn(c, '取出蛊', Icons.arrow_outward, () => showUnequipDialog(context, ctx)),
                  _moreBtn(c, '催动蛊', Icons.flash_on, () => showUseDialog(context, ctx)),
                  _moreBtn(c, '对话NPC', Icons.chat, () => showTalkDialog(context, ctx)),
                  _moreBtn(c, '交易', Icons.store, () => showTradeDialog(context, ctx)),
                  _moreBtn(c, '攻击NPC', Icons.gavel, () => showAttackDialog(context, ctx)),
                  _moreBtn(c, '境界突破', Icons.auto_awesome, () { ctx.handle('breakthrough'); }),
                  _moreBtn(c, '区域地图', Icons.map, () { ctx.handle('map'); }),
                  _moreBtn(c, '存读档', Icons.save, _showSaveMenu),
                  _moreBtn(c, '存档码备份', Icons.qr_code, () => showSaveCodeBackup(context, ctx)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreBtn(BuildContext sheetCtx, String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2C1E3A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () { Navigator.pop(sheetCtx); onTap(); },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  /// 设置弹窗：双模式切换 + 说明。
  void _showSettings() {
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('交互设置', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('交互模式', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              RadioListTile<bool>(
                title: const Text('图形触屏模式（推荐大众玩家）', style: TextStyle(color: Colors.white)),
                subtitle: const Text('隐藏指令输入框，所有操作点击完成', style: TextStyle(color: Colors.white54, fontSize: 12)),
                value: false, groupValue: ctx.advancedMode,
                onChanged: (v) { ctx.setAdvancedMode(false); setState(() {}); },
              ),
              RadioListTile<bool>(
                title: const Text('进阶指令模式（老玩家）', style: TextStyle(color: Colors.white)),
                subtitle: const Text('显示底部指令输入框，支持传统 MUD 指令', style: TextStyle(color: Colors.white54, fontSize: 12)),
                value: true, groupValue: ctx.advancedMode,
                onChanged: (v) { ctx.setAdvancedMode(true); setState(() {}); },
              ),
              const Divider(color: Colors.white24, height: 20),
              const Text('说明：两种模式可随时切换，且均与原指令系统兼容。',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              const Text('图形模式下，点击日志中的 NPC 名/野生蛊名可直接交互；“更多操作”收纳全部带参指令。',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
          ],
        ),
      ),
    );
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

/// 一段可点击富文本片段：onTap 为 null 表示普通文本。
class TextSegment {
  final String text;
  final VoidCallback? onTap;
  TextSegment(this.text, this.onTap);
}

/// 可点击富文本：正确管理 TapGestureRecognizer 生命周期，避免 ListView 复用泄漏。
class _ClickableRichText extends StatefulWidget {
  final TextStyle baseStyle;
  final List<TextSegment> segments;
  const _ClickableRichText({required this.baseStyle, required this.segments});

  @override
  State<_ClickableRichText> createState() => _ClickableRichTextState();
}

class _ClickableRichTextState extends State<_ClickableRichText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _recognizers.clear();
    final spans = <TextSpan>[];
    for (final seg in widget.segments) {
      if (seg.onTap == null) {
        spans.add(TextSpan(text: seg.text));
      } else {
        final r = TapGestureRecognizer()..onTap = seg.onTap;
        _recognizers.add(r);
        spans.add(TextSpan(
          text: seg.text,
          style: const TextStyle(color: Colors.yellow, decoration: TextDecoration.underline),
          recognizer: r,
        ));
      }
    }
    return RichText(
      text: TextSpan(style: widget.baseStyle, children: spans),
    );
  }
}

