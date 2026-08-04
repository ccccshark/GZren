// panels_v2.dart
// V3.5 第二阶段系统 UI 面板集合（触屏图形化入口）。
// 补齐 v1.5.0 公告但缺 UI 入口的 7 个子系统：
//   1. 空窍容量面板   showSlotCapacityPanel
//   2. 储物蛊面板     showStorageGuPanel
//   3. 食物滋养面板   showFoodPanel
//   4. 势力声望面板   showReputationPanel
//   5. 悬赏榜面板     showBountyPanel
//   6. 黑市面板       showBlackMarketPanel
//   7. 以物易物面板   showBarterPanel
//   8. 任务系统面板   showQuestPanel
// 设计原则与 panels.dart 一致：
//   - 触屏图形化优先，所有交互通过按钮/卡片点击
//   - 内部最终调用 ctx.handle()，底层指令引擎零改动
//   - 与 panels.dart 共用配色 _panelBg/_panelItemBg/_panelAccent
import 'package:flutter/material.dart';
import '../engine/command.dart';
import '../data_model/player_model.dart' show Player;
import '../data_model/gu_model.dart';
import '../data_model/recipe_model.dart' show MatParser;
import '../data_model/slot_capacity_model.dart' show SlotCapacity;
import '../data_model/storage_gu_model.dart' show StorageGu;
import '../data_model/food_model.dart' show FoodSystem, FoodEffect;
import '../data_model/reputation_model.dart' show Reputation, Faction;
import '../data_model/trade_upgrade_model.dart'
    show BountyBoard, BountyQuest, BlackMarket, BlackMarketStock;
import '../engine/quest_system.dart' show QuestSystem;

// 与 panels.dart 共用配色（独立声明，避免私有符号跨文件引用失败）
const Color _v2PanelBg = Color(0xFF1E1E1E);
const Color _v2ItemBg = Color(0xFF2C1E3A);
const Color _v2Accent = Color(0xFF8E44AD);

// 通用样式：信息行
Widget _v2InfoRow(String label, String value, {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(color: valueColor ?? Colors.white, fontSize: 13)),
        ),
      ],
    ),
  );
}

// 通用样式：分区标题
Widget _v2SectionTitle(String text, {Color color = _v2Accent}) {
  return Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Text(text,
        style: TextStyle(
            color: color, fontSize: 13, fontWeight: FontWeight.bold)),
  );
}

// 通用样式：主操作按钮
Widget _v2PrimaryBtn(String label, IconData icon, VoidCallback onTap,
    {Color color = const Color(0xFF27AE60)}) {
  return ElevatedButton.icon(
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 44),
    ),
    onPressed: onTap,
  );
}

// 通用：包装为 AlertDialog
Future<void> _v2ShowDialog(
    BuildContext context, String title, IconData icon, Widget content,
    {List<Widget>? actions}) {
  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _v2PanelBg,
      title: Row(children: [
        Icon(icon, color: _v2Accent, size: 22),
        const SizedBox(width: 8),
        Expanded(
            child: Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 17))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
          width: double.maxFinite,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16), child: content)),
      actions: actions ??
          [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
    ),
  );
}

