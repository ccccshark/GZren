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
                return _exitCard(dirCN, e.key, targetName, () {
                  Navigator.pop(context);
                  ctx.handle('go ${e.key}');
                });
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

  Widget _exitCard(String dirCN, String dirKey, String targetName, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
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
            Container(
              width: 36, height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _panelAccent, shape: BoxShape.circle,
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
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            )),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
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
    return GestureDetector(
      onLongPress: onEdit,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: empty ? const Color(0xFF1A1A1A) : const Color(0xFF1ABC9C).withOpacity(0.18),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
              color: empty ? Colors.white30 : const Color(0xFF1ABC9C), size: 16),
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

class _InventoryClassifiedContent extends StatelessWidget {
  final GameContext ctx;
  const _InventoryClassifiedContent({required this.ctx});

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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('材料（采集/掉落/购买所得）', Icons.grain, const Color(0xFF27AE60),
              materials.isEmpty
                  ? ['空空如也']
                  : materials.entries.map((e) => '· ${e.key} x${e.value}').toList()),
          const SizedBox(height: 10),
          _section('蛊方（炼蛊配方，需配合材料）', Icons.menu_book, const Color(0xFFE67E22),
              recipes.isEmpty
                  ? ['尚无蛊方']
                  : recipes.entries.map((e) => '· ${e.key} x${e.value}').toList()),
          const SizedBox(height: 10),
          _section('空窍蛊（已装备，可催动/投喂）', Icons.bolt, const Color(0xFF1ABC9C),
              p.guInSlot.isEmpty
                  ? ['空窍空空，尚未安放蛊虫']
                  : p.guInSlot.map((g) => '· ${g.name}${g.mutated ? "[变异]" : ""}　${g.rank}转/${g.school}　耐久 ${g.durability}/${g.durabilityMax}　消耗${g.costZhen}真元').toList(),
              highlight: true),
          const SizedBox(height: 10),
          _section('背包蛊（寄存，需装备入空窍方可催动）', Icons.bug_report, const Color(0xFF9B59B6),
              p.guBag.isEmpty
                  ? ['无寄存蛊虫']
                  : p.guBag.map((g) => '· ${g.name}${g.mutated ? "[变异]" : ""}　${g.rank}转/${g.school}　耐久 ${g.durability}/${g.durabilityMax}').toList()),
          const SizedBox(height: 4),
          const Row(children: [
            Icon(Icons.info_outline, color: Colors.white38, size: 14),
            SizedBox(width: 4),
            Expanded(child: Text('材料/蛊方合计 ${p.inventory.length} 项；空窍 ${p.guInSlot.length}/${p.effectiveSlotMax}。',
                style: TextStyle(color: Colors.white38, fontSize: 11))),
          ]),
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
              if (widget.ctx.player != null) {
                widget.ctx.player!.flags['need_tutorial'] = false;
                widget.ctx.notifyListeners();
              }
              Navigator.pop(context);
            },
            child: const Text('开始游戏'),
          ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }
}
