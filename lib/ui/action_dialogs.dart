// action_dialogs.dart
// 移动端大众化交互层：所有带参数指令的图形化选择弹窗。
// 设计原则：弹窗读取当前游戏状态（背包/空窍/场景NPC/野生蛊/蛊方），
// 玩家点击选择后，程序自动拼装为原有规范指令交给 ctx.handle() 执行。
// 底层 MUD 指令引擎、存档、JSON 配置完全不改，100% 兼容。
import 'package:flutter/material.dart';
import '../engine/command.dart';
import '../engine/gu_system.dart' as gu;
import '../data_model/npc_model.dart';
import '../data_model/recipe_model.dart';

const Color _bg = Color(0xFF1E1E1E);
const Color _itemBg = Color(0xFF2C1E3A);

/// 通用列表选择弹窗。返回玩家选中的索引（取消返回 null）。
Future<int?> _showPickList({
  required BuildContext context,
  required String title,
  required List<Widget> tiles,
  double maxWidth = 480,
}) {
  return showDialog<int>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _bg,
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: maxWidth,
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: tiles.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) => InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.pop(c, i),
            child: tiles[i],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('取消')),
      ],
    ),
  );
}

Widget _tile(String title, {String? subtitle, IconData? icon, Color? iconColor}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: _itemBg, borderRadius: BorderRadius.circular(8)),
    child: Row(children: [
      if (icon != null) ...[
        Icon(icon, color: iconColor ?? Colors.white70, size: 20),
        const SizedBox(width: 10),
      ],
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
        ],
      )),
      const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
    ]),
  );
}

void _run(BuildContext context, GameContext ctx, String rawCmd) {
  // 选择列表 _showPickList 在返回结果时已自行关闭，这里无需再 pop。
  ctx.handle(rawCmd);
}

// ===================== 蛊虫操作 =====================

/// 捕捉野蛊：列出当前场景野生蛊虫，点击 capture。
Future<void> showCaptureDialog(BuildContext context, GameContext ctx) async {
  final room = ctx.curRoom();
  if (room.wildGu.isEmpty) {
    ctx.out('当前场景没有野生蛊虫可捕捉。', MsgType.danger);
    return;
  }
  final tiles = <Widget>[];
  for (final gid in room.wildGu) {
    final t = ctx.guList[gid];
    final name = t?.name ?? gid;
    tiles.add(_tile(name,
        subtitle: '${t?.rank ?? 1}转 · ${t?.school ?? ""}　${t?.desc ?? ""}',
        icon: Icons.bug_report, iconColor: const Color(0xFF9B59B6)));
  }
  final idx = await _showPickList(context: context, title: '捕捉野生蛊虫', tiles: tiles);
  if (idx == null) return;
  final gid = room.wildGu[idx];
  final name = ctx.guList[gid]?.name ?? gid;
  _run(context, ctx, 'capture $name');
}

/// 炼蛊：读取背包内拥有的蛊方列表，点击启动炼制。
Future<void> showRefineDialog(BuildContext context, GameContext ctx) async {
  final owned = ctx.recipes.where((r) => ctx.player!.inventory.contains(r.name)).toList();
  if (owned.isEmpty) {
    ctx.out('你未持有任何蛊方，无法炼蛊。先采集/探索获取蛊方。', MsgType.danger);
    return;
  }
  final tiles = owned.map((r) {
    final out = ctx.guList[r.outputGid]?.name ?? '?';
    final lack = <String>[];
    for (final m in r.material) {
      final (n, c) = MatParser.parse(m);
      if (gu.countMaterial(ctx.player!, n) < c) lack.add('$n(缺)');
    }
    final okStr = lack.isEmpty ? '材料齐备' : '缺少：${lack.join("、")}';
    return _tile(r.name,
        subtitle: '产出 $out · ${r.rank}转 · 成功率 ${(r.baseSuccess * 100).round()}% · $okStr',
        icon: Icons.science, iconColor: const Color(0xFF27AE60));
  }).toList();
  final idx = await _showPickList(context: context, title: '炼蛊（选择蛊方）', tiles: tiles);
  if (idx == null) return;
  _run(context, ctx, 'refine ${owned[idx].name}');
}

