// main.dart
// 蛊真人单机文字MUD（安卓端）APP 入口。纯离线，无任何联网功能。
import 'package:flutter/material.dart';
import 'engine/command.dart';
import 'ui/main_game_page.dart';
import 'ui/save_menu.dart';
import 'ui/help_page.dart';
import 'ui/disclaimer_dialog.dart';

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
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFF8E44AD),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8E44AD),
          secondary: Color(0xFF27AE60),
          surface: Color(0xFF1E1E1E),
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
        body: Center(child: CircularProgressIndicator(color: Color(0xFF8E44AD))),
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
        backgroundColor: const Color(0xFF2C1E3A),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('蛊 真 人', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF8E44AD))),
              const SizedBox(height: 8),
              const Text('单机文字MUD · 纯离线', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),
              _menuBtn(context, '新建角色', Icons.person_add, () => _newGame(context)),
              _menuBtn(context, '读取存档', Icons.save, () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SaveMenuPage(ctx: ctx, mode: SaveMenuMode.load)))),
              _menuBtn(context, '游戏说明', Icons.help_outline, () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const HelpPage()))),
              _menuBtn(context, '退出', Icons.exit_to_app, () => Navigator.of(context).maybePop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuBtn(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          icon: Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 18)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2C1E3A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onTap,
        ),
      ),
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
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainGamePage(ctx: ctx)));
              },
              child: const Text('开始'),
            ),
          ],
        ),
      ),
    );
  }
}
