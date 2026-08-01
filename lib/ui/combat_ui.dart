// combat_ui.dart
// 战斗/天劫渡劫独立界面：实时文字刷新 + 战斗快捷按钮。
import 'package:flutter/material.dart';
import '../engine/command.dart';
import '../data_model/gu_model.dart';
import '../data_model/killer_move_model.dart' show KillerMoveStore;

class CombatUIPage extends StatefulWidget {
  final GameContext ctx;
  final bool isTribulation;
  const CombatUIPage({super.key, required this.ctx, required this.isTribulation});
  @override
  State<CombatUIPage> createState() => _CombatUIPageState();
}

class _CombatUIPageState extends State<CombatUIPage> {
  final ScrollController _scroll = ScrollController();
  GameContext get ctx => widget.ctx;
  bool get trib => widget.isTribulation;

  @override
  void initState() {
    super.initState();
    ctx.addListener(_onChanged);
  }

  @override
  void dispose() {
    ctx.removeListener(_onChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Color _msgColor(MsgType t) {
    switch (t) {
      case MsgType.combat: case MsgType.danger: return const Color(0xFFE74C3C);
      case MsgType.fortune: return const Color(0xFF27AE60);
      case MsgType.gu: return const Color(0xFF9B59B6);
      case MsgType.scene: return const Color(0xFFE67E22);
      case MsgType.system: return Colors.white;
    }
  }

  List<GuInstance> get _attackGus {
    final p = ctx.player!;
    return p.guInSlot.where((g) =>
        g.combat['type'] == 'attack' || g.combat['type'] == 'attack_poison').toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = ctx.player!;
    final npcName = trib ? '天劫雷罚' : ctx.combat!.npc.name;
    final npcHp = trib ? '-' : ctx.combat!.npc.physique;
    return Scaffold(
      appBar: AppBar(
        title: Text(trib ? '⚡ 天劫渡劫 ⚡' : '战斗中'),
        backgroundColor: trib ? const Color(0xFF7B241C) : const Color(0xFF7B241C),
        automaticallyImplyLeading: false,
      ),
      body: Column(children: [
        // 状态条
        Container(
          color: const Color(0xFF1A1A1A),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(child: Text('你 体魄:${p.physique} 真元:${p.trueyuan}', style: const TextStyle(color: Colors.green))),
            Expanded(child: Text('$npcName 体魄:$npcHp', style: const TextStyle(color: Colors.red), textAlign: TextAlign.right)),
          ]),
        ),
        // 战斗文字
        Expanded(
          child: Container(
            color: const Color(0xFF0E0E0E),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(10),
              itemCount: ctx.log.length,
              itemBuilder: (_, i) {
                final m = ctx.log[i];
                return Text(m.text, style: TextStyle(color: _msgColor(m.type), fontSize: 14, height: 1.3));
              },
            ),
          ),
        ),
        // 战斗快捷按钮
        Container(
          color: const Color(0xFF1A1A1A),
          padding: const EdgeInsets.all(6),
          child: trib ? _tribButtons() : _combatButtons(),
        ),
      ]),
    );
  }

  Widget _combatButtons() {
    // V1.3 新增：已构筑杀招列表，战斗内一键整套释放（同流派协同加成）
    final killerMoves = KillerMoveStore.list(ctx.player!);
    return Wrap(
      spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
      children: [
        ..._attackGus.map((g) => ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B241C)),
          onPressed: () => ctx.combatAction('attack', g.name),
          child: Text('催动·${g.name}'),
        )),
        // V1.3 新增【杀招一键释放】：点击释放整套组合
        ...killerMoves.map((km) => ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)),
          onPressed: () => ctx.combatAction('killmove', km.name),
          child: Text('杀招·${km.name}'),
        )),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C3E50)),
          onPressed: () => ctx.combatAction('defend'),
          child: const Text('防御'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F8C8D)),
          onPressed: () => ctx.combatAction('flee'),
          child: const Text('尝试逃亡'),
        ),
      ],
    );
  }

  Widget _tribButtons() {
    return Wrap(
      spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
      children: [
        ...ctx.player!.guInSlot.where((g) => g.combat['type'] == 'defense').map((g) =>
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C3E50)),
            onPressed: () => ctx.tribulationAction('use ${g.name}'),
            child: Text('催动·${g.name}'),
          )),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C3E50)),
          onPressed: () => ctx.tribulationAction('defend'),
          child: const Text('全力防御'),
        ),
      ],
    );
  }
}
