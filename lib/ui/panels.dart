// panels.dart
// 第一阶段基础体验完善优化·新增 UI 面板集合（增量文件，不动旧代码）。
// 包含 5 个面板：
//   1. MapNavPanel       —— 简易地图导航面板（点击场景信息弹出可视化出口列表）
//   2. QuickBarPanel     —— 自定义蛊虫快捷栏（玩家自选 3 只常用蛊一键催动）
//   3. StatusWarningDialog —— 状态预警弹窗（寿元低/真元不足/伤势/空窍受损）
//   4. InventoryClassifiedPanel —— 背包 UI 分类重构（材料/蛊方/空窍蛊/背包蛊分开展示）
//   5. TutorialGuide     —— 完整版新手分段弹窗引导（移动/采集/捉蛊/炼蛊/战斗）
// 设计原则：
//   - 触屏图形化优先：所有交互通过按钮/卡片点击完成
//   - 兼容老指令模式：面板内部最终仍调用 ctx.handle()，底层指令引擎零改动
//   - 100% 兼容旧存档：所有新状态写入 player.flags，旧存档 flags 无对应键时回退默认值
//   - 纯单机无网络：日志保存到 APP 私有目录，无任何联网行为
import 'package:flutter/material.dart';
import '../engine/command.dart';
import '../data_model/scene_model.dart';
import '../data_model/gu_model.dart';
import '../data_model/recipe_model.dart'; // MatParser
import '../data_model/poison_model.dart' show PoisonStore, PoisonRank, PoisonInstance;
import '../data_model/killer_move_model.dart' show KillerMoveStore, KillerMove;
import 'detail_dialogs.dart'; // 第三阶段新增：材料/蛊虫详情浮窗 + 域外通道封锁弹窗

// 通用配色（与 action_dialogs.dart 保持一致风格）
const Color _panelBg = Color(0xFF1E1E1E);
const Color _panelItemBg = Color(0xFF2C1E3A);
const Color _panelAccent = Color(0xFF8E44AD);

// 方向中文映射（与 command.dart doLook 中常量一致，独立复制避免改动旧代码）
const Map<String, String> _dirCN = {
  'north': '北', 'south': '南', 'east': '东', 'west': '西',
  'up': '上', 'down': '下', 'in': '内', 'out': '外',
};

// ===================== 1. 简易地图导航面板 =====================

/// 弹出地图导航面板：展示当前场景卡片 + 可视化出口列表，点击出口直接移动。
/// 由主界面点击场景信息行触发。底层调用 ctx.handle('go $dir')，完全兼容旧指令。
Future<void> showMapNavPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final room = ctx.curRoom();
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _panelBg,
      title: Row(children: [
        const Icon(Icons.map, color: _panelAccent, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('地图导航 · ${room.name}',
            style: const TextStyle(color: Colors.white, fontSize: 17))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: _MapNavContent(ctx: ctx, room: room),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ),
  );
}

class _MapNavContent extends StatelessWidget {
  final GameContext ctx;
  final Room room;
  const _MapNavContent({required this.ctx, required this.room});

  @override
  Widget build(BuildContext context) {
    final exits = room.exits.entries.toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前场景卡片
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1ABC9C).withOpacity(0.12),
              border: Border.all(color: const Color(0xFF1ABC9C), width: 1.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.location_on, color: Color(0xFF1ABC9C), size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text('当前：${room.name}',
                      style: const TextStyle(color: Color(0xFF1ABC9C), fontSize: 16, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 6),
                Text(room.description,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 出口标题
          Row(children: [
            const Icon(Icons.exit_to_app, color: Colors.white70, size: 18),
            const SizedBox(width: 6),
            Text('出口（共 ${exits.length} 条）',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          if (exits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('此处没有可见出口，或许需通过特殊方式离开。',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            )
          else
            // 出口网格：每个出口一张可点击卡片，显示方向 + 目标场景名
            // 第三阶段新增【14】：border_ 前缀目标显示封锁标识，点击弹出封锁提示
            // V1.6 加固【秘境入口提示】：目标 secret 以 need_gu_ 开头时，出口卡片显示锁形标识，
            //   点击仍走 go 指令（由引擎拦截并提示需持有对应蛊虫），不直接传送。
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.6,
              children: exits.map((e) {
                final dirCN = _dirCN[e.key] ?? e.key;
                final target = ctx.rooms[e.value];
                final targetName = target?.name ?? e.value;
                // V3.7 五域境界解锁：4 大关口（西漠/北原/东海/中州）改为境界判定，
                //   不再 UI 预拦截，直接走 go 指令由引擎解锁/放行/提示。
                //   仅太古遗迹等其它 border_ 仍由引擎封锁，UI 不再弹封锁弹窗。
                final isBorderPass = e.value == 'border_west_pass' ||
                    e.value == 'border_north_pass' ||
                    e.value == 'border_east_pass' ||
                    e.value == 'border_center_pass';
                final isBorderLocked = e.value.startsWith('border_') && !isBorderPass;
                // 秘境入口判定：目标房间 secret 字段以 need_gu_ 开头
                final isSecretLocked = target != null && target.secret.startsWith('need_gu_');
                return _exitCard(dirCN, e.key, targetName, () {
                  if (isBorderLocked) {
                    // 太古遗迹等持续封锁通道：弹出封锁提示，不执行传送
                    showBorderLockedDialog(context, targetName);
                  } else {
                    Navigator.pop(context);
                    ctx.handle('go ${e.key}');
                  }
                }, isBorder: isBorderLocked, isSecretLocked: isSecretLocked);
              }).toList(),
            ),
          const SizedBox(height: 6),
          // 提示行
          const Row(children: [
            Icon(Icons.info_outline, color: Colors.white38, size: 14),
            SizedBox(width: 4),
            Expanded(child: Text('点击出口卡片直接移动；也可继续使用 go north 等指令。',
                style: TextStyle(color: Colors.white38, fontSize: 11))),
          ]),
        ],
      ),
    );
  }

  Widget _exitCard(String dirCN, String dirKey, String targetName, VoidCallback onTap,
      {bool isBorder = false, bool isSecretLocked = false}) {
    // 第三阶段新增【14】：域外通道出口用红色封锁样式标识
    // V1.6 加固：秘境入口（need_gu_）用紫色虚线样式标识，提示需钥匙蛊
    final lockColor = const Color(0xFF8E44AD);
    final cardColor = isBorder
        ? const Color(0xFFE74C3C).withOpacity(0.15)
        : (isSecretLocked ? lockColor.withOpacity(0.12) : _panelItemBg);
    final borderColor = isBorder
        ? const Color(0xFFE74C3C)
        : (isSecretLocked ? lockColor : _panelAccent.withOpacity(0.4));
    final dirColor = isBorder
        ? const Color(0xFFE74C3C)
        : (isSecretLocked ? lockColor : _panelAccent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          // 第三阶段新增【13】：放大触控区域，垂直 padding 从 8 增至 12
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dirColor, shape: BoxShape.circle,
              ),
              child: Text(dirCN, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('向$dirCN', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                Text(targetName,
                    style: TextStyle(color: isBorder ? const Color(0xFFE74C3C) : Colors.white,
                        fontSize: 13, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (isBorder)
                  const Text('[禁制封锁]', style: TextStyle(color: Color(0xFFE74C3C), fontSize: 10)),
                if (isSecretLocked)
                  const Text('[秘境·需钥匙蛊]', style: TextStyle(color: Color(0xFF8E44AD), fontSize: 10)),
              ],
            )),
            Icon(isBorder ? Icons.lock : (isSecretLocked ? Icons.vpn_key : Icons.chevron_right),
                color: isBorder ? const Color(0xFFE74C3C) : (isSecretLocked ? lockColor : Colors.white38), size: 18),
          ]),
        ),
      ),
    );
  }
}

