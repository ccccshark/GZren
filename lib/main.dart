// main.dart
// 蛊真人单机文字MUD（安卓端）APP 入口。纯离线，无任何联网功能。
import 'package:flutter/material.dart';
import 'engine/command.dart';
import 'ui/main_game_page.dart';
import 'ui/save_menu.dart';
import 'ui/help_page.dart';
import 'ui/disclaimer_dialog.dart';
import 'ui/save_code_dialog.dart';
import 'ui/panels.dart'; // 第一阶段新增：新手引导面板

void main() {
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

class MainMenuPage extends StatelessWidget {
  final GameContext ctx;
  const MainMenuPage({super.key, required this.ctx});

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

  Widget _menuBtn(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    // UI美化：圆角16、底色#261C30、淡紫细描边，按压柔光晕动效（封装于 _GlowMenuButton，仅样式）
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: _GlowMenuButton(label: label, icon: icon, onTap: onTap),
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
class _GlowMenuButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GlowMenuButton({required this.label, required this.icon, required this.onTap});
  @override
  State<_GlowMenuButton> createState() => _GlowMenuButtonState();
}

class _GlowMenuButtonState extends State<_GlowMenuButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
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
          color: const Color(0xFF261C30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF9D5CD0).withOpacity(0.45), width: 1),
          boxShadow: _pressed
              ? [BoxShadow(color: const Color(0xFF9D5CD0).withOpacity(0.55), blurRadius: 20, spreadRadius: 1)]
              : [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: const Color(0xFF9D5CD0), size: 20),
            const SizedBox(width: 12),
            Text(widget.label,
                style: const TextStyle(fontSize: 17, color: Color(0xFFDCDCDC), letterSpacing: 2)),
          ],
        ),
      ),
    );
  }
}