// ===================== 1. 空窍容量面板 =====================
Future<void> showSlotCapacityPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final p = ctx.player!;
  SlotCapacity.ensureStrictMode(p);
  final overloaded = SlotCapacity.isOverloaded(p);
  await _v2ShowDialog(
    context,
    '空窍·承载容量',
    Icons.inventory_2,
    SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _v2InfoRow('境界基准', '${SlotCapacity.baseCapacity(p)}'),
          _v2InfoRow('拓窍加成', '+${SlotCapacity.expandBonus(p)}'),
          _v2InfoRow('总上限', '${SlotCapacity.capacityMax(p)}',
              valueColor: _v2Accent),
          _v2InfoRow('已占用', '${SlotCapacity.usedCapacity(p)}',
              valueColor: overloaded ? Colors.redAccent : Colors.white),
          _v2InfoRow('剩余', '${SlotCapacity.freeCapacity(p)}'),
          if (overloaded)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                border: Border.all(color: Colors.redAccent, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '【过载警告】真元恢复暴跌，每日滋生暗伤。请取出高转蛊或服用拓窍蛊扩容。',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            )
          else
            _v2InfoRow('真元恢复倍率',
                SlotCapacity.trueyuanRecoverMultiplier(p).toStringAsFixed(2)),
          _v2SectionTitle('已装备蛊占用明细'),
          if (p.guInSlot.isEmpty)
            const Text('  （空窍中未装备任何蛊）',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else
            for (final g in p.guInSlot)
              _v2InfoRow('· ${g.name}（${g.rank}转）',
                  '占用 ${SlotCapacity.guUse(g)}',
                  valueColor: Colors.white70),
        ],
      ),
    ),
  );
}

// ===================== 2. 储物蛊面板 =====================
Future<void> showStorageGuPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final p = ctx.player!;
  StorageGu.ensureStrictMode(p);
  final free = StorageGu.freeCapacity(p);
  await _v2ShowDialog(
    context,
    '储物蛊·背包容量',
    Icons.backpack,
    SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _v2InfoRow('随身基础', '${StorageGu.carryBase}'),
          _v2InfoRow('储物蛊加成', '+${StorageGu.storageBonus(p)}'),
          _v2InfoRow('总上限', '${StorageGu.capacityMax(p)}',
              valueColor: _v2Accent),
          _v2InfoRow('已占用', '${StorageGu.usedCapacity(p)}'),
          _v2InfoRow('剩余', '$free',
              valueColor: free < 0 ? Colors.redAccent : Colors.white),
          if (free < 0)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                border: Border.all(color: Colors.redAccent, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '【储物超载】背包超出上限，无法继续携带物资。请装备储物蛊或整理背包。',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          _v2SectionTitle('生效中的储物蛊'),
          if (!StorageGu.hasStorageGu(p))
            const Text('  （未装备任何储物蛊，仅靠随身基础容量）',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else
            for (final g in [...p.guInSlot, ...p.guBag])
              if (StorageGu.storageCapOf(g) > 0)
                _v2InfoRow('· ${g.name}（${g.rank}转）',
                    '+${StorageGu.storageCapOf(g)}',
                    valueColor: Colors.white70),
        ],
      ),
    ),
  );
}

// ===================== 3. 食物滋养面板 =====================
Future<void> showFoodPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final p = ctx.player!;
  FoodSystem.ensureStrictMode(p);
  final left = FoodSystem.satietyHoursLeft(p);
  // 收集可食用物资（材料主表在 ctx.materials['materials'] 子层）
  final matInfo = (ctx.materials['materials'] ?? {}) as Map<String, dynamic>;
  final foods = <MapEntry<String, (int, FoodEffect)>>[];
  for (final it in p.inventory) {
    final (n, c) = MatParser.parse(it);
    final info = matInfo[n] as Map<String, dynamic>?;
    final fe = FoodSystem.parseFoodEffect(info?['effect'] as Map<String, dynamic>?);
    if (fe != null) foods.add(MapEntry(n, (c, fe)));
  }
  await _v2ShowDialog(
    context,
    '食物滋养',
    Icons.restaurant,
    SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _v2InfoRow('饱食剩余', '${left.toStringAsFixed(1)} 小时',
              valueColor: left <= 0
                  ? Colors.redAccent
                  : (left < 6 ? Colors.orangeAccent : Colors.greenAccent)),
          if (left <= 0)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                border: Border.all(color: Colors.redAccent, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '【饥饿】久未进食，体魄每日持续流失，请尽快进食！',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            )
          else if (left < 6)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('【半饥半饱】饱食仅剩不多，请尽快补充。',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            ),
          _v2SectionTitle('可食用物资（点击食用）'),
          if (foods.isEmpty)
            const Text('  （背包中无可直接食用物资）',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else
            for (final entry in foods)
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  ctx.handle('eat ${entry.key}');
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _v2ItemBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _v2Accent.withOpacity(0.4), width: 1),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${entry.key} x${entry.value.$1}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(entry.value.$2.desc(),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Icon(Icons.restaurant_menu,
                        color: Colors.greenAccent, size: 18),
                  ]),
                ),
              ),
        ],
      ),
    ),
  );
}