// ===================== 2. 自定义蛊虫快捷栏 =====================

/// 快捷栏编辑面板：列出当前空窍中可催动的蛊虫，玩家自选最多 3 只存入快捷栏。
/// 快捷栏数据存于 player.flags['quick_bar']（List<String>，元素为蛊虫 instId）。
/// 旧存档 flags 无此键 → 快捷栏为空，完全兼容。
Future<void> showQuickBarPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _panelBg,
      title: Row(children: [
        const Icon(Icons.flash_on, color: Color(0xFF1ABC9C), size: 22),
        const SizedBox(width: 8),
        const Expanded(child: Text('蛊虫快捷栏',
            style: TextStyle(color: Colors.white, fontSize: 17))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: _QuickBarContent(ctx: ctx),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ),
  );
}

class _QuickBarContent extends StatefulWidget {
  final GameContext ctx;
  const _QuickBarContent({required this.ctx});
  @override
  State<_QuickBarContent> createState() => _QuickBarContentState();
}

class _QuickBarContentState extends State<_QuickBarContent> {
  @override
  Widget build(BuildContext context) {
    final p = widget.ctx.player!;
    final slot = p.guInSlot; // 仅空窍中的蛊可被催动（useGu 引擎限制）
    final quick = widget.ctx.quickBar; // 当前已设快捷栏 instId 列表
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前快捷栏槽位
          const Text('当前快捷栏（最多 3 槽）',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(children: List.generate(3, (i) {
            final instId = i < quick.length ? quick[i] : null;
            GuInstance? g;
            if (instId != null) {
              for (final x in slot) {
                if (x.instId == instId) { g = x; break; }
              }
            }
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _quickSlot(i, g),
            ));
          })),
          const SizedBox(height: 10),
          const Divider(color: Colors.white24, height: 8),
          const SizedBox(height: 4),
          // 可选蛊虫列表
          const Text('空窍中的蛊虫（点击切换是否加入快捷栏）',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 6),
          if (slot.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('空窍中尚未安放蛊虫，先装备蛊后再设快捷栏。',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            )
          else
            ...slot.map((g) => _selectableGu(g, quick.contains(g.instId))),
          const SizedBox(height: 4),
          const Row(children: [
            Icon(Icons.info_outline, color: Colors.white38, size: 14),
            SizedBox(width: 4),
            Expanded(child: Text('催动快捷栏仍走 use 指令，耐久/真元消耗与原引擎一致。',
                style: TextStyle(color: Colors.white38, fontSize: 11))),
          ]),
        ],
      ),
    );
  }

  Widget _quickSlot(int idx, GuInstance? g) {
    final empty = g == null;
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: empty ? _panelItemBg.withOpacity(0.4) : const Color(0xFF1ABC9C).withOpacity(0.15),
        border: Border.all(
            color: empty ? Colors.white24 : const Color(0xFF1ABC9C), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: empty
          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add, color: Colors.white30, size: 20),
              Text('空槽 ${idx + 1}', style: const TextStyle(color: Colors.white30, fontSize: 11)),
            ])
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(g.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${g.rank}转 · ${g.school}', style: const TextStyle(color: Colors.white70, fontSize: 10)),
              Text('耐久 ${g.durability}/${g.durabilityMax}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ]),
    );
  }

  Widget _selectableGu(GuInstance g, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _toggle(g.instId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1ABC9C).withOpacity(0.18) : _panelItemBg,
            border: Border.all(
                color: selected ? const Color(0xFF1ABC9C) : Colors.white12, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? const Color(0xFF1ABC9C) : Colors.white54, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                Text('${g.rank}转 · ${g.school} · 耐久 ${g.durability}/${g.durabilityMax} · 真元消耗${g.costZhen}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  void _toggle(String instId) {
    final cur = widget.ctx.quickBar;
    List<String> next;
    if (cur.contains(instId)) {
      next = cur.where((e) => e != instId).toList();
    } else if (cur.length >= 3) {
      // 槽位已满：替换最后一个
      next = [...cur.sublist(0, 2), instId];
    } else {
      next = [...cur, instId];
    }
    widget.ctx.setQuickBar(next);
    setState(() {});
  }
}

/// 主界面快捷栏组件（横向 3 槽，点击即催动，长按编辑）。
/// 由主界面 body 嵌入。空槽显示提示，已设槽点击执行 use 指令。
class QuickBarStrip extends StatelessWidget {
  final GameContext ctx;
  final VoidCallback onEdit;
  const QuickBarStrip({super.key, required this.ctx, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final quick = ctx.quickBar;
    final slot = ctx.player?.guInSlot ?? <GuInstance>[];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: List.generate(3, (i) {
        final instId = i < quick.length ? quick[i] : null;
        GuInstance? g;
        if (instId != null) {
          for (final x in slot) {
            if (x.instId == instId) { g = x; break; }
          }
        }
        return Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: _stripSlot(context, i, g),
        ));
      })),
    );
  }

  Widget _stripSlot(BuildContext context, int idx, GuInstance? g) {
    final empty = g == null;
    // 第三阶段新增【13】：放大快捷栏触控区域，minimumSize 确保最小高度 48dp
    return GestureDetector(
      onLongPress: onEdit,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: empty ? const Color(0xFF1A1A1A) : const Color(0xFF1ABC9C).withOpacity(0.18),
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          side: BorderSide(
              color: empty ? Colors.white12 : const Color(0xFF1ABC9C), width: 1),
        ),
        onPressed: empty
            ? onEdit
            : () {
                ctx.handle('use ${g.instId}');
              },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(empty ? Icons.add : Icons.flash_on,
              color: empty ? Colors.white30 : const Color(0xFF1ABC9C), size: 18),
          const SizedBox(height: 2),
          Text(
            empty ? '设快捷' : g.name,
            style: TextStyle(
                fontSize: 11,
                color: empty ? Colors.white54 : Colors.white,
                fontWeight: empty ? FontWeight.normal : FontWeight.bold),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    );
  }
}

