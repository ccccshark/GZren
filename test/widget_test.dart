// widget_test.dart
// Widget 测试：HelpPage 静态渲染、MainMenuPage 菜单显示、MainGamePage 输入与快捷按钮。
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:gzren/main.dart';
import 'package:gzren/engine/command.dart';
import 'package:gzren/ui/help_page.dart';
import 'package:gzren/ui/main_game_page.dart';

// ---------- 测试用辅助：将 assets 重定向到磁盘文件 + 临时存档目录 ----------
class _DiskAssetBundle extends CachingAssetBundle {
  final String assetsRoot;
  _DiskAssetBundle(this.assetsRoot);
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    // key 形如 'assets/static/xxx.json'
    final path = '$assetsRoot/${key.replaceFirst("assets/", "")}';
    return File(path).readAsString();
  }

  @override
  Future<ByteData> load(String key) async {
    final str = await loadString(key);
    return ByteData.sublistView(utf8.encode(str));
  }
}

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final Directory dir;
  _FakePathProvider(this.dir);
  @override
  Future<Directory?> getApplicationDocumentsPath() async => dir;
}

Future<void> _loadAssets(GameContext ctx) async {
  // flutter_test 默认 rootBundle 不能读取真实文件，这里通过 override 替换。
  // 简化：直接读取磁盘文件喂给 GameContext.loadStatic。
  // 但 loadStatic 内部已用 rootBundle，故需通过 setMockMessageHandler 替换。
  TestWidgetsFlutterBinding.ensureInitialized();
  final assetsRoot = Directory.current.path + '/assets/static';
  // 注册 asset 路径回源
  // 使用 services 二进制消息通道 mock
  ByteData? _handler(String channel, ByteData? msg) {
    return null;
  }
  // 简化做法：用 _DiskAssetBundle 直接构造然后调用底层数据加载。
  // 这里采用更直接的办法：把所有 JSON 解析逻辑复制到测试中以验证 GameContext。
  // 为避免重复，我们直接调用 ctx.loadStatic()，并通过 rootBundle mock。

  // 注册 platform asset channel
  ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      final file = File('$assetsRoot/$key'.replaceAll('assets/static/', ''));
      // 上面拼接逻辑修正：key 即 'assets/static/xxx.json'
      final path = '$assetsRoot/${key.substring('assets/static/'.length)}';
      if (File(path).existsSync()) {
        final bytes = File(path).readAsBytesSync();
        return ByteData.sublistView(bytes);
      }
      return null;
    },
  );
  await ctx.loadStatic();
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('guzhenren_widget_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir);
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
  });

  group('HelpPage', () {
    testWidgets('渲染所有指令分区标题', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HelpPage()));
      await tester.pumpAndSettle();
      expect(find.text('游戏说明'), findsOneWidget);
      expect(find.text('移动与场景'), findsOneWidget);
      expect(find.text('角色状态'), findsOneWidget);
      expect(find.text('蛊虫操作'), findsOneWidget);
      expect(find.text('NPC交互'), findsOneWidget);
      expect(find.text('生存行为'), findsOneWidget);
      expect(find.text('系统指令'), findsOneWidget);
      expect(find.text('核心规则'), findsOneWidget);
    });

    testWidgets('显示关键指令', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HelpPage()));
      await tester.pumpAndSettle();
      expect(find.text('look'), findsOneWidget);
      expect(find.text('status'), findsOneWidget);
      expect(find.text('capture [目标]'), findsOneWidget);
      expect(find.text('save [1~5]'), findsOneWidget);
      expect(find.text('quit'), findsOneWidget);
    });

    testWidgets('显示纯离线声明', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HelpPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('纯单机离线'), findsOneWidget);
    });
  });

  group('MainMenuPage', () {
    testWidgets('渲染启动菜单 4 个按钮', (tester) async {
      final ctx = GameContext();
      await _loadAssets(ctx);
      await tester.pumpWidget(MaterialApp(home: MainMenuPage(ctx: ctx)));
      await tester.pumpAndSettle();
      expect(find.text('蛊 真 人'), findsOneWidget);
      expect(find.text('新建角色'), findsOneWidget);
      expect(find.text('读取存档'), findsOneWidget);
      expect(find.text('游戏说明'), findsOneWidget);
      expect(find.text('退出'), findsOneWidget);
    });

    testWidgets('点击游戏说明跳转 HelpPage', (tester) async {
      final ctx = GameContext();
      await _loadAssets(ctx);
      await tester.pumpWidget(MaterialApp(home: MainMenuPage(ctx: ctx)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('游戏说明'));
      await tester.pumpAndSettle();
      expect(find.text('游戏说明'), findsWidgets); // AppBar 标题
      expect(find.text('移动与场景'), findsOneWidget);
    });

    testWidgets('点击新建角色弹出对话框', (tester) async {
      final ctx = GameContext();
      await _loadAssets(ctx);
      await tester.pumpWidget(MaterialApp(home: MainMenuPage(ctx: ctx)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();
      expect(find.text('角色创建'), findsOneWidget);
      expect(find.text('阵营'), findsOneWidget);
      expect(find.text('正道'), findsOneWidget);
      expect(find.text('魔道'), findsOneWidget);
      expect(find.text('中立'), findsOneWidget);
      expect(find.text('开始'), findsOneWidget);
    });
  });

  group('MainGamePage', () {
    testWidgets('快捷按钮点击触发对应指令', (tester) async {
      final ctx = GameContext();
      await _loadAssets(ctx);
      ctx.newGame('方源', '魔道');
      await tester.pumpWidget(MaterialApp(home: MainGamePage(ctx: ctx)));
      await tester.pumpAndSettle();
      // 初始 look 已执行，日志中应有场景信息
      expect(find.textContaining('青茅山山脚'), findsWidgets);
      // 点击「状态」快捷按钮
      await tester.tap(find.text('状态'));
      await tester.pumpAndSettle();
      expect(find.textContaining('角色状态'), findsWidgets);
      expect(find.textContaining('方源'), findsWidgets);
      // 点击「采集」
      await tester.tap(find.text('采集'));
      await tester.pumpAndSettle();
      expect(find.textContaining('采集到'), findsWidgets);
    });

    testWidgets('输入框输入 help 显示指令列表', (tester) async {
      final ctx = GameContext();
      await _loadAssets(ctx);
      ctx.newGame('方源', '中立');
      await tester.pumpWidget(MaterialApp(home: MainGamePage(ctx: ctx)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'help');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.textContaining('指令列表'), findsWidgets);
    });

    testWidgets('顶部 AppBar 显示角色名', (tester) async {
      final ctx = GameContext();
      await _loadAssets(ctx);
      ctx.newGame('独孤求败', '正道');
      await tester.pumpWidget(MaterialApp(home: MainGamePage(ctx: ctx)));
      await tester.pumpAndSettle();
      expect(find.text('独孤求败'), findsOneWidget);
    });

    testWidgets('移动指令 go north 切换场景', (tester) async {
      final ctx = GameContext();
      await _loadAssets(ctx);
      ctx.newGame('方源', '中立');
      await tester.pumpWidget(MaterialApp(home: MainGamePage(ctx: ctx)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('向北'));
      await tester.pumpAndSettle();
      // 从青茅山山脚向北 -> 青茅山山腰
      expect(find.textContaining('青茅山山腰'), findsWidgets);
    });
  });
}
