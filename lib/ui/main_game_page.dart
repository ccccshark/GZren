// main_game_page.dart
// 主游戏界面：上方文字输出区、中部快捷指令按钮、底部输入框（进阶模式）、悬浮存档/帮助按钮。
// 移动端大众化：默认图形触屏模式（隐藏指令输入框），所有带参数指令通过弹窗选择；
// 进阶模式（设置内开启）显示底部 EditText 指令输入框，兼容传统 MUD 指令。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../engine/command.dart';
import '../engine/save_system.dart' as sv;
import '../engine/environment_system.dart' show EnvironmentSystem;
import '../data_model/npc_model.dart';
import '../data_model/poison_model.dart' show PoisonStore, PoisonRank;
import 'action_dialogs.dart';
import 'combat_ui.dart';
import 'save_menu.dart';
import 'save_code_dialog.dart';
import 'help_page.dart';
import 'panels.dart'; // 第一阶段新增面板集合（地图/快捷栏/预警/背包分类/新手引导 + 毒素系统面板）
import 'detail_dialogs.dart'; // 第三阶段新增：材料/蛊虫详情浮窗 + 域外通道封锁弹窗

class MainGamePage extends StatefulWidget {
  final GameContext ctx;
  /// 第一阶段新增：是否在进入页面后自动弹出新手引导。
  /// 仅主菜单"新建角色"流程传入 true；读档/测试直接构造时默认 false，不自动弹窗。
  final bool autoStartTutorial;
  const MainGamePage({super.key, required this.ctx, this.autoStartTutorial = false});
  @override
  State<MainGamePage> createState() => _MainGamePageState();
}

