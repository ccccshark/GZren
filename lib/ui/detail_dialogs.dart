// detail_dialogs.dart
// 第三阶段新增【13.UI触屏交互优化】材料详情、蛊虫详情浮窗。
// 设计原则：
//   - 点击材料/蛊虫名弹出详情浮窗，展示全部属性
//   - 浮窗点击空白处或"关闭"按钮快速关闭，适配手机单手操作
//   - 统一暗黑国风文字MUD样式，与现有弹窗风格一致
//   - 底层仅读取 GameContext 静态数据，不修改任何状态，100%兼容旧存档
import 'package:flutter/material.dart';
import '../engine/command.dart';
import '../engine/player_core.dart' show levelRank;
import '../data_model/gu_model.dart';
import '../data_model/recipe_model.dart' show MatParser;
import '../data_model/scene_model.dart' show Room;
import '../data_model/player_model.dart' show Player;
import '../data_model/reputation_model.dart' show Reputation;

// 通用配色（与 panels.dart / action_dialogs.dart 保持一致）
const Color _dlgBg = Color(0xFF1E1E1E);
const Color _dlgItemBg = Color(0xFF2C1E3A);
const Color _dlgAccent = Color(0xFF8E44AD);

// ===================== 材料详情浮窗 =====================

/// 材料详情浮窗：展示来源、售卖价格、描述、可炼制蛊虫清单、效果。
/// 点击材料名触发，点击空白处或"关闭"快速关闭。
Future<void> showMaterialDetailDialog(
    BuildContext context, GameContext ctx, String matName) async {
  final matInfo = (ctx.materials['materials'] ?? {}) as Map;
  final info = (matInfo[matName] ?? {}) as Map;
  final rarity = (info['rarity'] ?? 1) as int;
  final price = info['price'] ?? 1;
  final desc = info['desc'] ?? '暂无描述';
  final effect = info['effect'];

  // 查找可炼制该材料的蛊方（材料名出现在 recipe.material 中）
  final relatedRecipes = <String>[];
  for (final r in ctx.recipes) {
    for (final m in r.material) {
      final (n, _) = MatParser.parse(m);
      if (n == matName) {
        final outName = ctx.guList[r.outputGid]?.name ?? r.outputGid;
        relatedRecipes.add('${r.name} → $outName');
        break;
      }
    }
  }

  // 查找该材料的来源场景（出现在 room.refresh_resource 中）
  final sourceRooms = <String>[];
  for (final room in ctx.rooms.values) {
    if (room.refreshResource.contains(matName)) {
      sourceRooms.add(room.name);
    }
  }

  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _dlgBg,
      title: Row(children: [
        Icon(_rarityIcon(rarity), color: _rarityColor(rarity), size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text(matName,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('稀有度', '★' * rarity, _rarityColor(rarity)),
              _infoRow('售价', '$price 原石', const Color(0xFFE67E22)),
              if (effect != null) ...[
                _infoRow('类型', (effect as Map)['type'] ?? '通用', const Color(0xFF1ABC9C)),
                if (effect['heal_phy'] != null)
                  _infoRow('恢复体魄', '+${effect['heal_phy']}', const Color(0xFF27AE60)),
                if (effect['heal_zhen'] != null)
                  _infoRow('恢复真元', '+${effect['heal_zhen']}', const Color(0xFF1ABC9C)),
                if (effect['satiety'] != null)
                  _infoRow('饱食度', '+${effect['satiety']}', const Color(0xFFE67E22)),
                if (effect['type'] == 'detox' && effect['power'] != null)
                  _infoRow('解毒力', '${effect['power']}', const Color(0xFF9D5CD0)),
                if (effect['detox_power'] != null && (effect['detox_power'] as num) > 0)
                  _infoRow('解毒力', '${effect['detox_power']}', const Color(0xFF9D5CD0)),
                if (effect['heal_injure_chance'] != null && (effect['heal_injure_chance'] as num) > 0)
                  _infoRow('疗伤几率', '${((effect['heal_injure_chance'] as num) * 100).round()}%', const Color(0xFF27AE60)),
              ],
              const SizedBox(height: 10),
              const Text('描述', style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
              if (sourceRooms.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('来源场景', style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: sourceRooms.map((r) =>
                    Chip(label: Text(r, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: _dlgItemBg, padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    )).toList()),
              ],
              if (relatedRecipes.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('可炼制蛊虫', style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                for (final r in relatedRecipes)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text('· $r', style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ),
  );
}

Color _rarityColor(int rarity) {
  switch (rarity) {
    case 1: return const Color(0xFF95A5A6);
    case 2: return const Color(0xFF27AE60);
    case 3: return const Color(0xFF2980B9);
    case 4: return const Color(0xFF9B59B6);
    default: return const Color(0xFFE67E22);
  }
}

IconData _rarityIcon(int rarity) {
  switch (rarity) {
    case 1: return Icons.grain;
    case 2: return Icons.spa;
    case 3: return Icons.diamond;
    case 4: return Icons.auto_awesome;
    default: return Icons.star;
  }
}

Widget _infoRow(String label, String value, Color valueColor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
      Expanded(child: Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold))),
    ]),
  );
}

// ===================== 蛊虫详情浮窗 =====================

/// 蛊虫详情浮窗（GuInstance 版）：展示蛊虫实例全部属性。
/// 适用于背包蛊/空窍蛊详情查看。点击蛊虫名触发，点击空白处或"关闭"快速关闭。
Future<void> showGuInstanceDetailDialog(
    BuildContext context, GameContext ctx, GuInstance g) async {
  final template = ctx.guList[g.gid];
  final evolveTo = g.gid.isNotEmpty && template?.evolveGid.isNotEmpty == true
      ? ctx.guList[template!.evolveGid]?.name ?? template.evolveGid
      : null;

  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _dlgBg,
      title: Row(children: [
        Icon(Icons.bug_report, color: _schoolColor(g.school), size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('${g.name}${g.mutated ? " [变异]" : ""}',
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('流派', g.school, _schoolColor(g.school)),
              _infoRow('转数', '${g.rank}转凡蛊', const Color(0xFFE67E22)),
              _infoRow('耐久', '${g.durability}/${g.durabilityMax}',
                  g.durability < g.durabilityMax * 0.3 ? const Color(0xFFE74C3C) : const Color(0xFF27AE60)),
              _infoRow('真元消耗', '${g.costZhen}', const Color(0xFF1ABC9C)),
              if (g.costLife > 0)
                _infoRow('寿元消耗', '${g.costLife}年/次', const Color(0xFFE74C3C)),
              _infoRow('战斗类型', (g.combat['type'] ?? 'passive'), const Color(0xFF9B59B6)),
              if (g.combat['power'] != null && (g.combat['power'] as int) > 0)
                _infoRow('威力', '${g.combat['power']}', const Color(0xFFE74C3C)),
              _infoRow('喜好饲料', g.feedMaterial.join('、'), const Color(0xFF27AE60)),
              if (evolveTo != null)
                _infoRow('进化目标', '→ $evolveTo', const Color(0xFF1ABC9C)),
              if (g.mutated)
                _infoRow('变异标记', '是（预留变异系统）', const Color(0xFF9D5CD0)),
              const SizedBox(height: 10),
              const Text('描述', style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(template?.desc ?? '暂无描述',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
              const SizedBox(height: 8),
              const Text('副作用', style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(g.sideEffect,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
              if (template?.habitat.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                const Text('栖息地', style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(template!.habitat.join('、'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ),
  );
}

/// 蛊虫详情浮窗（GuTemplate 版）：展示蛊虫模板全部属性。
/// 适用于野生蛊/炼蛊产出预览。点击蛊虫名触发。
Future<void> showGuTemplateDetailDialog(
    BuildContext context, GameContext ctx, String gid) async {
  final t = ctx.guList[gid];
  if (t == null) return;
  final evolveTo = t.evolveGid.isNotEmpty
      ? ctx.guList[t.evolveGid]?.name ?? t.evolveGid
      : null;

  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _dlgBg,
      title: Row(children: [
        Icon(Icons.bug_report, color: _schoolColor(t.school), size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text(t.name,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('流派', t.school, _schoolColor(t.school)),
              _infoRow('转数', '${t.rank}转凡蛊', const Color(0xFFE67E22)),
              _infoRow('最大耐久', '${t.durabilityMax}', const Color(0xFF27AE60)),
              _infoRow('真元消耗', '${t.costZhen}', const Color(0xFF1ABC9C)),
              if (t.costLife > 0)
                _infoRow('寿元消耗', '${t.costLife}年/次', const Color(0xFFE74C3C)),
              _infoRow('战斗类型', (t.combat['type'] ?? 'passive'), const Color(0xFF9B59B6)),
              if (t.combat['power'] != null && (t.combat['power'] as int) > 0)
                _infoRow('威力', '${t.combat['power']}', const Color(0xFFE74C3C)),
              _infoRow('喜好饲料', t.feedMaterial.join('、'), const Color(0xFF27AE60)),
              if (evolveTo != null)
                _infoRow('进化目标', '→ $evolveTo', const Color(0xFF1ABC9C)),
              const SizedBox(height: 10),
              const Text('描述', style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(t.desc, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
              const SizedBox(height: 8),
              const Text('副作用', style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(t.sideEffect, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
              if (t.habitat.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('栖息地', style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(t.habitat.join('、'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ),
  );
}

Color _schoolColor(String school) {
  switch (school) {
    case '力道': return const Color(0xFFE74C3C);
    case '毒道': return const Color(0xFF9D5CD0);
    case '气道': return const Color(0xFF1ABC9C);
    case '血道': return const Color(0xFFC0392B);
    case '兽道': return const Color(0xFFE67E22);
    case '鬼道': return const Color(0xFF8E44AD);
    case '食道': return const Color(0xFF27AE60);
    case '运道': return const Color(0xFFF1C40F);
    case '月道': return const Color(0xFF5DADE2);
    case '地道': return const Color(0xFFA04000);
    case '寿道': return const Color(0xFFECF0F1);
    case '岁月道': return const Color(0xFFBDC3C7);
    default: return const Color(0xFF95A5A6);
  }
}

// ===================== 随机事件抉择弹窗 =====================

/// 随机事件抉择弹窗【11.随机事件系统】
/// 当 GameContext.pendingEvent 非空时由主界面监听触发。
/// 展示事件剧情文本 + 动态生成抉择触屏选项，点击选项回调 ctx.resolveEventChoice(idx)。
/// 点击外部或"置之不理"视为放弃，回调 ctx.dismissPendingEvent()。
/// barrierDismissible=true 允许点击外部关闭，适配手机单手操作。
Future<void> showEventChoiceDialog(BuildContext context, GameContext ctx) async {
  final ev = ctx.pendingEvent;
  if (ev == null) return;
  final name = ev['name'] ?? '未知事件';
  final desc = ev['desc'] ?? '';
  final isFortune = ev['type'] == 'fortune';
  final choices = (ev['choices'] as List?) ?? [];
  final accent = isFortune ? const Color(0xFF27AE60) : const Color(0xFFE67E22);

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (c) => AlertDialog(
      backgroundColor: _dlgBg,
      title: Row(children: [
        Icon(isFortune ? Icons.auto_awesome : Icons.warning_amber_rounded,
            color: accent, size: 24),
        const SizedBox(width: 8),
        Expanded(child: Text('随机事件 · $name',
            style: TextStyle(color: accent, fontSize: 17, fontWeight: FontWeight.bold))),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  border: Border.all(color: accent, width: 1.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(desc,
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
              ),
              const SizedBox(height: 12),
              const Text('抉择',
                  style: TextStyle(color: _dlgAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              // 动态生成抉择按钮（触控区域放大，适配单手操作）
              for (var i = 0; i < choices.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Navigator.pop(c);
                      ctx.resolveEventChoice(i);
                    },
                    child: Container(
                      width: double.infinity,
                      // 第三阶段新增【13】：放大触控区域，垂直 padding 12
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: _dlgItemBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _dlgAccent.withOpacity(0.5), width: 1),
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: accent.withOpacity(0.25),
                          child: Text('${i + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text((choices[i] as Map)['text'] ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 14))),
                        const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              const Row(children: [
                Icon(Icons.info_outline, color: Colors.white38, size: 14),
                SizedBox(width: 4),
                Expanded(child: Text('选择后将自动结算效果（物资/气运/声望/伤势等）。',
                    style: TextStyle(color: Colors.white38, fontSize: 11))),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(c);
            ctx.dismissPendingEvent();
          },
          child: const Text('置之不理'),
        ),
      ],
    ),
  );
}

// ===================== 域外通道封锁提示弹窗 =====================

/// 域外通道封锁提示弹窗【14.四大域外通道伏笔】
/// 玩家点击 border_ 前缀场景传送时弹出，提示版本未开放。
/// 点击空白处或"关闭"快速关闭。
Future<void> showBorderLockedDialog(BuildContext context, String borderName) async {
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: _dlgBg,
      title: Row(children: [
        const Icon(Icons.lock, color: Color(0xFFE74C3C), size: 24),
        const SizedBox(width: 8),
        const Text('域外古道·禁制封锁',
            style: TextStyle(color: Color(0xFFE74C3C), fontSize: 17, fontWeight: FontWeight.bold)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE74C3C).withOpacity(0.10),
              border: Border.all(color: const Color(0xFFE74C3C), width: 1.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('前方通往「$borderName」的通道被一道上古禁制封锁。',
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                const SizedBox(height: 6),
                const Text('禁制上符文隐现，似在诉说着昔日南疆与域外各州的纷争纠葛。',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.info_outline, color: Color(0xFFE67E22), size: 16),
            SizedBox(width: 6),
            Expanded(child: Text('版本未开放，域外通道暂不可通行。',
                style: TextStyle(color: Color(0xFFE67E22), fontSize: 13))),
          ]),
          const SizedBox(height: 6),
          const Text('四大域外古道伏笔：北原·寒冰古道、西漠·黄沙古道、东海·滨海古道、中州·官道残段。',
              style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
      ],
    ),
  );
}

// ===================== 世界总地图面板 =====================

/// 世界总地图面板【V1.6·域外通道总览】
/// 五大区域状态：
///   - 南疆：已点亮（玩家初始所在区域，默认开启）
///   - 西漠：满足条件解锁（完成南疆主线 + 修为≥5转），否则显示解锁条件
///   - 北原：满足条件解锁（已解锁西漠 + 修为≥5转），否则显示解锁条件【V1.6 开放】
///   - 东海/中州：灰色锁定，版本未开放，保留伏笔
/// 仅读取 player.flags，不修改任何状态，100%兼容旧存档。
/// V1.9 升级【大地图导航系统】：两层级交互式大地图。
/// 层级1：五大区域总览（南疆/西漠/北原/东海/中州），未解锁灰色锁定+提示。
/// 层级2：点击已解锁大区 → 展开该区域全部场景列表 → 点击场景传送。
/// 传送规则（与步行探索双模式共存，不破坏原版）：
///   - 已解锁大区非秘境场景可传送（消耗真元 + 30分钟冷却）；
///   - 秘境（need_gu_）即使地图可见也不可传送，须步行持蛊进入；
///   - 域外关口/太古遗迹/逆流河不可传送；
///   - 传送冷却/真元不足时禁用并提示。
/// 区域危险警示：玩家与该区域所属势力敌对（声望<-70）时显示红色【悬赏区域】警示。
Future<void> showWorldMapPanel(BuildContext context, GameContext ctx) async {
  if (ctx.player == null) return;
  final p = ctx.player!;
  final rank = levelRank(p.level);
  final curRegion = ctx.regionOf(p.location);

  // 各大区解锁状态
  final regions = <_RegionInfo>[
    _RegionInfo(
      name: '南疆', icon: Icons.brightness_high, color: const Color(0xFF1ABC9C),
      desc: '瘴林密布，蛊师林立。青茅山宗族、黑崖寨、散修盟三足鼎立之地。',
      resources: '青茅草、原石、毒囊、月光石', guType: '气道·毒道·月道', danger: '中等',
      unlocked: true, faction: 'nanjiang',
    ),
    _RegionInfo(
      name: '西漠', icon: Icons.brightness_high, color: const Color(0xFFF39C12),
      desc: '黄沙万里，沙暴无常。土道、气道、鬼道蛊虫纵横之地，藏古蛊师遗迹。',
      resources: '流沙石、古蛊师遗骨、炎晶', guType: '地道·风沙道·鬼道', danger: '高',
      unlocked: (p.flags['xisha_unlocked'] as num?)?.toInt() != 0,
      ready: (p.flags['xisha_unlock_ready'] as num?)?.toInt() ?? 0,
      rank: rank, faction: 'ximo',
    ),
    _RegionInfo(
      name: '北原', icon: Icons.ac_unit, color: const Color(0xFF5DADE2),
      desc: '寒冰覆野，雪匪横行。冰道、水道蛊虫纵横之地，永冻冰窟藏冰麟蛊王。',
      resources: '寒冰原石、雪原草药、冻藏蛊材', guType: '冰道·水道·月道', danger: '高',
      unlocked: (p.flags['beiyuan_unlocked'] as num?)?.toInt() != 0,
      depUnlocked: (p.flags['xisha_unlocked'] as num?)?.toInt() ?? 0,
      rank: rank, faction: 'beiyuan',
    ),
    _RegionInfo(
      name: '东海', icon: Icons.waves, color: const Color(0xFF3FD0C9),
      desc: '碧波无垠，海妖潜行。滨海古道通往渔村码头，水道蛊虫的摇篮。',
      resources: '海珍珠、珊瑚碎片、海蛇蜕', guType: '水道·兽道', danger: '高',
      unlocked: (p.flags['donghai_unlocked'] as num?)?.toInt() != 0,
      rank: rank, faction: 'donghai',
    ),
    _RegionInfo(
      name: '中州', icon: Icons.menu_book, color: const Color(0xFFC39BD3),
      desc: '天下腹地，官道残段。诸子百家遗泽犹存，乃蛊道正统传承之源。',
      resources: '灵墨、中原麦穗、古竹简', guType: '气道·光道', danger: '中高',
      unlocked: (p.flags['zhongzhou_unlocked'] as num?)?.toInt() != 0,
      rank: rank, faction: 'zhongzhou',
    ),
  ];

  await showDialog(
    context: context,
    builder: (c) => _WorldMapDialog(
      ctx: ctx, regions: regions, curRegion: curRegion, rank: rank,
    ),
  );
}

/// 区域元数据。
class _RegionInfo {
  final String name;
  final IconData icon;
  final Color color;
  final String desc;
  final String resources;
  final String guType;
  final String danger;
  final bool unlocked;
  final int ready;        // 西漠专用：主线就绪
  final int depUnlocked;  // 北原专用：西漠已解锁
  final int rank;         // 玩家修为
  final String faction;   // 所属势力（用于声望警示）
  const _RegionInfo({
    required this.name, required this.icon, required this.color,
    required this.desc, required this.resources, required this.guType,
    required this.danger, required this.unlocked, required this.faction,
    this.ready = 0, this.depUnlocked = 0, this.rank = 0,
  });
}

/// 大地图对话框（Stateful：支持展开/收起区域场景列表）。
class _WorldMapDialog extends StatefulWidget {
  final GameContext ctx;
  final List<_RegionInfo> regions;
  final String curRegion;
  final int rank;
  const _WorldMapDialog({required this.ctx, required this.regions,
    required this.curRegion, required this.rank});
  @override
  State<_WorldMapDialog> createState() => _WorldMapDialogState();
}

class _WorldMapDialogState extends State<_WorldMapDialog> {
  String? _expandedRegion;

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final p = ctx.player!;
    final cdLeft = ctx.teleportCooldownLeft();
    return AlertDialog(
      backgroundColor: _dlgBg,
      title: Row(children: [
        const Icon(Icons.public, color: _dlgAccent, size: 22),
        const SizedBox(width: 8),
        const Expanded(child: Text('大地图导航',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
        // 传送冷却指示
        if (cdLeft > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE67E22).withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE67E22), width: 0.8),
            ),
            child: Text('传送冷却 $cdLeft分',
                style: const TextStyle(color: Color(0xFFE67E22), fontSize: 10)),
          ),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部当前位置 + 真元
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1ABC9C).withOpacity(0.10),
                  border: Border.all(color: const Color(0xFF1ABC9C), width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.my_location, color: Color(0xFF1ABC9C), size: 16),
                  const SizedBox(width: 6),
                  Text('当前：${widget.curRegion}',
                      style: const TextStyle(color: Color(0xFF1ABC9C), fontSize: 13, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('真元 ${p.trueyuan}/${p.trueyuanMax}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 10),
              // 五大区域卡片
              for (int i = 0; i < widget.regions.length; i++) ...[
                _regionCard(widget.regions[i]),
                if (i < widget.regions.length - 1) const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              // 底部说明
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  border: Border.all(color: Colors.white12, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.info_outline, color: Colors.white54, size: 14),
                      SizedBox(width: 4),
                      Expanded(child: Text('点击已解锁大区展开场景列表，点击场景可传送（消耗真元+30分钟冷却）。',
                          style: TextStyle(color: Colors.white54, fontSize: 11))),
                    ]),
                    SizedBox(height: 4),
                    Text('· 秘境（⭐）须步行持蛊进入，不可传送',
                        style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)),
                    Text('· 太古遗迹/逆流河永久锁定',
                        style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }

  /// 单个区域卡片（点击展开场景列表）。
  Widget _regionCard(_RegionInfo r) {
    final isCurrent = widget.curRegion == r.name;
    final isLit = r.unlocked;
    final cardColor = isLit ? _dlgItemBg : const Color(0xFF1A1A1A);
    final borderColor = isLit ? r.color.withOpacity(0.5) : Colors.white24;
    final nameColor = isLit ? Colors.white : Colors.white38;
    final descColor = isLit ? Colors.white70 : Colors.white38;
    // 声望警示：玩家与该区域势力敌对（<-70）
    final repVal = Reputation.of(widget.ctx.player!, r.faction);
    final isHostile = repVal < -70;
    final expanded = _expandedRegion == r.name;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHostile ? const Color(0xFFE74C3C) : borderColor,
          width: isHostile ? 1.6 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 区域头（可点击展开）
          InkWell(
            onTap: isLit ? () {
              setState(() => _expandedRegion = expanded ? null : r.name);
            } : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(r.icon, color: isLit ? r.color : const Color(0xFF7F8C8D), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(r.name,
                          style: TextStyle(color: nameColor, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1ABC9C),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('你在此',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    else if (!isLit)
                      const Icon(Icons.lock, color: Color(0xFF7F8C8D), size: 16)
                    else
                      Icon(expanded ? Icons.expand_less : Icons.expand_more,
                          color: r.color, size: 20),
                  ]),
                  const SizedBox(height: 6),
                  Text(r.desc, style: TextStyle(color: descColor, fontSize: 12, height: 1.4)),
                  if (isLit) ...[
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 2, children: [
                      _tag('资源:${r.resources}', const Color(0xFF27AE60)),
                      _tag('蛊:${r.guType}', const Color(0xFF8E44AD)),
                      _tag('危险:${r.danger}', const Color(0xFFE67E22)),
                    ]),
                  ],
                  if (isHostile && isLit) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE74C3C).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE74C3C).withOpacity(0.5), width: 0.8),
                      ),
                      child: const Row(children: [
                        Icon(Icons.warning_amber_rounded, color: Color(0xFFE74C3C), size: 14),
                        SizedBox(width: 4),
                        Expanded(child: Text('【悬赏区域】恶行昭著，易遭遇追捕蛊师！',
                            style: TextStyle(color: Color(0xFFE74C3C), fontSize: 11, fontWeight: FontWeight.bold))),
                      ]),
                    ),
                  ],
                  if (!isLit) ...[
                    const SizedBox(height: 6),
                    _unlockHint(r),
                  ],
                ],
              ),
            ),
          ),
          // 展开场景列表
          if (expanded && isLit) _sceneList(r),
        ],
      ),
    );
  }

  /// 场景列表（区域下属全部场景，可点击传送）。
  Widget _sceneList(_RegionInfo r) {
    final ctx = widget.ctx;
    final p = ctx.player!;
    final cdLeft = ctx.teleportCooldownLeft();
    // 该区域全部场景
    final rooms = ctx.rooms.values
        .where((room) => ctx.regionOf(room.rid) == r.name)
        .toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final room in rooms)
            _sceneTile(room, p, cdLeft, r),
        ],
      ),
    );
  }

  /// 单个场景行。
  Widget _sceneTile(Room room, Player p, int cdLeft, _RegionInfo r) {
    final ctx = widget.ctx;
    final isCurrent = p.location == room.rid;
    final isSecret = room.secret.startsWith('need_gu_');
    final visible = ctx.isRoomVisibleOnMap(room);
    if (!visible) return const SizedBox.shrink(); // 秘境未持蛊不显示
    // 可传送判定
    final canTp = !isCurrent && !isSecret && cdLeft <= 0 && p.trueyuan >= ctx.teleportCostOf(r.name);
    final cost = ctx.teleportCostOf(r.name);
    Color tileColor = isCurrent ? const Color(0xFF1ABC9C).withOpacity(0.08) : Colors.transparent;
    return InkWell(
      onTap: canTp ? () async {
        final ok = await ctx.teleportTo(room.rid);
        if (ok && mounted) {
          Navigator.pop(context);
        }
      } : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isCurrent ? const Color(0xFF1ABC9C) : Colors.white12,
            width: isCurrent ? 1 : 0.6,
          ),
        ),
        child: Row(children: [
          Icon(
            isCurrent ? Icons.my_location
              : (isSecret ? Icons.star : (canTp ? Icons.flash_on : Icons.lock_outline)),
            color: isCurrent ? const Color(0xFF1ABC9C)
              : (isSecret ? const Color(0xFFF1C40F) : (canTp ? r.color : const Color(0xFF7F8C8D))),
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.name,
                    style: TextStyle(
                      color: isCurrent ? const Color(0xFF1ABC9C)
                        : (canTp ? Colors.white : Colors.white54),
                      fontSize: 13, fontWeight: FontWeight.bold,
                    )),
                if (isSecret)
                  const Text('⭐秘境·须步行持蛊进入',
                      style: TextStyle(color: Color(0xFFF1C40F), fontSize: 10))
                else if (isCurrent)
                  const Text('当前所在',
                      style: TextStyle(color: Color(0xFF1ABC9C), fontSize: 10))
                else if (cdLeft > 0)
                  Text('传送冷却中($cdLeft分)',
                      style: const TextStyle(color: Color(0xFFE67E22), fontSize: 10))
                else if (p.trueyuan < cost)
                  Text('真元不足(需$cost)',
                      style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 10))
                else
                  Text('传送·消耗$cost真元',
                      style: TextStyle(color: r.color.withOpacity(0.8), fontSize: 10)),
              ],
            ),
          ),
          if (!isCurrent && !isSecret && canTp)
            const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
        ]),
      ),
    );
  }

  /// 区域未解锁提示。
  Widget _unlockHint(_RegionInfo r) {
    String hint;
    if (r.name == '西漠') {
      if (r.ready > 0 && r.rank >= 5) {
        hint = '条件已满足，前往南疆西侧「黄沙古道」催动双蛊破禁即可解锁。';
      } else {
        final buf = <String>[];
        if (r.ready == 0) buf.add('需完成南疆主线『西漠之钥』');
        if (r.rank < 5) buf.add('修为需达五转（当前 ${r.rank} 转）');
        hint = '${buf.join("，")}方可破禁。';
      }
    } else if (r.name == '北原') {
      if (r.depUnlocked > 0 && r.rank >= 5) {
        hint = '条件已满足，前往青茅山北麓「寒冰古道」催动修为破禁即可解锁。';
      } else {
        final buf = <String>[];
        if (r.depUnlocked == 0) buf.add('需先解锁西漠通道');
        if (r.rank < 5) buf.add('修为需达五转（当前 ${r.rank} 转）');
        hint = '${buf.join("，")}方可破禁。';
      }
    } else if (r.name == '东海' || r.name == '中州') {
      hint = r.rank >= 5
        ? '条件已满足，前往南疆对应关口破禁即可解锁。'
        : '需修为达五转（当前 ${r.rank} 转）方可破禁。';
    } else {
      hint = '需要打通区域通道方可进入。';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: r.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: r.color, size: 13),
        const SizedBox(width: 4),
        Expanded(child: Text(hint, style: TextStyle(color: r.color, fontSize: 11, height: 1.4))),
      ]),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10)),
    );
  }
}
