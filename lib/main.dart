// main.dart
// 蛊真人单机文字MUD（安卓端）APP 入口。纯离线，无任何联网功能。
// V2.0 内存优化：Debug 模式关闭多余检测+图片缓存限制+错误兜底 zone。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'engine/command.dart';
import 'engine/save_system.dart' as sv;
import 'ui/main_game_page.dart';
import 'ui/save_menu.dart';
import 'ui/help_page.dart';
import 'ui/disclaimer_dialog.dart';
import 'ui/save_code_dialog.dart';
import 'ui/panels.dart'; // 第一阶段新增：新手引导面板

void main() {
  // V2.0 内存优化【关闭 Debug 多余检测】：release 模式下禁用调试断言与 painting 检测。
  if (kReleaseMode) {
    debugPrint = (_, {int? wrapWidth}) {}; // 静默 debugPrint，减少字符串拼接开销
    debugDefaultTargetPlatformOverride = null;
  }
  // V2.0 内存优化【图片缓存限制】：纯文字游戏无大图，限制 Flutter 图片缓存为最小值。
  // 即使运行时仅用 Material Icons 字体图标，也防止意外图片解码缓存膨胀。
  PaintingBinding.instance.imageCache.maximumSize = 20; // 最多缓存 20 张
  PaintingBinding.instance.imageCache.maximumSizeBytes = 2 * 1024 * 1024; // 2MB 上限

  // V2.0 内存优化【错误兜底 zone】：捕获未处理异常，防止崩溃且不产生调试堆栈日志。
  runZonedGuarded(() {
    runApp(const GuZhenRenApp());
  }, (error, stack) {
    // release 模式下静默处理，debug 模式下输出到控制台
    if (kDebugMode) {
      debugPrint('未捕获异常: $error\n$stack');
    }
  });
}

class GuZhenRenApp extends StatelessWidget {
  const GuZhenRenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '蛊真人单机MUD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        // UI美化·统一色彩规范：背景#0A0A0D，主色#593475，高亮紫#9D5CD0
        scaffoldBackgroundColor: const Color(0xFF0A0A0D),
        primaryColor: const Color(0xFF593475),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF593475),
          secondary: Color(0xFF9D5CD0),
          surface: Color(0xFF14101A),
        ),
        fontFamily: 'monospace',
      ),
      home: const BootPage(),
    );
  }
}

class BootPage extends StatefulWidget {
  const BootPage({super.key});
  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  final GameContext ctx = GameContext();
  bool _loading = true;
  bool _disclaimerAccepted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ctx.loadStatic();
    if (!mounted) return;
    // 启动后最先弹出免责声明弹窗；用户必须同意才进入主菜单，拒绝则退出 App。
    final accepted = await showStartupDisclaimer(context);
    if (!mounted) return;
    setState(() {
      _disclaimerAccepted = accepted;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF9D5CD0))),
      );
    }
    // 用户拒绝时显示空 Scaffold（SystemNavigator.pop 已触发退出 App）
    if (!_disclaimerAccepted) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return MainMenuPage(ctx: ctx);
  }
}

class MainMenuPage extends StatefulWidget {
  final GameContext ctx;
  const MainMenuPage({super.key, required this.ctx});
  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  GameContext get ctx => widget.ctx;
  bool? _hasAutoSave;

  @override
  void initState() {
    super.initState();
    sv.SafeSaveManager.instance.hasAutoSave().then((v) {
      if (mounted) setState(() => _hasAutoSave = v);
    });
  }

