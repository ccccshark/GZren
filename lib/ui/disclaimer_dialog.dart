// disclaimer_dialog.dart
// 启动开屏免责声明弹窗：App 启动后最先弹出，用户必须点击【同意并进入】才可进入主菜单；
// 点击【拒绝】直接退出应用。可选复选框【下次启动不再弹出】，状态用 SharedPreferences 持久化。
//
// 设计原则：仅新增启动弹窗逻辑，不改动游戏引擎/存档/指令/JSON 资源。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kDisclaimerKey = 'disclaimer_accepted_v1';

/// 启动时检查是否需要展示免责声明弹窗。
/// 返回 true 表示可进入主菜单（已同意或之前勾选过"不再弹出"）；
/// 返回 false 表示用户拒绝，调用方应退出 App。
Future<bool> showStartupDisclaimer(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kDisclaimerKey) == true) {
    return true; // 之前已同意且勾选"不再弹出"
  }
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false, // 不可点击外部关闭
    builder: (c) => const _DisclaimerDialog(),
  );
  if (accepted == true) return true;
  // 用户拒绝（或系统返回）→ 退出 App
  await SystemNavigator.pop();
  return false;
}

class _DisclaimerDialog extends StatefulWidget {
  const _DisclaimerDialog();

  @override
  State<_DisclaimerDialog> createState() => _DisclaimerDialogState();
}

class _DisclaimerDialogState extends State<_DisclaimerDialog> {
  bool _dontShowAgain = false;

  void _agree() async {
    if (_dontShowAgain) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDisclaimerKey, true);
    }
    Navigator.of(context).pop(true);
  }

  void _reject() {
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 屏蔽系统返回键关闭
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '免责与开源声明',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 正文支持滚动（内容较长时）
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListBody(
                    children: const [
                      _Item('1. 本项目为开源文字 MUD 游戏，仅用于个人学习、技术交流用途；'),
                      _Item('2. 《蛊真人》相关原著名称、世界观、人物、蛊虫设定版权归属原作者；本项目不商用、不售卖、不盈利；'),
                      _Item('3. 禁止将本项目二次打包用于商业盈利；'),
                      _Item('4. 游戏内所有剧情仅为同人创作，不代表现实价值观；'),
                      _Item('5. 项目代码开源，任何人可自由学习研究，传播时请附带本声明。'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 复选框：下次启动不再弹出
              InkWell(
                onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24, height: 24,
                      child: Checkbox(
                        value: _dontShowAgain,
                        onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
                        checkColor: Colors.white,
                        activeColor: const Color(0xFF8E44AD),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('下次启动不再弹出', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: _reject,
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE74C3C)),
            child: const Text('拒绝', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: _agree,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('同意并进入', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final String text;
  const _Item(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
      ),
    );
  }
}
