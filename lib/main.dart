// main.dart
// 蛊真人单机文字MUD（安卓端）APP 入口。纯离线，无任何联网功能。
// V3.4 启动修复：
//   - 移除 runZonedGuarded 包裹 runApp（反模式：吞掉 widget build 异常的默认红屏渲染，
//     导致 release 模式下任何 build 抛错都看不到反馈，背景又是 #0A0A0D 深黑 → 用户只看到黑屏）
//   - 加 ErrorWidget.builder：任何 widget build 异常都显示错误文字，不再黑屏
//   - FlutterError.onError 调用 FlutterError.presentError 保留默认渲染
//   - 不再静默 debugPrint（防止关键错误被吞）
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
  // 【必须最先】WidgetsFlutterBinding 初始化，否则 PaintingBinding 等无法访问。
  WidgetsFlutterBinding.ensureInitialized();

  // V2.0 内存优化【图片缓存限制】：纯文字游戏无大图，限制 Flutter 图片缓存为最小值。
  // 注意：放在 ErrorWidget.builder 之前，避免此处异常也无反馈。
  PaintingBinding.instance.imageCache.maximumSize = 20;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 2 * 1024 * 1024;

  // 【V3.4 关键修复】ErrorWidget.builder：当任何 widget build/layout 抛异常时，
  // Flutter 会渲染此 builder 返回的 widget 替代默认红屏。
  // release 模式默认 ErrorWidget 只显示 "Exception caught" 浅色文字，
  // 在深色背景上几乎不可见 → 这是黑屏无反应的直接原因之一。
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF0A0A0D),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    '应用渲染异常',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    details.exception.toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '请截图反馈给开发者，重启 App 可重试。',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };

  // FlutterError.onError：捕获 Flutter 框架层渲染/布局/管线异常。
  // 调用 FlutterError.presentError 让 ErrorWidget.builder 渲染错误界面。
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    final msg = details.exceptionAsString();
    final stack = details.stack?.toString() ?? '';
    debugPrint('FlutterError.onError: $msg\n$stack');
    if (kReleaseMode) {
      // 异步写日志，不阻塞渲染。
      writeErrorLog('FlutterError', msg, stack: stack);
    }
  };

  // PlatformDispatcher.onError：捕获 Dart 层未处理的异步异常。
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher.onError: $error\n$stack');
    if (kReleaseMode) {
      writeErrorLog('DartError', error.toString(), stack: stack.toString());
    }
    return true;
  };

  // 【V3.4 关键修复】直接 runApp，不再用 runZonedGuarded 包裹。
  // runZonedGuarded 包裹 runApp 是反模式：会让 Flutter framework 在 guarded zone 内
  // 运行，导致 widget build 异常被 zone 吞掉（只调用我们写日志的 handler），
  // 而 ErrorWidget 默认渲染被跳过 → 黑屏无反馈。
  runApp(const GuZhenRenApp());
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