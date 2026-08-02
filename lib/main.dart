// main.dart
// 蛊真人单机文字MUD（安卓端）APP 入口。纯离线，无任何联网功能。
// V3.1 启动修复：WidgetsFlutterBinding 置顶 + 三层异常捕获 + 写本地错误日志。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:gzren/utils/safe_json_loader.dart' show writeErrorLog;
import 'engine/command.dart';
import 'engine/save_system.dart' as sv;
import 'ui/main_game_page.dart';
import 'ui/save_menu.dart';
import 'ui/help_page.dart';
import 'ui/disclaimer_dialog.dart';
import 'ui/save_code_dialog.dart';
import 'ui/panels.dart';
import 'ui/splash_page.dart';

void main() {
  // 【修复】WidgetsFlutterBinding 必须最先初始化，否则 PaintingBinding 等无法访问。
  WidgetsFlutterBinding.ensureInitialized();

  // V2.0 内存优化【关闭 Debug 多余检测】：release 模式下禁用调试断言与 painting 检测。
  if (kReleaseMode) {
    debugPrint = (_, {int? wrapWidth}) {}; // 静默 debugPrint，减少字符串拼接开销
    debugDefaultTargetPlatformOverride = null;
  }
  // V2.0 内存优化【图片缓存限制】：纯文字游戏无大图，限制 Flutter 图片缓存为最小值。
  PaintingBinding.instance.imageCache.maximumSize = 20;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 2 * 1024 * 1024;

  // 【修复】FlutterError.onError：捕获 Flutter 框架层渲染/布局/管线异常，防止永久白屏。
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    final stack = details.stack?.toString() ?? '';
    debugPrint('FlutterError.onError: $msg\n$stack');
    // 非 debug 模式写入本地日志
    if (kReleaseMode) {
      writeErrorLog('FlutterError', msg, stack: stack);
    }
  };

  // 【修复】PlatformDispatcher.onError：捕获 Dart 层未处理的异步异常。
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher.onError: $error\n$stack');
    if (kReleaseMode) {
      writeErrorLog('DartError', error.toString(), stack: stack.toString());
    }
    return true; // 已处理，不终止进程
  };

  // 【修复】runZonedGuarded：捕获 runApp 同步初始化异常 + zone 内未捕获异常。
  runZonedGuarded(() {
    runApp(const GuZhenRenApp());
  }, (Object error, StackTrace stack) {
    final msg = 'runZonedGuarded: $error';
    debugPrint('$msg\n$stack');
    if (kReleaseMode) {
      writeErrorLog('ZoneError', error.toString(), stack: stack.toString());
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
        scaffoldBackgroundColor: const Color(0xFF0A0A0D),
        primaryColor: const Color(0xFF593475),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF593475),
          secondary: Color(0xFF9D5CD0),
          surface: Color(0xFF14101A),
        ),
        fontFamily: 'monospace',
      ),
      // V3.1 闪屏首页：先渲染 UI，addPostFrameCallback 后异步分批加载数据。
      home: SplashPage(onInitialized: (ctx) => MainMenuPage(ctx: ctx)),
    );
  }
}

// ===================== 主菜单页面 =====================

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
          Positioned.fill(child: CustomPaint(painter: _ScrollPatternPainter())),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                  if (_hasAutoSave == true)
                    _menuBtn(context, '继续游戏', Icons.play_arrow, () => _continueGame(context),
                        highlight: true),
                  _menuBtn(context, '新建角色', Icons.person_add, () => _newGame(context)),
                  _menuBtn(context, '读取存档', Icons.save, () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SaveMenuPage(ctx: ctx, mode: SaveMenuMode.load)))),
                  _menuBtn(context, '存档码备份', Icons.qr_code, () => showSaveCodeBackup(context, ctx)),
                  _menuBtn(context, '新手引导', Icons.school, () => showTutorialGuide(context, ctx, forceShow: true)),
                  _menuBtn(context, '游戏说明', Icons.help_outline, () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const HelpPage()))),
                  _menuBtn(context, '退出', Icons.exit_to_app, () => Navigator.of(context).maybePop()),
                  const SizedBox(height: 28),
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

// ===================== 主菜单 UI 美化组件 =====================

class _ScrollPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF9D5CD0).withOpacity(0.04)
      ..strokeWidth = 1;
    const step = 30.0;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
    }
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