// ===================== 4. 势力声望面板 =====================
Future<void> showReputationPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final p = ctx.player!;
  await _v2ShowDialog(
    context,
    '势力声望',
    Icons.military_tech,
    SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in Faction.all)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _v2ItemBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Reputation.isHostile(p, f)
                        ? Colors.redAccent.withOpacity(0.6)
                        : _v2Accent.withOpacity(0.4),
                    width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(Faction.names[f] ?? f,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ),
                    if (Reputation.isHostile(p, f))
                      const Text('【敌对】',
                          style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                  ]),
                  const SizedBox(height: 4),
                  _v2InfoRow('声望值', '${Reputation.of(p, f)}',
                      valueColor: Colors.white),
                  _v2InfoRow('评级', Reputation.gradeLabel(Reputation.of(p, f))),
                  _v2InfoRow('交易倍率',
                      '${Reputation.priceMul(p, f).toStringAsFixed(2)}x'),
                  _v2InfoRow('地图通行',
                      Reputation.canEnter(p, f) ? '可通行' : '禁止进入',
                      valueColor: Reputation.canEnter(p, f)
                          ? Colors.greenAccent
                          : Colors.redAccent),
                  _v2InfoRow('专属解锁',
                      Reputation.canUnlockExclusive(p, f) ? '已解锁' : '未解锁'),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

// ===================== 5. 悬赏榜面板 =====================
Future<void> showBountyPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final list = BountyBoard.list(ctx.player!);
  await _v2ShowDialog(
    context,
    '悬赏榜',
    Icons.assignment,
    SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: Text('当前无悬赏任务',
                      style: TextStyle(color: Colors.white54, fontSize: 13))),
            )
          else
            for (int i = 0; i < list.length; i++)
              _BountyCard(
                quest: list[i],
                onAccept: () {
                  Navigator.pop(context);
                  ctx.handle('bountyaccept $i');
                },
                onSubmit: () {
                  Navigator.pop(context);
                  ctx.handle('bountysubmit $i');
                },
              ),
          const SizedBox(height: 8),
          const Text(
            '提示：kill 类悬赏需击杀指定 NPC 后提交；gather 类需收集足够物资。',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _BountyCard extends StatelessWidget {
  final BountyQuest quest;
  final VoidCallback onAccept;
  final VoidCallback onSubmit;
  const _BountyCard(
      {required this.quest, required this.onAccept, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final status = quest.status;
    final canAccept = status == 'open';
    final canSubmit = status == 'accepted';
    final done = status == 'done';
    final factionName = Faction.names[quest.faction] ?? quest.faction;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _v2ItemBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: done
                ? Colors.greenAccent.withOpacity(0.6)
                : (canSubmit ? Colors.orangeAccent.withOpacity(0.6) : _v2Accent.withOpacity(0.4)),
            width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(quest.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ),
            if (done)
              const Text('已完成',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 11))
            else if (canSubmit)
              const Text('进行中',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11))
            else
              const Text('可接取',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Text(quest.desc,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          _v2InfoRow('发布势力', factionName),
          _v2InfoRow('类型', quest.type == 'kill' ? '击杀 NPC' : '采集物资'),
          _v2InfoRow('目标', '${quest.target} x${quest.amount}'),
          _v2InfoRow('奖励', quest.rewardDesc, valueColor: Colors.greenAccent),
          if (canAccept || canSubmit) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (canAccept)
                Expanded(
                  child: _v2PrimaryBtn('接取', Icons.download, onAccept,
                      color: _v2Accent),
                ),
              if (canSubmit) ...[
                if (canAccept) const SizedBox(width: 8),
                Expanded(
                  child: _v2PrimaryBtn('提交', Icons.check, onSubmit,
                      color: const Color(0xFFE67E22)),
                ),
              ]
            ]),
          ],
        ],
      ),
    );
  }
}

