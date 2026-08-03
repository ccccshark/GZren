// splash_page.dart
// V3.3 闪屏启动页：先渲染 UI → 异步加载资源 → 跳转主界面。
// 【V3.3】移除 compute Isolate（364KB JSON 直接解析），加整体超时保护。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gzren/engine/command.dart';
import 'package:gzren/ui/disclaimer_dialog.dart';

class SplashPage extends StatefulWidget {
  final Widget Function(GameContext ctx) onInitialized;
  const SplashPage({super.key, required this.onInitialized});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  late GameContext _ctx;
  String _statusText = '正在初始化...';
  bool _hasError = false;
  String _errorMessage = '';
  bool _ctxReady = false;

  @override
  void initState() {
    super.initState();
    // 首帧渲染后再开始加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLoading();
    });
  }

  Future<void> _startLoading() async {
    try {
      // 创建 GameContext
      _ctx = GameContext();
      _ctxReady = true;

      // 整体超时保护：30 秒未完成则报错
      await _loadAll().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('资源加载超时（30s），请重试');
        },
      );

      if (!mounted) return;

      setState(() => _statusText = '加载完成');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      // 展示免责声明
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
      debugPrint('SplashPage 加载异常: $e\n$stack');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _statusText = '初始化失败';
      });
    }
  }

  Future<void> _loadAll() async {
    // 依次加载各资源，每步更新状态文字
    setState(() => _statusText = '加载蛊虫数据...');
    await _ctx.loadStaticGuList();
    if (!mounted) return;

    setState(() => _statusText = '加载地图数据...');
    await _ctx.loadStaticMap();
    if (!mounted) return;

    setState(() => _statusText = '加载蛊方数据...');
    await _ctx.loadStaticRecipe();
    if (!mounted) return;

    setState(() => _statusText = '加载NPC数据...');
    await _ctx.loadStaticNpc();
    if (!mounted) return;

    setState(() => _statusText = '加载材料数据...');
    await _ctx.loadStaticMaterial();
    if (!mounted) return;

    setState(() => _statusText = '加载事件数据...');
    await _ctx.loadStaticEvent();
    if (!mounted) return;

    setState(() => _statusText = '加载区域数据...');
    await _ctx.loadStaticRegion();
    if (!mounted) return;

    setState(() => _statusText = '加载环境配置...');
    await _ctx.loadStaticEnvironment();
    if (!mounted) return;

    setState(() => _statusText = '加载任务系统...');
    await _ctx.loadStaticQuest();
    if (!mounted) return;

    // 初始化 NPC AI
    _ctx.npcAi = NPCAI(_ctx.guList);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0D),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 标题
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
            // 加载指示器或错误图标
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
            // 状态文字
            Text(
              _statusText,
              style: TextStyle(
                color: _hasError ? Colors.redAccent : const Color(0xFF9D5CD0),
                fontSize: 14,
              ),
            ),
            // 错误时显示重试按钮
            if (_hasError) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _errorMessage = '';
                    _statusText = '正在重试...';
                  });
                  _startLoading();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF593475),
                  foregroundColor: Colors.white,
                ),
                child: const Text('重试'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text('退出', style: TextStyle(color: Colors.white54)),
              ),
              // 显示错误详情（可折叠）
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SelectableText(
                  _errorMessage,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