  Future<void> _continueGame(BuildContext context) async {
    final (p, npcStates) = await sv.SafeSaveManager.instance.loadAuto();
    if (!mounted) return;
    if (p == null) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF14101A),
          title: const Text('继续游戏失败', style: TextStyle(color: Colors.white)),
          content: const Text('自动存档损坏且无备份，请从"读取存档"选择手动存档槽。',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }
    await ctx.installLoadedSave(p, npcStates);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) =>
        MainGamePage(ctx: ctx)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('蛊真人 · 单机MUD'),
        centerTitle: true,
        backgroundColor: const Color(0xFF593475),
      ),
      body: Stack(
        children: [
          // UI美化：低透明度古卷暗纹背景
          Positioned.fill(child: CustomPaint(painter: _ScrollPatternPainter())),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // UI美化：古风标题 + 柔和外发光
                  const Text(
                    '蛊 真 人',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF9D5CD0),
                      letterSpacing: 14,
                      fontFamilyFallback: ['serif'],
                      shadows: [
                        Shadow(color: Color(0xFF9D5CD0), blurRadius: 14),
                        Shadow(color: Color(0xFF593475), blurRadius: 30),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('单机文字MUD · 纯离线',
                      style: TextStyle(color: Color(0xFF8C7DA0), fontSize: 13, letterSpacing: 2)),
                  const SizedBox(height: 44),
                  // V1.9 新增【继续游戏】：有自动存档时显示于顶部（高亮推荐按钮）
                  if (_hasAutoSave == true)
                    _menuBtn(context, '继续游戏', Icons.play_arrow, () => _continueGame(context),
                        highlight: true),
                  _menuBtn(context, '新建角色', Icons.person_add, () => _newGame(context)),
                  _menuBtn(context, '读取存档', Icons.save, () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SaveMenuPage(ctx: ctx, mode: SaveMenuMode.load)))),
                  _menuBtn(context, '存档码备份', Icons.qr_code, () => showSaveCodeBackup(context, ctx)),
                  // 第一阶段新增：主菜单新手引导入口（forceShow，可随时回顾，不影响存档）
                  _menuBtn(context, '新手引导', Icons.school, () => showTutorialGuide(context, ctx, forceShow: true)),
                  _menuBtn(context, '游戏说明', Icons.help_outline, () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const HelpPage()))),
                  _menuBtn(context, '退出', Icons.exit_to_app, () => Navigator.of(context).maybePop()),
                  const SizedBox(height: 28),
                  // UI美化：底部开源免责小字 + 开源地址
                  const Text(
                    '本项目为开源单机同人作品，仅供学习交流，严禁商用。\n游戏内容纯属虚构，与现实无关。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF6E6E6E), fontSize: 11, height: 1.6),
                  ),
                  const SizedBox(height: 6),
                  const SelectableText(
                    'https://github.com/ccccshark/GZren',
                    style: TextStyle(color: Color(0xFF7A6A8C), fontSize: 11, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuBtn(BuildContext context, String label, IconData icon, VoidCallback onTap, {bool highlight = false}) {
    // UI美化：圆角16、底色#261C30、淡紫细描边，按压柔光晕动效（封装于 _GlowMenuButton，仅样式）
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: _GlowMenuButton(label: label, icon: icon, onTap: onTap, highlight: highlight),
    );
  }

  void _newGame(BuildContext context) {
    final nameCtrl = TextEditingController(text: '无名蛊师');
    String align = '中立';
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('角色创建'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '角色名')),
            const SizedBox(height: 12),
            const Text('阵营'),
            Row(children: ['正道', '魔道', '中立'].map((a) =>
              Expanded(child: RadioListTile<String>(
                title: Text(a), value: a, groupValue: align,
                onChanged: (v) => setState(() => align = v!),
                dense: true,
              ))).toList()),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                ctx.newGame(nameCtrl.text.trim().isEmpty ? '无名蛊师' : nameCtrl.text.trim(), align);
                Navigator.pop(c);
                // 第一阶段新增：新建角色后自动弹出新手分段引导（autoStartTutorial=true）
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) =>
                    MainGamePage(ctx: ctx, autoStartTutorial: true)));
              },
              child: const Text('开始'),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== 主菜单 UI 美化组件（仅样式，无业务逻辑） =====================

/// 低透明度古卷暗纹背景：斜向纹理 + 暗印章方框，营造国风诡秘内敛氛围。
/// 纯绘制，不接收点击、不影响交互。
class _ScrollPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 斜向暗纹
    final line = Paint()
      ..color = const Color(0xFF9D5CD0).withOpacity(0.04)
      ..strokeWidth = 1;
    const step = 30.0;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
    }
    // 暗印章方框
    final sq = Paint()
      ..color = const Color(0xFF593475).withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (double y = 50; y < size.height; y += 130) {
      for (double x = 36; x < size.width; x += 130) {
        canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: 16, height: 16), sq);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 主菜单按钮：圆角16、底色#261C30、淡紫细描边，按压时柔光晕动效。
/// 仅样式封装，点击透传原 onTap 回调，不改动任何业务逻辑。
/// V1.9 新增 highlight 参数：为 true 时外发光+绿描边（推荐"继续游戏"使用）。
class _GlowMenuButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;
  const _GlowMenuButton({required this.label, required this.icon, required this.onTap, this.highlight = false});
  @override
  State<_GlowMenuButton> createState() => _GlowMenuButtonState();
}

class _GlowMenuButtonState extends State<_GlowMenuButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.highlight ? const Color(0xFF27AE60) : const Color(0xFF9D5CD0);
    final iconColor = widget.highlight ? const Color(0xFF27AE60) : const Color(0xFF9D5CD0);
    final textColor = widget.highlight ? const Color(0xFFE8F8EE) : const Color(0xFFDCDCDC);
    final bgColor = widget.highlight ? const Color(0xFF183A24) : const Color(0xFF261C30);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTap: () {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor.withOpacity(widget.highlight ? 0.75 : 0.45), width: 1),
          boxShadow: _pressed
              ? [BoxShadow(color: borderColor.withOpacity(0.55), blurRadius: 20, spreadRadius: 1)]
              : (widget.highlight
                  ? [BoxShadow(color: borderColor.withOpacity(0.35), blurRadius: 12, spreadRadius: 0.5)]
                  : [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2))]),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Text(widget.label,
                style: TextStyle(fontSize: 17, color: textColor, letterSpacing: 2, fontWeight: widget.highlight ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