/// 投喂：先选蛊虫，再选该蛊可吃的材料（且背包拥有的）。
Future<void> showFeedDialog(BuildContext context, GameContext ctx) async {
  final allGu = [...ctx.player!.guInSlot, ...ctx.player!.guBag];
  if (allGu.isEmpty) {
    ctx.out('你还没有任何蛊虫。', MsgType.danger);
    return;
  }
  final tiles = allGu.map((g) {
    final loc = ctx.player!.guInSlot.contains(g) ? '空窍' : '背包';
    return _tile(g.name,
        subtitle: '$loc · 进食：${g.feedMaterial.join("、")} · 耐久 ${g.durability}/${g.durabilityMax}',
        icon: Icons.restaurant, iconColor: const Color(0xFFE67E22));
  }).toList();
  final idx = await _showPickList(context: context, title: '投喂（选择蛊虫）', tiles: tiles);
  if (idx == null) return;
  final target = allGu[idx];
  // 第二步：选材料
  final avail = target.feedMaterial.where((m) => gu.hasMaterial(ctx.player!, m, 1)).toList();
  if (avail.isEmpty) {
    ctx.out('${target.name} 的食物（${target.feedMaterial.join("、")}）背包中均无存量。', MsgType.danger);
    return;
  }
  final mTiles = avail.map((m) => _tile(m,
      subtitle: '持有 ${gu.countMaterial(ctx.player!, m)}',
      icon: Icons.inventory_2, iconColor: const Color(0xFF27AE60))).toList();
  final midx = await _showPickList(context: context, title: '投喂 ${target.name}（选择材料）', tiles: mTiles);
  if (midx == null) return;
  _run(context, ctx, 'feed ${target.name} ${avail[midx]}');
}

/// 装备蛊：列出背包寄存蛊虫（未装备的），点击 equip。
Future<void> showEquipDialog(BuildContext context, GameContext ctx) async {
  if (ctx.player!.guBag.isEmpty) {
    ctx.out('背包寄存蛊虫为空，无可装备。', MsgType.danger);
    return;
  }
  final tiles = ctx.player!.guBag.map((g) => _tile(g.name,
      subtitle: '${g.rank}转 · ${g.school} · 耐久 ${g.durability}/${g.durabilityMax} · 真元消耗${g.costZhen}',
      icon: Icons.bolt, iconColor: const Color(0xFF9B59B6))).toList();
  final idx = await _showPickList(context: context, title: '装备蛊入空窍（剩余 ${ctx.player!.freeSlotCount} 槽）', tiles: tiles);
  if (idx == null) return;
  _run(context, ctx, 'equip ${ctx.player!.guBag[idx].name}');
}

/// 取出蛊：列出空窍中已装备蛊虫，点击 unequip。
Future<void> showUnequipDialog(BuildContext context, GameContext ctx) async {
  if (ctx.player!.guInSlot.isEmpty) {
    ctx.out('空窍中尚未安放蛊虫。', MsgType.danger);
    return;
  }
  final tiles = ctx.player!.guInSlot.map((g) => _tile(g.name,
      subtitle: '${g.rank}转 · ${g.school} · 耐久 ${g.durability}/${g.durabilityMax}',
      icon: Icons.arrow_outward, iconColor: const Color(0xFFE74C3C))).toList();
  final idx = await _showPickList(context: context, title: '取出空窍蛊虫', tiles: tiles);
  if (idx == null) return;
  _run(context, ctx, 'unequip ${ctx.player!.guInSlot[idx].name}');
}

/// 催动蛊：列出空窍中可催动的蛊虫，点击 use。
Future<void> showUseDialog(BuildContext context, GameContext ctx) async {
  final usable = ctx.player!.guInSlot.where((g) => g.durability > 0).toList();
  if (usable.isEmpty) {
    ctx.out('空窍中没有可催动的蛊虫（耐久耗尽需先投喂）。', MsgType.danger);
    return;
  }
  final tiles = usable.map((g) {
    final ctype = g.combat['type'] ?? 'passive';
    return _tile(g.name,
        subtitle: '${g.rank}转 · 类型 $ctype · 耐久 ${g.durability}/${g.durabilityMax} · 真元消耗${g.costZhen}',
        icon: Icons.flash_on, iconColor: const Color(0xFF1ABC9C));
  }).toList();
  final idx = await _showPickList(context: context, title: '催动蛊虫（非战斗）', tiles: tiles);
  if (idx == null) return;
  _run(context, ctx, 'use ${usable[idx].name}');
}

