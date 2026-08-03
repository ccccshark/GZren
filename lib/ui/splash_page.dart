// splash_page.dart
// V3.1 闪屏启动页：addPostFrameCallback → 先渲染 UI → 后台异步分批加载 → 完成跳转。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gzren/engine/command.dart';
import 'package:gzren/ui/disclaimer_dialog.dart';

/// 加载阶段进度枚举。
enum _LoadPhase {
  init,
  guList,
  map,
  recipe,
  npc,
  material,
  event,
  region,
  environment,
  quest,
  done,
}

const _phaseNames = {
  _LoadPhase.init: '正在初始化...',
  _LoadPhase.guList: '加载蛊虫数据...',
  _LoadPhase.map: '加载地图数据...',
  _LoadPhase.recipe: '加载蛊方数据...',
  _LoadPhase.npc: '加载NPC数据...',
  _LoadPhase.material: '加载材料数据...',
  _LoadPhase.event: '加载事件数据...',
  _LoadPhase.region: '加载区域数据...',
  _LoadPhase.environment: '加载环境配置...',
  _LoadPhase.quest: '加载任务系统...',
  _LoadPhase.done: '加载完成',
};

class SplashPage extends StatefulWidget {
  final Widget Function(GameContext ctx) onInitialized;
  const SplashPage({super.key, required this.onInitialized});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  // 【修复】V3.2 GameContext 改为 late 懒加载，不在字段初始化器创建，
  // 防止构造函数异常阻塞首帧渲染。在 _loadInBatches() 首次调用时初始化。
  late final GameContext _ctx;
  _LoadPhase _phase = _LoadPhase.init;
  bool _hasError = false;
  String _errorMessage = '';
  bool _ctxInitialized = false;

  @override
  void initState() {
    super.initState();
    // ① 先渲染 UI（首帧只显示标题+加载动画，不执行任何数据加载）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ② 首帧渲染完成后，开始异步分批加载
      _loadInBatches();
    });
  }

  // 分批加载：每批加载完成后更新状态文字，释放 UI 事件循环
  Future<void> _loadInBatches() async {
    try {
      // 【修复】V3.2 首次加载时创建 GameContext，不阻塞首帧渲染
      if (!_ctxInitialized) {
        _ctx = GameContext();
        _ctxInitialized = true;
      }
      // 第1批：蛊虫（核心，失败则无法继续）
      await _safeBatch(_LoadPhase.guList, () => _ctx.loadStaticGuList());
      if (!mounted) return;

      // 每批之间让出微任务队列，防止 UI 卡顿
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // 第2批：地图（核心，失败则无法继续）
      await _safeBatch(_LoadPhase.map, () => _ctx.loadStaticMap());
      if (!mounted) return;

      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // 第3批：蛊方
      await _safeBatch(_LoadPhase.recipe, () => _ctx.loadStaticRecipe());
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // 第4批：NPC模板
      await _safeBatch(_LoadPhase.npc, () => _ctx.loadStaticNpc());
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // 第5批：材料
      await _safeBatch(_LoadPhase.material, () => _ctx.loadStaticMaterial());
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // 第6批：随机事件
      await _safeBatch(_LoadPhase.event, () => _ctx.loadStaticEvent());
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // 第7批：南疆区域数据
      await _safeBatch(_LoadPhase.region, () => _ctx.loadStaticRegion());
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // 第8批：环境配置
      await _safeBatch(_LoadPhase.environment, () => _ctx.loadStaticEnvironment());
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // 第9批：任务系统
      await _safeBatch(_LoadPhase.quest, () => _ctx.loadStaticQuest());
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // 所有资源加载完成，标记完成
      _setPhase(_LoadPhase.done);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      // 展示免责声明弹窗
      final accepted = await showStartupDisclaimer(context);
      if (!mounted) return;

      if (accepted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => widget.onInitialized(_ctx)),
        );
      }
    } catch (e, stack) {
      if (!mounted) return;
      debugPrint('SplashPage 分批加载异常: $e\n$stack');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
      _showErrorDialog();
    }
  }

  // 执行单批加载，失败时抛出异常中断流程
  Future<void> _safeBatch(_LoadPhase phase, Future<void> Function() loader) async {
    _setPhase(phase);
    await loader();
  }

  void _setPhase(_LoadPhase p) {
    if (mounted) setState(() => _phase = p);
  }

  void _showErrorDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '初始化失败',
          style: TextStyle(color: Colors.redAccent, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Text(
            '游戏资源加载异常，请尝试重新安装。\n\n错误: $_errorMessage',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _hasError = false;
                _errorMessage = '';
                _phase = _LoadPhase.init;
              });
              // 重新加载
              WidgetsBinding.instance.addPostFrameCallback((_) => _loadInBatches());
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF9D5CD0)),
            child: const Text('重试'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              SystemNavigator.pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phaseName = _phaseNames[_phase] ?? '加载中...';
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0D),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '蛊 真 人',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Color(0xFF9D5CD0),
                letterSpacing: 14,
                fontFamilyFallback: ['serif'],
                shadows: [
                  Shadow(color: Color(0xFF9D5CD0), blurRadius: 20),
                  Shadow(color: Color(0xFF593475), blurRadius: 40),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '单机文字MUD',
              style: TextStyle(
                color: Color(0xFF8C7DA0),
                fontSize: 14,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 60),
            if (!_hasError)
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  color: Color(0xFF9D5CD0),
                  strokeWidth: 3,
                ),
              )
            else
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 36,
              ),
            const SizedBox(height: 24),
            Text(
              _hasError ? '初始化失败' : phaseName,
              style: TextStyle(
                color: _hasError ? Colors.redAccent : const Color(0xFF9D5CD0),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}