// ===================== 3. 状态预警弹窗 =====================

/// 状态预警弹窗：读取 ctx.warnings()，按类型显示预警条目。
/// 调用方应在 player 状态变化后调用（如 tick/战斗后）。
/// 返回 true 表示确认知悉；false 表示玩家选择"不再提示本次"。
/// 主动提示策略由调用方控制，本函数仅负责展示。
Future<void> showStatusWarningDialog(BuildContext context, GameContext ctx) async {
  final ws = ctx.warnings();
  if (ws.isEmpty) return;
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _panelBg,
      title: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFE67E22), size: 24),
        const SizedBox(width: 8),
        const Text('状态预警', style: TextStyle(color: Color(0xFFE67E22), fontSize: 18)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in ws)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE67E22).withOpacity(0.12),
                border: Border.all(color: const Color(0xFFE67E22), width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.priority_high, color: Color(0xFFE67E22), size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(w,
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4))),
              ]),
            ),
          const SizedBox(height: 4),
          const Text('提示：预警仅在状态危险时主动弹出。可继续游戏或静坐恢复。',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了')),
      ],
    ),
  );
}

// ===================== 4. 背包 UI 分类重构面板 =====================

/// 背包分类重构面板：将原 doInventory 的扁平输出拆分为 4 个分类卡片：
///   · 材料（非"蛊方"后缀的库存项）
///   · 蛊方（库存中名称以"蛊方"结尾的项）
///   · 空窍蛊（player.guInSlot，已装备可催动）
///   · 背包蛊（player.guBag，寄存未装备）
/// 纯展示，不修改任何状态。底层仍调用 ctx.handle('inventory') / ctx.handle('kuang') 兼容老指令。
Future<void> showInventoryClassifiedPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _panelBg,
      title: Row(children: [
        const Icon(Icons.inventory_2, color: _panelAccent, size: 22),
        const SizedBox(width: 8),
        const Expanded(child: Text('背包（分类视图）',
            style: TextStyle(color: Colors.white, fontSize: 17))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: _InventoryClassifiedContent(ctx: ctx),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ),
  );
}

class _InventoryClassifiedContent extends StatefulWidget {
  final GameContext ctx;
  const _InventoryClassifiedContent({required this.ctx});

  @override
  State<_InventoryClassifiedContent> createState() => _InventoryClassifiedContentState();
}

class _InventoryClassifiedContentState extends State<_InventoryClassifiedContent> {
  // V1.3 新增【背包优化】：分类标签切换 + 名称模糊搜索
  String _tab = 'all'; // all / material / recipe / gu
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  GameContext get ctx => widget.ctx;

