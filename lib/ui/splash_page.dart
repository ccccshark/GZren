// splash_page.dart
// V3.0 闪屏启动页：先展示加载界面，后台异步初始化游戏数据，初始化完成再跳转主菜单。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gzren/engine/command.dart';
import 'package:gzren/ui/disclaimer_dialog.dart';

class SplashPage extends StatefulWidget {
  /// 初始化完成后的回调，由 main.dart 传入，负责跳转主菜单页面。
  final Widget Function(GameContext ctx) onInitialized;

  const SplashPage({super.key, required this.onInitialized});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final GameContext _ctx = GameContext();
  String _statusText = '正在初始化...';
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  Future<void> _initGame() async {
    try {
      setState(() => _statusText = '正在加载游戏数据...');

      // 异步加载全部静态资源（JSON 解析内部已包裹 try-catch）
      await _ctx.loadStatic();

      if (!mounted) return;

      setState(() => _statusText = '加载完成');

      // 短暂延迟让用户看到"加载完成"
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      // 展示免责声明弹窗
      final accepted = await showStartupDisclaimer(context);
      if (!mounted) return;

      if (accepted) {
        // 跳转主菜单页面（由回调构建）
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => widget.onInitialized(_ctx)),
        );
      }
      // 用户拒绝 → showStartupDisclaimer 内部已调用 SystemNavigator.pop()
    } catch (e, stack) {
      // 全局兜底：loadStatic 内部 try-catch 漏掉的异常在此捕获
      if (!mounted) return;
      debugPrint('SplashPage 初始化异常: $e\n$stack');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _statusText = '初始化失败';
      });
      _showErrorDialog();
    }
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
            '游戏资源加载异常，请检查安装包完整性后重试。\n\n错误: $_errorMessage',
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
                _statusText = '正在重试...';
              });
              _initGame();
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0D),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 游戏标题
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
            // 加载指示器
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
          ],
        ),
      ),
    );
  }
}