// ===================== NPC 交互 =====================

/// NPC 通用动作菜单：对话/交易/攻击。由日志点击或“更多操作”调用。
Future<void> showNpcActionDialog(BuildContext context, GameContext ctx, Npc npc) async {
  if (!npc.alive) {
    ctx.out('${npc.name} 已死。', MsgType.danger);
    return;
  }
  final tag = npc.isHostile ? '敌对' : (npc.isMerchant ? '商人' : 'NPC');
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _bg,
      title: Text('${npc.name}（$tag · ${npc.level}）',
          style: const TextStyle(color: Colors.white, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _npcBtn(c, '对话 talk', Icons.chat, const Color(0xFF27AE60), () => ctx.handle('talk ${npc.name}')),
          if (npc.isMerchant)
            _npcBtn(c, '交易 trade', Icons.store, const Color(0xFFE67E22), () {
              ctx.handle('trade ${npc.name}');
              // _npcBtn 已关闭本弹窗；这里异步打开买/卖选择
              Future.microtask(() => showBuySellDialog(context, ctx, npc));
            }),
          _npcBtn(c, npc.isHostile ? '攻击 attack' : '主动攻击', Icons.gavel, const Color(0xFFE74C3C), () => ctx.handle('attack ${npc.name}')),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
    ),
  );
}

Widget _npcBtn(BuildContext dialogCtx, String label, IconData icon, Color color, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _itemBg, foregroundColor: Colors.white,
          alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        ),
        onPressed: () { Navigator.pop(dialogCtx); onTap(); },
      ),
    ),
  );
}

/// 对话：列出场景NPC，点击 talk。
Future<void> showTalkDialog(BuildContext context, GameContext ctx) async {
  final npcs = ctx.npcsInCurRoom().where((n) => n.alive).toList();
  if (npcs.isEmpty) {
    ctx.out('这里没有可以对话的人。', MsgType.danger);
    return;
  }
  final tiles = npcs.map((n) {
    final tag = n.isHostile ? '[敌对]' : (n.isMerchant ? '[商人]' : '[NPC]');
    return _tile('$tag ${n.name}', subtitle: n.level, icon: Icons.chat, iconColor: const Color(0xFF27AE60));
  }).toList();
  final idx = await _showPickList(context: context, title: '与 NPC 对话', tiles: tiles);
  if (idx == null) return;
  _run(context, ctx, 'talk ${npcs[idx].name}');
}

/// 交易：列出场景商人，选中后展示货物并进入买/卖选择。
Future<void> showTradeDialog(BuildContext context, GameContext ctx) async {
  final merchants = ctx.npcsInCurRoom().where((n) => n.alive && n.isMerchant).toList();
  if (merchants.isEmpty) {
    ctx.out('这里没有商人可交易。', MsgType.danger);
    return;
  }
  // BUG修复【老槐翁原石循环刷取】：货物数过滤黑名单（原石为货币不计入商品）
  final tiles = merchants.map((n) {
    final goodsCount = n.tradeGoods.entries.where((e) => !ctx.isTradeBlacklisted(e.key)).length;
    return _tile(n.name, subtitle: '货物 $goodsCount 种', icon: Icons.store, iconColor: const Color(0xFFE67E22));
  }).toList();
  final idx = await _showPickList(context: context, title: '选择商人交易', tiles: tiles);
  if (idx == null) return;
  final npc = merchants[idx];
  // 先 trade 打印货物列表到日志
  ctx.handle('trade ${npc.name}');
  // 再弹买/卖二级选择
  await showBuySellDialog(context, ctx, npc);
}

enum _TradeOp { buy, sell }