  @override
  Widget build(BuildContext context) {
    final p = ctx.player!;
    // 拆分材料/蛊方（蛊方名以"蛊方"结尾；与 recipe.json 命名一致）
    final materials = <String, int>{};
    final recipes = <String, int>{};
    for (final it in p.inventory) {
      final (n, c) = MatParser.parse(it);
      if (n.endsWith('蛊方')) {
        recipes[n] = (recipes[n] ?? 0) + c;
      } else {
        materials[n] = (materials[n] ?? 0) + c;
      }
    }
    // 模糊搜索过滤
    final q = _query.trim().toLowerCase();
    bool match(String s) => q.isEmpty || s.toLowerCase().contains(q);
    final matsF = materials.entries.where((e) => match(e.key)).toList();
    final recipesF = recipes.entries.where((e) => match(e.key)).toList();
    final slotGuF = p.guInSlot.where((g) => match(g.name)).toList();
    final bagGuF = p.guBag.where((g) => match(g.name)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // V1.3 新增【模糊搜索框】
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索材料/蛊方/蛊虫名称…',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                      onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); },
                    ) : null,
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _panelAccent)),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          // V1.3 新增【分类标签切换】
          _tabBar(),
          const SizedBox(height: 8),
          // V1.3 新增【批量操作快捷栏】（仅材料标签显示批量出售）
          if (_tab == 'all' || _tab == 'material')
            _batchActionBar(materials),
          if (_tab == 'all' || _tab == 'material') ...[
            _sectionClickable('材料（采集/掉落/购买所得）', Icons.grain, const Color(0xFF27AE60),
                matsF.isEmpty
                    ? (q.isEmpty ? ['空空如也'] : ['未匹配到材料'])
                    : matsF.map((e) => '· ${e.key} x${e.value}').toList(),
                onTapItem: matsF.isEmpty ? null : (idx) {
                  showMaterialDetailDialog(context, ctx, matsF[idx].key);
                }),
            const SizedBox(height: 10),
          ],
          if (_tab == 'all' || _tab == 'recipe') ...[
            _section('蛊方（炼蛊配方，需配合材料）', Icons.menu_book, const Color(0xFFE67E22),
                recipesF.isEmpty
                    ? (q.isEmpty ? ['尚无蛊方'] : ['未匹配到蛊方'])
                    : recipesF.map((e) => '· ${e.key} x${e.value}').toList()),
            const SizedBox(height: 10),
          ],
          if (_tab == 'all' || _tab == 'gu') ...[
            // 第三阶段新增【13】：空窍蛊行可点击查看详情
            _sectionClickable('空窍蛊（已装备，可催动/投喂，点击查看详情）', Icons.bolt, const Color(0xFF1ABC9C),
                slotGuF.isEmpty
                    ? (q.isEmpty ? ['空窍空空，尚未安放蛊虫'] : ['未匹配到蛊虫'])
                    : slotGuF.map((g) => '· ${g.name}${g.mutated ? "[变异]" : ""}　${g.rank}转/${g.school}　耐久 ${g.durability}/${g.durabilityMax}　消耗${g.costZhen}真元').toList(),
                onTapItem: slotGuF.isEmpty ? null : (idx) {
                  showGuInstanceDetailDialog(context, ctx, slotGuF[idx]);
                }, highlight: true),
            const SizedBox(height: 10),
            // 第三阶段新增【13】：背包蛊行可点击查看详情
            _sectionClickable('背包蛊（寄存，需装备入空窍方可催动，点击查看详情）', Icons.bug_report, const Color(0xFF9B59B6),
                bagGuF.isEmpty
                    ? (q.isEmpty ? ['无寄存蛊虫'] : ['未匹配到蛊虫'])
                    : bagGuF.map((g) => '· ${g.name}${g.mutated ? "[变异]" : ""}　${g.rank}转/${g.school}　耐久 ${g.durability}/${g.durabilityMax}').toList(),
                onTapItem: bagGuF.isEmpty ? null : (idx) {
                  showGuInstanceDetailDialog(context, ctx, bagGuF[idx]);
                }),
          ],
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.info_outline, color: Colors.white38, size: 14),
            const SizedBox(width: 4),
            Expanded(child: Text('材料/蛊方合计 ${p.inventory.length} 项；空窍 ${p.guInSlot.length}/${p.effectiveSlotMax}。',
                style: const TextStyle(color: Colors.white38, fontSize: 11))),
          ]),
        ],
      ),
    );
  }

  /// V1.3 新增【分类标签栏】：全部/材料/蛊方/蛊虫 触屏切换。
  Widget _tabBar() {
    final tabs = [
      ('all', '全部', Icons.grid_view),
      ('material', '材料', Icons.grain),
      ('recipe', '蛊方', Icons.menu_book),
      ('gu', '蛊虫', Icons.bug_report),
    ];
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: tabs.map((t) {
          final active = _tab == t.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ElevatedButton.icon(
              icon: Icon(t.$3, size: 15),
              label: Text(t.$2, style: const TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: active ? const Color(0xFF8E44AD) : const Color(0xFF2C1E3A),
                foregroundColor: active ? Colors.white : Colors.white70,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => setState(() => _tab = t.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// V1.3 新增【批量操作栏】：批量出售（卖给当前场景商人，黑名单物品自动跳过）。
  Widget _batchActionBar(Map<String, int> materials) {
    // 仅当场景存在商人且有非黑名单材料时显示
    if (ctx.npcsInCurRoom().isEmpty || materials.isEmpty) return const SizedBox.shrink();
    final hasMerchant = ctx.npcsInCurRoom().any((n) => n.isMerchant);
    if (!hasMerchant) return const SizedBox.shrink();
    final sellable = materials.entries.where((e) => !ctx.isTradeBlacklisted(e.key)).toList();
    if (sellable.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.sell, size: 16),
          label: const Text('批量出售', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE67E22), foregroundColor: Colors.white,
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: () => _confirmBatchSell(sellable),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Text('一键出售全部可售材料（货币类自动跳过）',
            style: TextStyle(color: Colors.white38, fontSize: 10))),
      ]),
    );
  }

  /// V1.3 新增【批量出售确认】：列出将出售的材料与预估原石，确认后逐项出售。
  void _confirmBatchSell(List<MapEntry<String, int>> sellable) {
    final matInfo = (ctx.materials['materials'] ?? {}) as Map;
    int total = 0;
    final lines = <String>[];
    for (final e in sellable) {
      final priceInfo = ((matInfo[e.key] ?? {}) as Map)['price'] ?? 1;
      final price = ((priceInfo as num) * 0.6).toInt().clamp(1, 9999) * e.value;
      total += price;
      lines.add('· ${e.key} x${e.value} → $price 原石');
    }
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _panelBg,
        title: const Text('批量出售确认', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...lines.map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              )),
              const Divider(color: Colors.white24, height: 16),
              Text('合计预估获得：$total 原石',
                  style: const TextStyle(color: Color(0xFF27AE60), fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(c);
              for (final e in sellable) {
                ctx.doTradeAction('sell ${e.key} ${e.value}');
              }
              ctx.out('【批量出售】已出售 ${sellable.length} 种材料。', MsgType.fortune);
              setState(() {});
            },
            child: const Text('确认出售'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, Color color, List<String> items, {bool highlight = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(highlight ? 0.7 : 0.4), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(title,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 6),
        for (final s in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35)),
          ),
      ]),
    );
  }

  // 第三阶段新增【13】：可点击的 section，每行点击触发 onTapItem 回调
  Widget _sectionClickable(String title, IconData icon, Color color, List<String> items,
      {bool highlight = false, void Function(int idx)? onTapItem}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(highlight ? 0.7 : 0.4), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(title,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 6),
        if (onTapItem == null)
          for (final s in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35)),
            )
        else
          for (int i = 0; i < items.length; i++)
            // 第三阶段新增【13】：放大触控区域，垂直 padding 增至 6
            InkWell(
              onTap: () => onTapItem(i),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                margin: const EdgeInsets.only(bottom: 2),
                child: Text(items[i],
                    style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12, height: 1.35,
                        decoration: TextDecoration.underline, decorationColor: Colors.white24)),
              ),
            ),
      ]),
    );
  }
}