class _MainGamePageState extends State<MainGamePage> with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  GameContext get ctx => widget.ctx;

  // 第一阶段新增：状态预警去重签名。仅当预警集合变化时主动弹窗，避免重复打扰。
  // 旧存档/旧版本无此字段，不影响兼容。
  String _lastWarnSig = '';
  bool _warnDialogShowing = false;
  // 第三阶段新增【11.随机事件】：抉择事件弹窗去重标志，避免同一事件重复弹窗。
  bool _eventDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ctx.addListener(_onChanged);
    // V1.9 新增【自动存档】：挂载 onAutoSaveStatus 回调，独立于 SafeSaveManager 的 onStatus
    ctx.onAutoSaveStatus = (ok, msg, isErr) {
      // GameContext 内部已通过 addListener 触发 setState，此处仅占位便于扩展
    };
    // 第一阶段新增：仅主菜单"新建角色"流程（autoStartTutorial=true）自动弹出新手引导。
    // 读档、测试直接构造本页时默认 false，不弹窗，避免阻塞功能测试与读档体验。
    // 引导全程可随时通过"日志菜单→新手引导"或"更多操作→新手引导"重新打开。
    if (widget.autoStartTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showTutorialGuide(context, ctx, forceShow: true);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ctx.removeListener(_onChanged);
    ctx.onAutoSaveStatus = null;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // V1.9 新增【自动存档触发③】：App 退至后台（onPause）触发自动存档。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (mounted) {
        ctx.onPauseAutoSave();
      }
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      _maybeShowWarning();
      _maybeShowEventChoice();
    });
  }

  /// 状态预警主动提示：仅当非战斗/渡劫、预警非空、且签名变化时弹一次。
  /// 签名 = 当前预警文本拼接，避免相同状态反复弹窗。
  void _maybeShowWarning() {
    if (!mounted) return;
    if (ctx.inCombat || ctx.inTribulation || ctx.gameOver) return;
    if (_warnDialogShowing) return;
    final ws = ctx.warnings();
    if (ws.isEmpty) {
      _lastWarnSig = '';
      return;
    }
    final sig = ws.join('|');
    if (sig == _lastWarnSig) return;
    _lastWarnSig = sig;
    _warnDialogShowing = true;
    showStatusWarningDialog(context, ctx).then((_) {
      _warnDialogShowing = false;
    });
  }

  /// 第三阶段新增【11.随机事件抉择弹窗】：当引擎挂起 pendingEvent 时主动弹出抉择界面。
  /// 仅在非战斗/渡劫/未结束、且未正在显示事件弹窗时触发。
  /// 弹窗关闭（选择或放弃）后引擎会清空 pendingEvent，标志位复位。
  void _maybeShowEventChoice() {
    if (!mounted) return;
    if (ctx.inCombat || ctx.inTribulation || ctx.gameOver) return;
    if (_eventDialogShowing) return;
    if (ctx.pendingEvent == null) return;
    _eventDialogShowing = true;
    showEventChoiceDialog(context, ctx).then((_) {
      _eventDialogShowing = false;
    });
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
      case MsgType.system: return const Color(0xFFDCDCDC); // 正文白
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

  /// V1.3 新增【UI顶部状态栏】：展示当前游戏日期 + 时段 + 天气，状态栏同步环境系统。
  /// 点击可展开时段/天气增益减益详情。纯只读展示，不修改游戏状态。
  Widget _envStatusBar() {
    final p = ctx.player;
    if (p == null) return const SizedBox.shrink();
    final phase = EnvironmentSystem.curPhase(p);
    final weather = EnvironmentSystem.curWeather(p);
    final day = EnvironmentSystem.gameDay(p);
    // 时段配色：白天暖黄、黄昏橙、夜晚深紫蓝、凌晨冷青
    final phaseColor = const {
      '白天': Color(0xFFF1C40F),
      '黄昏': Color(0xFFE67E22),
      '夜晚': Color(0xFF5B6FBF),
      '凌晨': Color(0xFF1ABC9C),
    }[phase.phase] ?? const Color(0xFF9D5CD0);
    final wBuff = EnvironmentSystem.weatherBuff(p);
    final wDebuff = EnvironmentSystem.weatherDebuff(p);
    return Material(
      color: const Color(0xFF110F15),
      child: InkWell(
        onTap: () => _showEnvDetail(phase, weather, day, wBuff, wDebuff, phaseColor),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: phaseColor.withOpacity(0.45), width: 1)),
          ),
          child: Row(children: [
            Icon(_phaseIcon(phase.phase), color: phaseColor, size: 16),
            const SizedBox(width: 6),
            Text('第${day}天',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: phaseColor.withOpacity(0.22),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: phaseColor.withOpacity(0.5), width: 0.8),
              ),
              child: Text(phase.phase, style: TextStyle(color: phaseColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            Icon(_weatherIcon(weather), color: const Color(0xFF1ABC9C), size: 15),
            const SizedBox(width: 3),
            Text(weather, style: const TextStyle(color: const Color(0xFF1ABC9C), fontSize: 11)),
            const Spacer(),
            // 时段/天气增益简标
            if (phase.buff.isNotEmpty || wBuff.isNotEmpty)
              const Text('增益↑', style: TextStyle(color: Color(0xFF27AE60), fontSize: 10)),
            if (phase.debuff.isNotEmpty || wDebuff.isNotEmpty)
              const Padding(padding: EdgeInsets.only(left: 4),
                  child: Text('减益↓', style: TextStyle(color: Color(0xFFE67E22), fontSize: 10))),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
          ]),
        ),
      ),
    );
  }

  IconData _phaseIcon(String phase) {
    switch (phase) {
      case '白天': return Icons.wb_sunny;
      case '黄昏': return Icons.wb_twilight;
      case '夜晚': return Icons.nightlight_round;
      case '凌晨': return Icons.bedtime;
      default: return Icons.access_time;
    }
  }

  IconData _weatherIcon(String w) {
    switch (w) {
      case '晴朗': return Icons.wb_sunny_outlined;
      case '小雨': return Icons.grain;
      case '浓雾': return Icons.cloud;
      case '梅雨': return Icons.water_drop;
      default: return Icons.cloud_outlined;
    }
  }

  /// V1.3 新增【环境详情弹窗】：展示时段/天气增益减益明细。
  void _showEnvDetail(dynamic phase, String weather, int day,
      Map<String, double> wBuff, Map<String, dynamic> wDebuff, Color phaseColor) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14101A),
        title: Text('第$day天 · ${phase.phase} · $weather',
            style: TextStyle(color: phaseColor, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('〔${phase.phase}〕${phase.desc}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
              const SizedBox(height: 10),
              const Text('时段效果', style: TextStyle(color: Color(0xFF9D5CD0), fontSize: 13, fontWeight: FontWeight.bold)),
              if (phase.buff.isEmpty && phase.debuff.isEmpty)
                const Text('  无特殊效果', style: TextStyle(color: Colors.white54, fontSize: 12)),
              for (final e in phase.buff.entries)
                _envRow('${e.key} 威力', '×${e.value.toStringAsFixed(2)}', const Color(0xFF27AE60)),
              for (final e in phase.debuff.entries)
                _envRow(e.key, '×${e.value.toStringAsFixed(2)}', const Color(0xFFE67E22)),
              const SizedBox(height: 10),
              const Text('天气效果', style: TextStyle(color: Color(0xFF1ABC9C), fontSize: 13, fontWeight: FontWeight.bold)),
              if (wBuff.isEmpty && wDebuff.isEmpty)
                const Text('  无特殊效果', style: TextStyle(color: Colors.white54, fontSize: 12)),
              for (final e in wBuff.entries)
                _envRow('${e.key} 威力', '×${e.value.toStringAsFixed(2)}', const Color(0xFF27AE60)),
              for (final e in wDebuff.entries)
                _envRow(e.key, e.value is bool ? '生效中' : '×${(e.value as num).toStringAsFixed(2)}', const Color(0xFFE67E22)),
              const SizedBox(height: 8),
              const Divider(color: Colors.white24, height: 16),
              const Text('提示：环境效果与场景增益叠加生效，影响战斗、炼蛊、捕捉成功率。',
                  style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _envRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        Text('  · $label：', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(value, style: TextStyle(color: valueColor, fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  /// 接入【毒素中毒系统】常驻中毒状态栏：显示中毒标签 + 严重度颜色，点击展开详情。
  Widget _poisonStatusBar() {
    final p = ctx.player!;
    final poisons = PoisonStore.list(p);
    final hasDao = poisons.any((x) => x.rank == PoisonRank.dao);
    final hasOdd = poisons.any((x) => x.rank == PoisonRank.odd);
    final hasFierce = poisons.any((x) => x.rank == PoisonRank.fierce);
    final color = hasDao ? const Color(0xFF9D5CD0)
        : (hasOdd ? const Color(0xFFE74C3C)
        : (hasFierce ? const Color(0xFFE67E22) : const Color(0xFF27AE60)));
    final severity = hasDao ? '道毒缠身'
        : (hasOdd ? '奇毒攻心'
        : (hasFierce ? '烈性毒素' : '轻微中毒'));
    final nextTick = poisons.map((x) => x.hoursLeft).reduce((a, b) => a < b ? a : b);
    return Material(
      color: color.withOpacity(0.18),
      child: InkWell(
        onTap: () => showPoisonDetailPanel(context, ctx),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: color.withOpacity(0.5), width: 1)),
          ),
          child: Row(children: [
            Icon(Icons.science, color: color, size: 16),
            const SizedBox(width: 6),
            Text('[$severity] 中${poisons.length}种毒',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '${poisons.map((x) => x.name).join("、")}　下次毒发 ${nextTick.toStringAsFixed(0)}h 后',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            )),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
          ]),
        ),
      ),
    );
  }

  /// V1.9 新增【自动存档小字提示状态栏】：显示最近一次自动存档成功/失败状态。
  /// 绿色=成功，红色=失败；常驻几秒后玩家可忽略；纯展示不拦截。
  Widget _autoSaveStatusBar() {
    final isErr = ctx.lastAutoSaveIsError;
    final color = isErr ? const Color(0xFFE74C3C) : const Color(0xFF27AE60);
    return Material(
      color: color.withOpacity(0.12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: color.withOpacity(0.35), width: 0.8)),
        ),
        child: Row(children: [
          Icon(isErr ? Icons.error_outline : Icons.save_alt, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(child: Text(
            ctx.lastAutoSaveMsg,
            style: TextStyle(color: color, fontSize: 11, height: 1.3),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          )),
          const SizedBox(width: 6),
          Text(
            sv.SafeSaveManager.instance.lastAutoSaveTimeText,
            style: TextStyle(color: color.withOpacity(0.75), fontSize: 10),
          ),
        ]),
      ),
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
        backgroundColor: const Color(0xFF593475), // UI美化·主色
        actions: [
          IconButton(icon: const Icon(Icons.save), tooltip: '存档', onPressed: _showSaveMenu),
          IconButton(icon: const Icon(Icons.folder_open), tooltip: '读档', onPressed: _showLoadMenu),
          // 第一阶段新增：日志管理菜单（清空/保存到文件）
          PopupMenuButton<String>(
            icon: const Icon(Icons.article),
            tooltip: '日志',
            color: const Color(0xFF14101A), // UI美化·菜单背景
            onSelected: (v) {
              if (v == 'clear') _clearLog();
              else if (v == 'save') _saveLog();
              else if (v == 'tutorial') {
                showTutorialGuide(context, ctx, forceShow: true);
              } else if (v == 'warning') {
                final ws = ctx.warnings();
                if (ws.isEmpty) {
                  ctx.out('当前状态良好，无需预警。', MsgType.fortune);
                } else {
                  showStatusWarningDialog(context, ctx);
                }
              }
            },
            itemBuilder: (c) => [
              const PopupMenuItem(value: 'save', child: ListTile(
                leading: Icon(Icons.download, color: Colors.white),
                title: Text('保存日志到文件', style: TextStyle(color: Colors.white)),
                dense: true,
              )),
              const PopupMenuItem(value: 'clear', child: ListTile(
                leading: Icon(Icons.delete_sweep, color: Colors.white),
                title: Text('清空日志', style: TextStyle(color: Colors.white)),
                dense: true,
              )),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'tutorial', child: ListTile(
                leading: Icon(Icons.school, color: Color(0xFF1ABC9C)),
                title: Text('新手引导', style: TextStyle(color: Colors.white)),
                dense: true,
              )),
              const PopupMenuItem(value: 'warning', child: ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: Color(0xFFE67E22)),
                title: Text('状态预警', style: TextStyle(color: Colors.white)),
                dense: true,
              )),
            ],
          ),
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
          // V1.3 新增【UI顶部环境状态栏】：展示当前游戏日期+时段+天气，点击展开详情。
          if (ctx.player != null) _envStatusBar(),
          // 接入【毒素中毒系统】状态栏：仅中毒时显示常驻标签，点击展开毒素详情面板。
          if (ctx.player != null && PoisonStore.hasAny(ctx.player!))
            _poisonStatusBar(),
          // V1.9 新增【自动存档小字提示】：展示最近一次自动存档状态。
          if (ctx.player != null && ctx.lastAutoSaveMsg.isNotEmpty)
            _autoSaveStatusBar(),
          // 上方文字输出区（NPC/野生蛊行可点击）
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF0A0A0D), // UI美化·背景
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
            color: const Color(0xFF110F15), // UI美化·指令栏背景
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(children: [
              _btnRow(['场景', '状态', '背包', '空窍', '采集', '静坐'],
                  ['look', 'status', '__inv_panel__', 'kuang', 'gather', 'rest']),
              const SizedBox(height: 4),
              _btnRow(['向北', '向南', '向东', '向西', '更多操作'],
                  ['go north', 'go south', 'go east', 'go west', '__more__']),
              // 第一阶段新增：自定义蛊虫快捷栏（3 槽，点击催动，长按编辑）
              QuickBarStrip(ctx: ctx, onEdit: () => showQuickBarPanel(context, ctx)),
            ]),
          ),
          // 底部输入框：仅进阶模式显示（默认隐藏）
          if (ctx.advancedMode)
            Container(
              color: const Color(0xFF1C1426), // UI美化·输入框背景
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

  /// 渲染单条日志；V1.3 新增【日志分段边框容器】：每条独立事件用独立边框容器分隔，
  /// 细灰色边框 + 内部边距 + 段落间距；点击展开完整文本；长按复制文本。
  /// 旧存档历史日志（普通 Msg）自动套用新样式渲染，无需修改存储结构。
  Widget _logLine(Msg m) {
    final color = _msgColor(m.type);
    // 构建日志条目内部内容（保留 NPC/野生蛊/场景标题的可点击富文本逻辑）
    // builder 接收 expanded 状态：长文本折叠时截断，展开时完整显示。
    Widget innerBuilder(bool expanded) {
      final npc = _matchNpcLine(m.text);
      if (npc != null) {
        return _clickableLine(m.text, color, npc.name, () => showNpcActionDialog(context, ctx, npc));
      }
      final wildLine = _matchWildGuLine(m.text);
      if (wildLine != null) {
        return _wildGuSpan(m.text, color, wildLine);
      }
      if (m.type == MsgType.scene && _isSceneHeader(m.text)) {
        return _clickableLine(m.text, color, m.text, () => showMapNavPanel(context, ctx), bold: true);
      }
      final bold = m.text.startsWith('【') ||
          m.type == MsgType.danger ||
          m.type == MsgType.fortune;
      return Text(m.text,
          maxLines: expanded ? null : 5,
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
              color: color, fontSize: 14, height: 1.3,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal));
    }
    return _LogEntryBox(
      msg: m,
      borderColor: color,
      innerBuilder: innerBuilder,
    );
  }

  /// 判断是否为场景标题行：形如【青茅山】，且括号内为当前场景名。
  bool _isSceneHeader(String text) {
    if (!text.startsWith('【') || !text.endsWith('】')) return false;
    try {
      final inner = text.substring(1, text.length - 1);
      return ctx.player != null && inner == ctx.curRoom().name;
    } catch (_) {
      return false;
    }
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

  Widget _clickableLine(String fullText, Color color, String clickWord, VoidCallback onTap,
      {bool bold = false}) {
    final idx = fullText.indexOf(clickWord);
    if (idx < 0) {
      return Text(fullText, style: TextStyle(
          color: color, fontSize: 14, height: 1.3,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal));
    }
    return _ClickableRichText(
      baseStyle: TextStyle(color: color, fontSize: 14, height: 1.3,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      segments: [
        TextSegment(fullText.substring(0, idx), null),
        TextSegment(clickWord, onTap),
        TextSegment(fullText.substring(idx + clickWord.length), null),
      ],
    );
  }

  Widget _wildGuSpan(String fullText, Color color, List<String> guNames) {
    // 在整行中为每个出现的蛊名加可点击 span
    // 第三阶段新增【13】：点击蛊名弹出操作选择（捕捉/查看详情），兼容触屏+指令双模式
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
      // 查找该蛊名的 gid 用于详情展示
      String? gid;
      for (final entry in ctx.guList.entries) {
        if (entry.value.name == captured) { gid = entry.key; break; }
      }
      // 第三阶段新增【13】：点击弹出选择菜单（捕捉/查看详情）
      segments.add(TextSegment(captured, () {
        if (gid != null) {
          _showWildGuActionMenu(captured, gid);
        } else {
          ctx.handle('capture $captured');
        }
      }));
      remaining = remaining.substring(bestIdx + captured.length);
    }
    return _ClickableRichText(
      baseStyle: TextStyle(color: color, fontSize: 14, height: 1.3),
      segments: segments,
    );
  }

  /// 第三阶段新增【13】：野生蛊操作菜单（捕捉/查看详情）
  void _showWildGuActionMenu(String guName, String gid) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14101A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text('$guName · 操作',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              // 第三阶段新增【13】：放大触控区域
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                icon: const Icon(Icons.bug_report, size: 20),
                label: Text('捕捉 $guName'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF261C30), foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () { Navigator.pop(c); ctx.handle('capture $guName'); },
              )),
              const SizedBox(height: 6),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                icon: const Icon(Icons.info_outline, size: 20),
                label: const Text('查看详情'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF261C30), foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () { Navigator.pop(c); showGuTemplateDetailDialog(context, ctx, gid); },
              )),
              const SizedBox(height: 6),
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btnRow(List<String> labels, List<String> cmds) {
    // 第三阶段新增【13】：放大按钮触控区域，垂直 padding 从 6 增至 12，适配手机单手操作
    return Row(children: List.generate(labels.length, (i) =>
      Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: cmds[i] == '__more__' ? const Color(0xFF593475) : const Color(0xFF261C30),
            foregroundColor: const Color(0xFFDCDCDC),
            // 第三阶段新增【13】：minimumSize 确保最小触控高度 48dp
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(vertical: 12),
            textStyle: const TextStyle(fontSize: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: const Color(0xFF9D5CD0).withOpacity(0.35), width: 1),
            ),
          ),
          onPressed: () {
            if (cmds[i] == '__more__') {
              _showMoreActions();
            } else if (cmds[i] == '__inv_panel__') {
              // 第一阶段新增：打开背包分类重构面板（仍可经进阶模式 inventory 指令走旧输出）
              showInventoryClassifiedPanel(context, ctx);
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
      backgroundColor: const Color(0xFF14101A), // UI美化·面板背景
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
                  _moreBtn(c, '地图导航', Icons.explore, () => showMapNavPanel(context, ctx)),
                  _moreBtn(c, '大地图导航', Icons.public, () => showWorldMapPanel(context, ctx)),
                  _moreBtn(c, '蛊虫快捷栏', Icons.flash_on, () => showQuickBarPanel(context, ctx)),
                  _moreBtn(c, '杀招面板', Icons.bolt, () => showKillerMovePanel(context, ctx)),
                  _moreBtn(c, '状态预警', Icons.warning_amber_rounded, () {
                    final ws = ctx.warnings();
                    if (ws.isEmpty) ctx.out('当前状态良好，无需预警。', MsgType.fortune);
                    else showStatusWarningDialog(context, ctx);
                  }),
                  _moreBtn(c, '祛毒解毒', Icons.healing, () {
                    // 接入【毒素中毒系统】统一操作面板
                    final ps = PoisonStore.list(ctx.player!);
                    if (ps.isEmpty) {
                      ctx.out('你体内无毒，无需祛毒。', MsgType.fortune);
                    } else {
                      showDetoxActionPanel(context, ctx, initialCmd: 'herb');
                    }
                  }),
                  _moreBtn(c, '毒素详情', Icons.science, () => showPoisonDetailPanel(context, ctx)),
                  _moreBtn(c, '新手引导', Icons.school, () => showTutorialGuide(context, ctx, forceShow: true)),
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
    // 第三阶段新增【13】：放大"更多操作"按钮触控区域，padding 增至 vertical 10
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF261C30),
        foregroundColor: const Color(0xFFDCDCDC),
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: const Color(0xFF9D5CD0).withOpacity(0.3), width: 1),
        ),
      ),
      onPressed: () { Navigator.pop(sheetCtx); onTap(); },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  /// 设置弹窗：双模式切换 + V1.9 自动存档开关 + 说明。
  void _showSettings() {
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          backgroundColor: const Color(0xFF14101A), // UI美化·面板背景
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
              // V1.9 新增【自动存档开关】
              const Text('存档设置', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              SwitchListTile(
                title: const Text('开启自动存档', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  '场景切换/战斗/炼蛊/交易/采集/切后台/180s轮询 自动保存',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: ctx.autoSaveEnabled,
                activeColor: const Color(0xFF27AE60),
                onChanged: (v) { ctx.autoSaveEnabled = v; setState(() {}); },
              ),
              if (ctx.autoSaveEnabled)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '最近自动存档：${sv.SafeSaveManager.instance.lastAutoSaveTimeText}',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
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

  // 第一阶段新增：日志清空（保留一条系统提示，避免空白困惑）
  void _clearLog() {
    ctx.clearLog();
    ctx.out('日志已清空。', MsgType.system);
  }

  // 第一阶段新增：日志保存到 APP 私有目录 txt 文件，纯本地无网络
  Future<void> _saveLog() async {
    if (ctx.log.isEmpty) {
      ctx.out('日志为空，无需保存。', MsgType.system);
      return;
    }
    ctx.out('正在保存日志到本地……', MsgType.system);
    final path = await ctx.saveLogToFile();
    if (path == null) {
      ctx.out('日志保存失败（无法访问应用目录）。', MsgType.danger);
      return;
    }
    ctx.out('【日志已保存】$path', MsgType.fortune);
  }
}

/// 一段可点击富文本片段：onTap 为 null 表示普通文本。
/// 第三阶段新增：onLongPress 支持长按查看详情（仅当 onTap 为 null 时生效）。
class TextSegment {
  final String text;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  TextSegment(this.text, this.onTap, {this.onLongPress});
}

/// 可点击富文本：正确管理 TapGestureRecognizer 生命周期，避免 ListView 复用泄漏。
/// 第三阶段新增：支持 LongPressGestureRecognizer 用于长按查看详情。
class _ClickableRichText extends StatefulWidget {
  final TextStyle baseStyle;
  final List<TextSegment> segments;
  const _ClickableRichText({required this.baseStyle, required this.segments});

  @override
  State<_ClickableRichText> createState() => _ClickableRichTextState();
}

class _ClickableRichTextState extends State<_ClickableRichText> {
  final List<TapGestureRecognizer> _recognizers = [];
  final List<LongPressGestureRecognizer> _longRecognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    for (final r in _longRecognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _recognizers.clear();
    _longRecognizers.clear();
    final spans = <TextSpan>[];
    for (final seg in widget.segments) {
      if (seg.onTap == null && seg.onLongPress == null) {
        spans.add(TextSpan(text: seg.text));
      } else if (seg.onTap != null) {
        // 优先使用 tap recognizer（TextSpan 仅支持单个 recognizer）
        final r = TapGestureRecognizer()..onTap = seg.onTap;
        _recognizers.add(r);
        spans.add(TextSpan(
          text: seg.text,
          style: const TextStyle(color: Colors.yellow, decoration: TextDecoration.underline),
          recognizer: r,
        ));
      } else {
        // 仅 long-press：用 LongPressGestureRecognizer
        final r = LongPressGestureRecognizer()..onLongPress = seg.onLongPress;
        _longRecognizers.add(r);
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

/// V1.3 新增【日志分段边框容器】：每条日志独立边框分隔，点击展开完整文本，长按复制。
/// 旧存档历史日志自动套用新样式渲染（无需修改存储结构），文字指令输出同样分框渲染。
class _LogEntryBox extends StatefulWidget {
  final Msg msg;
  final Color borderColor;
  final Widget Function(bool expanded) innerBuilder;
  const _LogEntryBox({
    required this.msg,
    required this.borderColor,
    required this.innerBuilder,
  });

  @override
  State<_LogEntryBox> createState() => _LogEntryBoxState();
}

class _LogEntryBoxState extends State<_LogEntryBox> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.msg.text.length > 80 || widget.msg.text.contains('\n');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 长按复制全文到剪贴板
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: widget.msg.text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已复制日志文本'),
            duration: const Duration(milliseconds: 900),
            backgroundColor: const Color(0xFF261C30),
          ),
        );
      },
      // 点击展开/收起（仅长文本有效，短文本不切换避免误触）
      onTap: isLong ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2.5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          // 细灰色边框，按日志类型染色低透明度
          border: Border.all(
            color: widget.borderColor.withOpacity(0.28),
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(4),
          color: widget.borderColor.withOpacity(0.04),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧色条标识日志类型
            Container(
              width: 2.5,
              margin: const EdgeInsets.only(right: 6, top: 2),
              constraints: const BoxConstraints(minHeight: 12),
              decoration: BoxDecoration(
                color: widget.borderColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            Expanded(child: widget.innerBuilder(_expanded)),
            if (isLong)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Icon(
                  _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 14,
                  color: widget.borderColor.withOpacity(0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