/// 买/卖二级选择（针对指定商人）。由 NPC 动作菜单或交易流程调用。
Future<void> showBuySellDialog(BuildContext context, GameContext ctx, Npc npc) async {
  final buyOrSell = await showDialog<_TradeOp>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _bg,
      title: Text('${npc.name} 商铺', style: const TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _actionTile(c, _TradeOp.buy, '购买商品', Icons.shopping_cart, const Color(0xFF27AE60)),
        _actionTile(c, _TradeOp.sell, '出售物资', Icons.sell, const Color(0xFFE67E22)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('关闭'))],
    ),
  );
  if (buyOrSell == _TradeOp.buy) {
    await showBuyDialog(context, ctx, npc);
  } else if (buyOrSell == _TradeOp.sell) {
    await showSellDialog(context, ctx);
  }
}

/// 买/卖二级菜单项。
Widget _actionTile(BuildContext dialogCtx, _TradeOp op, String label, IconData icon, Color color) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _itemBg, foregroundColor: Colors.white,
          alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        ),
        onPressed: () => Navigator.pop(dialogCtx, op),
      ),
    ),
  );
}

/// 购买：列出商人货物，点击 buy。
/// BUG修复【老槐翁原石循环刷取】：过滤黑名单商品（原石为货币，不出现在购买列表）
Future<void> showBuyDialog(BuildContext context, GameContext ctx, Npc npc) async {
  final have = gu.countMaterial(ctx.player!, '原石');
  // 过滤黑名单：货币类物品（原石）不出售
  final goods = npc.tradeGoods.entries
      .where((e) => !ctx.isTradeBlacklisted(e.key))
      .toList();
  if (goods.isEmpty) {
    ctx.out('${npc.name} 没有货物出售。', MsgType.danger);
    return;
  }
  final tiles = goods.map((e) => _tile(e.key,
      subtitle: '价格 ${e.value}原石 · 你持有 $have 原石',
      icon: Icons.shopping_cart, iconColor: const Color(0xFF27AE60))).toList();
  final idx = await _showPickList(context: context, title: '购买（原石=$have）', tiles: tiles);
  if (idx == null) return;
  final item = goods[idx].key;
  ctx.doTradeAction('buy $item 1');
}

/// 出售：列出背包可出售材料，点击 sell。
/// BUG修复【老槐翁原石循环刷取】：过滤黑名单物品（原石为货币，不可出售换原石，杜绝闭环兑换）
Future<void> showSellDialog(BuildContext context, GameContext ctx) async {
  final p = ctx.player!;
  // 去重统计背包材料
  final seen = <String, int>{};
  for (final it in p.inventory) {
    final (n, c) = MatParser.parse(it);
    seen[n] = (seen[n] ?? 0) + c;
  }
  // 过滤黑名单：货币类物品（原石）不可出售
  final sellable = seen.entries
      .where((e) => !ctx.isTradeBlacklisted(e.key))
      .toList();
  if (sellable.isEmpty) {
    ctx.out('背包空空如也，无可出售。', MsgType.danger);
    return;
  }
  final matInfo = (ctx.materials['materials'] ?? {}) as Map;
  final tiles = sellable.map((e) {
    final priceInfo = ((matInfo[e.key] ?? {}) as Map)['price'] ?? 1;
    final price = (((priceInfo as num) * 0.6).toInt()) * e.value;
    return _tile(e.key, subtitle: '持有 ${e.value} · 可售得约 $price 原石', icon: Icons.sell, iconColor: const Color(0xFFE67E22));
  }).toList();
  final idx = await _showPickList(context: context, title: '出售物资', tiles: tiles);
  if (idx == null) return;
  final item = sellable[idx].key;
  ctx.doTradeAction('sell $item ${sellable[idx].value}');
}

/// 攻击：列出场景可攻击NPC，点击 attack。
Future<void> showAttackDialog(BuildContext context, GameContext ctx) async {
  final npcs = ctx.npcsInCurRoom().where((n) => n.alive).toList();
  if (npcs.isEmpty) {
    ctx.out('这里没有可以攻击的目标。', MsgType.danger);
    return;
  }
  final tiles = npcs.map((n) {
    final tag = n.isHostile ? '[敌对]' : '[NPC]';
    return _tile('$tag ${n.name}', subtitle: '${n.level} · 体魄 ${n.physique}', icon: Icons.gavel, iconColor: const Color(0xFFE74C3C));
  }).toList();
  final idx = await _showPickList(context: context, title: '选择攻击目标', tiles: tiles);
  if (idx == null) return;
  _run(context, ctx, 'attack ${npcs[idx].name}');
}