// ===================== 5. 完整版新手分段引导 =====================

/// 新手引导步骤定义。每完成一步调用 ctx.markTutorialDone(stepKey) 记入 player.flags。
/// 全部步骤完成后清除 player.flags['need_tutorial']，主界面不再自动弹出。
class _TutorialStep {
  final String key;
  final String title;
  final IconData icon;
  final Color color;
  final List<String> body; // 多段正文
  final String tip; // 操作提示
  const _TutorialStep(this.key, this.title, this.icon, this.color, this.body, this.tip);
}

const List<_TutorialStep> _tutorialSteps = [
  _TutorialStep('move', '一、移动与场景',
      Icons.navigation, Color(0xFF1ABC9C),
      ['欢迎来到蛊真人的世界。屏幕上方是文字输出区，会显示当前场景的描述、出口、野生蛊与 NPC。',
       '点击场景信息行（蓝色【场景名】）可弹出【地图导航面板】，看到所有出口的可视化卡片。',
       '点击出口卡片即可直接移动到相邻场景，无需手打指令。'],
      '试试点击日志中的【青茅山】或快捷按钮"场景"，再点击出口卡片移动。'),
  _TutorialStep('gather', '二、采集资源',
      Icons.grain, Color(0xFF27AE60),
      ['材料是炼蛊的基础。点击"采集"按钮可从当前场景获取资源（露水、青茅草根、原石等）。',
       '原石是通用货币，可与商人交易购买蛊方/材料；其他材料用于炼蛊或投喂蛊虫。',
       '采集会消耗时间，可能触发随机事件或野怪伏击，注意状态。'],
      '点击"采集"按钮试着采几次，看看背包里增加了什么。'),
  _TutorialStep('capture', '三、捉蛊',
      Icons.bug_report, Color(0xFF9B59B6),
      ['场景中出现的"野生蛊虫：青茅蛊, 月光蛊"行中，蛊名是黄色可点击的——直接点击即发起捕捉。',
       '也可点"更多操作"→"捕捉野蛊"从列表选择。捕捉消耗真元，有成功率，受境界与气运影响。',
       '捉到的蛊进入【背包蛊】寄存，需装备入空窍方可催动。'],
      '找到一只野生蛊，点击它的名字尝试捕捉。'),
  _TutorialStep('refine', '四、炼蛊',
      Icons.science, Color(0xFFE67E22),
      ['持有点"蛊方"+材料即可炼蛊。点"更多操作"→"炼蛊"会列出你持有的蛊方与材料齐备情况。',
       '炼蛊有成功率，失败会损毁材料，严重时被炸伤（新增伤势、体魄下降），极小概率炼出变异蛊。',
       '炼蛊造诣随次数提升，可提高成功率。'],
      '确认背包有"探路蛊蛊方"等蛊方与材料后，点"炼蛊"试试。'),
  _TutorialStep('combat', '五、战斗与突破',
      Icons.gavel, Color(0xFFE74C3C),
      ['点击日志中 NPC 名字（黄色）可弹出对话/交易/攻击菜单。敌对 NPC 会主动伏击。',
       '战斗中可选择催动空窍蛊攻击/防御，真元与耐久是关键资源。',
       '累积道痕后可"境界突破"，每次突破寿元上限提升；劫数满则触发天劫，失败即陨落。'],
      '试试与场景中的 NPC 对话，或就近采集/捉蛊壮大自己。'),
];

/// 完整版新手引导弹窗。分段显示 5 个步骤，玩家可"上一步/下一步"浏览。
/// 完成最后一步后标记引导完成。forceShow=true 时忽略完成状态强制弹出（供主菜单"重新查看"）。
/// 调用方负责决定是否调用（如主界面在 need_tutorial=true 时自动调用）。
Future<void> showTutorialGuide(BuildContext context, GameContext ctx, {bool forceShow = false}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (c) => _TutorialGuideDialog(ctx: ctx, forceShow: forceShow),
  );
}

class _TutorialGuideDialog extends StatefulWidget {
  final GameContext ctx;
  final bool forceShow;
  const _TutorialGuideDialog({required this.ctx, required this.forceShow});
  @override
  State<_TutorialGuideDialog> createState() => _TutorialGuideDialogState();
}

class _TutorialGuideDialogState extends State<_TutorialGuideDialog> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final step = _tutorialSteps[_idx];
    final isLast = _idx == _tutorialSteps.length - 1;
    final isFirst = _idx == 0;
    return AlertDialog(
      backgroundColor: _panelBg,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      title: Row(children: [
        Icon(step.icon, color: step.color, size: 24),
        const SizedBox(width: 8),
        Expanded(child: Text(step.title,
            style: TextStyle(color: step.color, fontSize: 17, fontWeight: FontWeight.bold))),
        if (widget.forceShow)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: '关闭',
          ),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 步骤进度指示
            Row(children: [
              for (int i = 0; i < _tutorialSteps.length; i++)
                Expanded(child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i <= _idx ? step.color : Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
            ]),
            const SizedBox(height: 12),
            // 正文
            for (final p in step.body)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
              ),
            // 操作提示卡
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: step.color.withOpacity(0.12),
                border: Border.all(color: step.color.withOpacity(0.5), width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lightbulb, color: step.color, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(step.tip,
                    style: TextStyle(color: step.color, fontSize: 12, height: 1.4))),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        if (!isFirst)
          TextButton(onPressed: () => setState(() => _idx--), child: const Text('上一步')),
        // 中间显示当前步数
        Text('${_idx + 1} / ${_tutorialSteps.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        if (!isLast)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: step.color, foregroundColor: Colors.white,
            ),
            onPressed: () {
              widget.ctx.markTutorialDone(step.key);
              setState(() => _idx++);
            },
            child: const Text('下一步'),
          )
        else
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: step.color, foregroundColor: Colors.white,
            ),
            onPressed: () {
              widget.ctx.markTutorialDone(step.key);
              // 全部完成：清除自动弹出标记
              widget.ctx.clearTutorialNeeded();
              Navigator.pop(context);
            },
            child: const Text('开始游戏'),
          ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }
}