// ===================== 6. 黑市面板 =====================
Future<void> showBlackMarketPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final p = ctx.player!;
  final (ok, msg) = BlackMarket.canEnter(p);
  final stock = ok ? BlackMarket.stock(p) : <BlackMarketStock>[];
  await _v2ShowDialog(
    context,
    '南疆黑市',
    Icons.storefront,
    SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!ok)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                border: Border.all(color: Colors.redAccent, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(msg,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            )
          else ...[
            Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (BlackMarket.isGuchaoActive(p))
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.12),
                  border: Border.all(color: Colors.redAccent, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('⚡ 蛊潮将至！黑市追加蛊潮专属货品。',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            if (((p.flags['blackmarket_vip'] as num?)?.toInt() ?? 0) > 0)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('★ VIP 通道已开启，可选购高阶蛊方。',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
              ),
            _v2SectionTitle('今夜货品'),
            if (stock.isEmpty)
              const Text('  （今夜无新货……）',
                  style: TextStyle(color: Colors.white54, fontSize: 12))
            else
              for (final s in stock)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _v2ItemBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _v2Accent.withOpacity(0.4), width: 1),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(s.desc,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ),
                    Text('${s.price} 原石',
                        style: const TextStyle(
                            color: Colors.greenAccent, fontSize: 12)),
                  ]),
                ),
            const SizedBox(height: 8),
            const Text(
              '提示：购买请使用交易面板（黑市货品会出现在 NPC 交易列表中）。',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ],
      ),
    ),
  );
}

// ===================== 7. 以物易物面板 =====================
Future<void> showBarterPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final p = ctx.player!;
  await _v2ShowDialog(
    context,
    '以物易物',
    Icons.swap_horiz,
    _BarterForm(ctx: ctx, player: p),
  );
}

class _BarterForm extends StatefulWidget {
  final GameContext ctx;
  final Player player;
  const _BarterForm({required this.ctx, required this.player});
  @override
  State<_BarterForm> createState() => _BarterFormState();
}

class _BarterFormState extends State<_BarterForm> {
  String? _giveName;
  String? _wantName;
  int _giveCount = 1;
  int _wantCount = 1;
  String? _hint;

  List<String> get _invNames {
    final s = <String>{};
    for (final it in widget.player.inventory) {
      final (n, _) = MatParser.parse(it);
      s.add(n);
    }
    return s.toList()..sort();
  }