// ===================== 6. 毒素中毒系统·毒素详情面板 =====================

/// 毒素详情面板：展示当前所有中毒状态、下次毒发倒计时、解毒建议。
/// 底层调用 ctx.handle('detox') / ctx.handle('rest') 等指令，完全兼容旧引擎。
Future<void> showPoisonDetailPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _panelBg,
      title: Row(children: [
        const Icon(Icons.science, color: Color(0xFF9D5CD0), size: 22),
        const SizedBox(width: 8),
        const Expanded(child: Text('中毒状态',
            style: TextStyle(color: Colors.white, fontSize: 17))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: _PoisonDetailContent(ctx: ctx),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ),
  );
}

class _PoisonDetailContent extends StatelessWidget {
  final GameContext ctx;
  const _PoisonDetailContent({required this.ctx});
  @override
  Widget build(BuildContext context) {
    final p = ctx.player!;
    final poisons = PoisonStore.list(p);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (poisons.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(children: [
                Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 20),
                SizedBox(width: 8),
                Text('体内无毒，经脉清明。', style: TextStyle(color: Colors.white, fontSize: 14)),
              ]),
            )
          else
            ...poisons.map((x) => _poisonCard(x)),
          const SizedBox(height: 10),
          const Divider(color: Colors.white24, height: 8),
          const SizedBox(height: 4),
          const Text('解毒途径',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _detoxWay('① 静坐休养', '缓慢代谢轻微毒素，高阶仅延缓', 'rest', context),
          _detoxWay('② 服解毒草药', '解轻微、压制烈性（重复衰减）', 'herb', context),
          _detoxWay('③ 催动解毒蛊', '主流手段，凡蛊不解道毒', 'use', context),
          _detoxWay('④ 燃烧寿元逼毒', '永久削寿，失败叠加', 'burnlife', context),
          _detoxWay('⑤ 以毒攻毒', '失败则毒素叠加', 'poisonattack', context),
          const SizedBox(height: 6),
          const Row(children: [
            Icon(Icons.info_outline, color: Colors.white38, size: 14),
            SizedBox(width: 4),
            Expanded(child: Text('凡蛊、草药无法解除道毒；毒素长期不清会留下永久暗伤。',
                style: TextStyle(color: Colors.white38, fontSize: 11))),
          ]),
        ],
      ),
    );
  }

  Widget _poisonCard(PoisonInstance x) {
    final color = switch (x.rank) {
      PoisonRank.minor  => const Color(0xFF27AE60),
      PoisonRank.fierce => const Color(0xFFE67E22),
      PoisonRank.odd    => const Color(0xFFE74C3C),
      PoisonRank.dao    => const Color(0xFF9D5CD0),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bug_report, color: color, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text('${x.name} [${x.rank.cn}]',
                style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 4),
          Text('威力 ${x.power}　周期 ${x.tickHours}h　下次毒发 ${x.hoursLeft.toStringAsFixed(0)}h 后',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text('累计毒发 ${x.tickCount} 次　来源：${x.source}',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _detoxWay(String title, String desc, String cmd, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.pop(context);
          if (cmd == 'rest' || cmd == 'herb' || cmd == 'use' ||
              cmd == 'burnlife' || cmd == 'poisonattack') {
            // 走"祛毒解毒"操作面板统一选择
            showDetoxActionPanel(context, ctx, initialCmd: cmd);
          } else {
            ctx.handle(cmd);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _panelItemBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _panelAccent.withOpacity(0.4), width: 1),
          ),
          child: Row(children: [
            const Icon(Icons.healing, color: _panelAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            )),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ]),
        ),
      ),
    );
  }
}

/// 祛毒操作面板：根据途径选择具体材料/蛊/年数，统一弹窗交互。
/// 底层仍调 ctx.handle()，不改动引擎。
Future<void> showDetoxActionPanel(BuildContext context, GameContext ctx,
    {String? initialCmd}) async {
  if (ctx.player == null) return;
  await showDialog(
    context: context,
    builder: (c) => _DetoxActionDialog(ctx: ctx, initialCmd: initialCmd ?? 'herb'),
  );
}

class _DetoxActionDialog extends StatefulWidget {
  final GameContext ctx;
  final String initialCmd;
  const _DetoxActionDialog({required this.ctx, required this.initialCmd});
  @override
  State<_DetoxActionDialog> createState() => _DetoxActionDialogState();
}

class _DetoxActionDialogState extends State<_DetoxActionDialog> {
  late String _cmd;

  @override
  void initState() {
    super.initState();
    _cmd = widget.initialCmd;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.ctx.player!;
    return AlertDialog(
      backgroundColor: _panelBg,
      title: const Text('祛毒解毒', style: TextStyle(color: Colors.white, fontSize: 17)),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 途径切换
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip('herb', '解毒草药', _cmd == 'herb'),
              _chip('use', '解毒蛊', _cmd == 'use'),
              _chip('burnlife', '燃烧寿元', _cmd == 'burnlife'),
              _chip('poisonattack', '以毒攻毒', _cmd == 'poisonattack'),
            ]),
            const SizedBox(height: 12),
            _buildBody(p),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }

  Widget _chip(String cmd, String label, bool active) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 12)),
      selected: active,
      selectedColor: _panelAccent,
      backgroundColor: _panelItemBg,
      onSelected: (_) => setState(() => _cmd = cmd),
    );
  }

  Widget _buildBody(p) {
    switch (_cmd) {
      case 'herb':
        return _herbList(p);
      case 'use':
        return _detoxGuList(p);
      case 'burnlife':
        return _burnLifeInput(p);
      case 'poisonattack':
        return _poisonAttackList(p);
      default:
        return const SizedBox.shrink();
    }
  }

  // ---- 解毒草药列表 ----
  Widget _herbList(p) {
    final herbs = <MapEntry<String, int>>[];
    for (final it in p.inventory) {
      final (n, c) = MatParser.parse(it);
      // 识别解毒草药：青茅草、银针花、解毒散
      if (['青茅草', '银针花', '解毒散'].contains(n)) {
        herbs.add(MapEntry(n, c));
      }
    }
    if (herbs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('背包无解毒草药。可向老槐翁购入青茅草、银针花、解毒散。',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('选择草药服用（重复使用效果衰减）：',
            style: TextStyle(color: Colors.white, fontSize: 13)),
        const SizedBox(height: 6),
        ...herbs.map((e) => _actionRow(e.key, 'x${e.value}', () {
          widget.ctx.handle('herb ${e.key}');
          Navigator.pop(context);
        })),
      ],
    );
  }

  // ---- 解毒蛊列表 ----
  Widget _detoxGuList(p) {
    final gus = p.guInSlot.where((g) =>
        g.combat['type'] == 'detox' && g.durability > 0).toList();
    if (gus.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('空窍中无可用解毒蛊。可通过炼蛊或捕捉获得。',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('选择解毒蛊催动：',
            style: TextStyle(color: Colors.white, fontSize: 13)),
        const SizedBox(height: 6),
        ...gus.map((g) => _actionRow(g.name, '${g.rank}转 耐久${g.durability}/${g.durabilityMax}', () {
          widget.ctx.handle('use ${g.instId}');
          Navigator.pop(context);
        })),
      ],
    );
  }

  // ---- 燃烧寿元输入 ----
  Widget _burnLifeInput(p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('当前寿元：${p.lifeLeft.toStringAsFixed(1)} 年',
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        const SizedBox(height: 4),
        const Text('燃烧寿元强行逼毒，永久削减寿元，失败则毒素叠加。建议留有余寿。',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _actionChip('燃烧 2 年', () {
            widget.ctx.handle('burnlife 2');
            Navigator.pop(context);
          }),
          _actionChip('燃烧 5 年', () {
            widget.ctx.handle('burnlife 5');
            Navigator.pop(context);
          }),
          _actionChip('燃烧 10 年', () {
            widget.ctx.handle('burnlife 10');
            Navigator.pop(context);
          }),
        ]),
      ],
    );
  }

  // ---- 以毒攻毒材料列表 ----
  Widget _poisonAttackList(p) {
    final attackMats = <MapEntry<String, int>>[];
    for (final it in p.inventory) {
      final (n, c) = MatParser.parse(it);
      if (['毒囊', '蛇蜕', '黑莲花瓣'].contains(n)) {
        attackMats.add(MapEntry(n, c));
      }
    }
    if (attackMats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('背包无可用于攻毒的毒物（毒囊/蛇蜕/黑莲花瓣）。',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('选择毒物以毒攻毒（失败则该毒叠加于身）：',
            style: TextStyle(color: Colors.white, fontSize: 13)),
        const SizedBox(height: 6),
        ...attackMats.map((e) => _actionRow(e.key, 'x${e.value}', () {
          widget.ctx.handle('poisonattack ${e.key}');
          Navigator.pop(context);
        })),
      ],
    );
  }

  Widget _actionRow(String title, String sub, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _panelItemBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _panelAccent.withOpacity(0.4), width: 1),
          ),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            )),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _actionChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: _panelAccent,
      onPressed: onTap,
    );
  }
}

// ===================== V1.3 新增【杀招自定义面板】 =====================

/// 杀招面板入口：列出已构筑杀招（释放/删除），支持新建组合（触屏勾选空窍+背包蛊）。
/// 自动校验：杀招清单自动剔除已丢失/死亡的蛊虫（cast 时由 KillerMoveStore 解析，不在空窍中即失效）。
/// 底层调用 ctx.handle('kmnew'/'km'/'kmdel')，与文字指令模式结果完全一致。
Future<void> showKillerMovePanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  await showDialog(
    context: context,
    builder: (c) => _KillerMoveDialog(ctx: ctx),
  );
}

class _KillerMoveDialog extends StatefulWidget {
  final GameContext ctx;
  const _KillerMoveDialog({required this.ctx});
  @override
  State<_KillerMoveDialog> createState() => _KillerMoveDialogState();
}

class _KillerMoveDialogState extends State<_KillerMoveDialog> {
  bool _creating = false;
  final _nameCtrl = TextEditingController();
  final Set<String> _selected = {}; // 选中的 instId

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.ctx.player!;
    final moves = KillerMoveStore.list(p);
    return AlertDialog(
      backgroundColor: _panelBg,
      title: Row(children: [
        const Icon(Icons.flash_on, color: Color(0xFFE67E22), size: 22),
        const SizedBox(width: 8),
        const Expanded(child: Text('杀招面板',
            style: TextStyle(color: Colors.white, fontSize: 17))),
        Text('${moves.length}/${KillerMoveStore.maxSlots}',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: _creating
            ? _buildCreateView(p)
            : _buildListView(p, moves),
      ),
      actions: [
        if (_creating)
          TextButton(
            onPressed: () => setState(() {
              _creating = false;
              _selected.clear();
              _nameCtrl.clear();
            }),
            child: const Text('返回'),
          )
        else if (moves.length < KillerMoveStore.maxSlots)
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('构筑新杀招'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60), foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => setState(() => _creating = true),
          )
        else
          const Padding(padding: EdgeInsets.only(right: 8),
              child: Text('杀招槽位已满', style: TextStyle(color: Colors.white54, fontSize: 12))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }

  /// 已构筑杀招列表视图。
  Widget _buildListView(p, List<KillerMove> moves) {
    if (moves.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.flash_off, color: Colors.white24, size: 48),
          SizedBox(height: 12),
          Text('尚未构筑任何杀招', style: TextStyle(color: Colors.white54, fontSize: 14)),
          SizedBox(height: 6),
          Text('杀招需组合 2~4 只蛊虫，同流派触发协同加成',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < moves.length; i++) ...[
            _moveCard(p, moves[i], i),
            const SizedBox(height: 8),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 4),
            child: Text('提示：杀招释放会消耗真元与蛊虫耐久；道痕冲突有反噬风险。',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _moveCard(p, KillerMove km, int idx) {
    final names = km.guNames(p);
    // 校验蛊虫是否仍在空窍/背包（已丢失/死亡的标记为红色）
    final gus = <GuInstance>[];
    for (final id in km.guInstIds) {
      for (final g in [...p.guInSlot, ...p.guBag]) {
        if (g.instId == id) { gus.add(g); break; }
      }
    }
    final valid = gus.length == km.guInstIds.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF261C30),
        border: Border.all(
          color: valid ? const Color(0xFFE67E22).withOpacity(0.5) : const Color(0xFFE74C3C).withOpacity(0.6),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('[$idx] ${km.name}',
              style: const TextStyle(color: Color(0xFFE67E22), fontSize: 14, fontWeight: FontWeight.bold)),
          if (!valid) ...[
            const SizedBox(width: 6),
            const Text('蛊虫缺失', style: TextStyle(color: Color(0xFFE74C3C), fontSize: 10)),
          ],
          const Spacer(),
          // 释放按钮
          ElevatedButton.icon(
            icon: const Icon(Icons.bolt, size: 16),
            label: const Text('释放', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE67E22), foregroundColor: Colors.white,
              minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: () {
              Navigator.pop(context);
              widget.ctx.handle('km ${km.name}');
            },
          ),
          const SizedBox(width: 6),
          // 删除按钮
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFE74C3C), size: 18),
            tooltip: '删除该杀招',
            constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
            padding: EdgeInsets.zero,
            onPressed: () {
              widget.ctx.handle('kmdel $idx');
              setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 4),
        Text('组合：${names.join(" + ")}',
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
        Text(_comboPreview(p, gus),
            style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3)),
      ]),
    );
  }