  List<String> get _matCatalog {
    final keys = widget.ctx.materials.keys.toList()..sort();
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invNames;
    final catalog = _matCatalog;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _v2SectionTitle('你给出（从背包选择）'),
          DropdownButton<String>(
            value: _giveName,
            dropdownColor: _v2PanelBg,
            isExpanded: true,
            hint: const Text('选择物资',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            items: inv
                .map((n) => DropdownMenuItem(
                      value: n,
                      child: Text(n,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) => setState(() {
              _giveName = v;
              _hint = null;
            }),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Text('数量',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                min: 1,
                max: 20,
                divisions: 19,
                value: _giveCount.toDouble(),
                label: '$_giveCount',
                activeColor: _v2Accent,
                onChanged: (v) => setState(() {
                  _giveCount = v.round();
                  _hint = null;
                }),
              ),
            ),
            SizedBox(
                width: 36,
                child: Text('$_giveCount',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    textAlign: TextAlign.right)),
          ]),
          _v2SectionTitle('你想要（从材料库选择）'),
          DropdownButton<String>(
            value: _wantName,
            dropdownColor: _v2PanelBg,
            isExpanded: true,
            hint: const Text('选择物资',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            items: catalog
                .map((n) => DropdownMenuItem(
                      value: n,
                      child: Text(n,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) => setState(() {
              _wantName = v;
              _hint = null;
            }),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Text('数量',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                min: 1,
                max: 20,
                divisions: 19,
                value: _wantCount.toDouble(),
                label: '$_wantCount',
                activeColor: _v2Accent,
                onChanged: (v) => setState(() {
                  _wantCount = v.round();
                  _hint = null;
                }),
              ),
            ),
            SizedBox(
                width: 36,
                child: Text('$_wantCount',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    textAlign: TextAlign.right)),
          ]),
          if (_hint != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _hint!.startsWith('成功')
                    ? Colors.greenAccent.withOpacity(0.12)
                    : Colors.redAccent.withOpacity(0.12),
                border: Border.all(
                    color: _hint!.startsWith('成功')
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_hint!,
                  style: TextStyle(
                      color: _hint!.startsWith('成功')
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 12)),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _v2PrimaryBtn(
              '发起易物',
              Icons.swap_horiz,
              () {
                if (_giveName == null || _wantName == null) {
                  setState(() => _hint = '请先选择双方物资');
                  return;
                }
                final cmd =
                    'barter $_giveName x$_giveCount=$_wantName x$_wantCount';
                Navigator.pop(context);
                widget.ctx.handle(cmd);
              },
              color: const Color(0xFFE67E22),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '提示：成功率受双方物资估值差、幸运值、势力声望影响。失败会消耗你给出的物资。',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ===================== 8. 任务系统面板 =====================
Future<void> showQuestPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final list = QuestSystem.overview(ctx.player!);
  await _v2ShowDialog(
    context,
    '任务系统',
    Icons.task_alt,
    SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: Text('当前无任何任务',
                      style: TextStyle(color: Colors.white54, fontSize: 13))),
            )
          else
            for (final q in list)
              _QuestCard(
                qid: q['qid'] ?? '',
                type: q['type'] ?? '',
                name: q['name'] ?? '',
                status: q['status'] ?? '',
                progress: q['progress'] ?? '',
                desc: q['desc'] ?? '',
                ctx: ctx,
              ),
        ],
      ),
    ),
  );
}

class _QuestCard extends StatelessWidget {
  final String qid;
  final String type;
  final String name;
  final String status;
  final String progress;
  final String desc;
  final GameContext ctx;
  const _QuestCard({
    required this.qid,
    required this.type,
    required this.name,
    required this.status,
    required this.progress,
    required this.desc,
    required this.ctx,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabel = const {'main': '主线', 'side': '支线', 'loop': '循环'}[type] ?? type;
    final statusInfo = const {
      'locked': ('〔未解锁〕', Colors.white54),
      'available': ('〔可接取〕', Colors.greenAccent),
      'active': ('〔进行中〕', Colors.orangeAccent),
      'completed': ('〔待交付〕', Colors.greenAccent),
      'turned_in': ('〔已交付〕', Colors.white54),
    }[status] ??
        ('', Colors.white);
    final canAccept = status == 'available';
    final canTurnIn = status == 'completed';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _v2ItemBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: (canAccept || canTurnIn)
                ? statusInfo.$2.withOpacity(0.6)
                : _v2Accent.withOpacity(0.3),
            width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _v2Accent.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(typeLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ),
            Text(statusInfo.$1,
                style: TextStyle(color: statusInfo.$2, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Text(desc,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (progress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('进度：$progress',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          if (canAccept || canTurnIn) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (canAccept)
                Expanded(
                  child: _v2PrimaryBtn('接取', Icons.download, () {
                    Navigator.pop(context);
                    ctx.handle('quest accept $name');
                  }, color: _v2Accent),
                ),
              if (canTurnIn) ...[
                if (canAccept) const SizedBox(width: 8),
                Expanded(
                  child: _v2PrimaryBtn('交付', Icons.check, () {
                    Navigator.pop(context);
                    ctx.handle('quest turnin $name');
                  }, color: const Color(0xFF27AE60)),
                ),
              ]
            ]),
          ],
        ],
      ),
    );
  }
}