  /// 协同加成预览（同流派≥2 +20%，道痕匹配）。
  String _comboPreview(p, List<GuInstance> gus) {
    if (gus.length < 2) return '需≥2只蛊方可触发协同';
    final schoolCnt = <String, int>{};
    for (final g in gus) {
      schoolCnt[g.school] = (schoolCnt[g.school] ?? 0) + 1;
    }
    final top = schoolCnt.values.isEmpty ? 0 : schoolCnt.values.reduce((a, b) => a > b ? a : b);
    final parts = <String>[];
    if (top >= 2) {
      parts.add('同流派协同 +${top >= 3 ? 35 : 20}%');
      for (final e in schoolCnt.entries) {
        if (e.value >= 2) {
          final d = p.daoMark[e.key] ?? 0;
          if (d > 0) parts.add('${e.key}道痕 +${d}%');
        }
      }
    }
    return parts.isEmpty ? '无协同加成（流派分散）' : parts.join('，');
  }

  /// 新建杀招视图：命名 + 触屏勾选空窍/背包蛊。
  Widget _buildCreateView(p) {
    final all = [...p.guInSlot, ...p.guBag];
    return StatefulBuilder(
      builder: (c, setState) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('杀招名称', style: TextStyle(color: _panelAccent, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: '如：青茅连环击',
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _panelAccent)),
              ),
            ),
            const SizedBox(height: 12),
            Text('勾选组合蛊虫（2~4只，已选 ${_selected.length}）',
                style: const TextStyle(color: _panelAccent, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (all.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('空窍与背包均无蛊虫，无法构筑杀招。',
                      style: TextStyle(color: Colors.white54, fontSize: 12))),
            for (final g in all)
              _guCheckTile(g, () => setState(() {})),
            const SizedBox(height: 8),
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_comboPreview(p, _selectedGus(p)),
                    style: const TextStyle(color: Color(0xFF27AE60), fontSize: 11)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('构筑杀招'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60), foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: (_selected.length >= 2 && _selected.length <= 4 && _nameCtrl.text.trim().isNotEmpty)
                    ? () => _confirmCreate(p)
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            const Text('校验：自动剔除已丢失/死亡的蛊虫；组合中蛊须在空窍或背包中。',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  List<GuInstance> _selectedGus(p) {
    final out = <GuInstance>[];
    for (final id in _selected) {
      for (final g in [...p.guInSlot, ...p.guBag]) {
        if (g.instId == id) { out.add(g); break; }
      }
    }
    return out;
  }

  Widget _guCheckTile(GuInstance g, VoidCallback onChanged) {
    final checked = _selected.contains(g.instId);
    final inSlot = widget.ctx.player!.guInSlot.any((x) => x.instId == g.instId);
    return InkWell(
      onTap: () {
        setState(() {
          if (checked) {
            _selected.remove(g.instId);
          } else {
            if (_selected.length >= 4) return;
            _selected.add(g.instId);
          }
        });
        onChanged();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: checked ? const Color(0xFF27AE60).withOpacity(0.12) : const Color(0xFF1E1E1E),
          border: Border.all(
            color: checked ? const Color(0xFF27AE60) : Colors.white12,
            width: checked ? 1.2 : 0.8,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Icon(checked ? Icons.check_box : Icons.check_box_outline_blank,
              color: checked ? const Color(0xFF27AE60) : Colors.white54, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(
            '${g.name}${g.mutated ? "[变异]" : ""}　${g.rank}转/${g.school}'
            '${inSlot ? "（空窍）" : "（背包）"}　耐久${g.durability}/${g.durabilityMax}',
            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
          )),
        ]),
      ),
    );
  }

  void _confirmCreate(p) {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selected.length < 2 || _selected.length > 4) return;
    // 通过 instId 构造蛊名列表传给底层（KillerMoveStore.add 支持按 instId 精确匹配）
    final gus = _selected.toList();
    final ok = KillerMoveStore.add(p, name, gus);
    if (ok) {
      widget.ctx.out('【杀招构筑】「$name」构筑成功！组合 ${gus.length} 只蛊，可一键释放。', MsgType.fortune);
      widget.ctx.notifyListeners();
    } else {
      widget.ctx.out('杀招构筑失败：组合中蛊虫需在空窍或背包中存在。', MsgType.danger);
    }
    Navigator.pop(context);
  }
}
