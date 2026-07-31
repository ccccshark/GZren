// command.dart
// 指令解析与分发 + 游戏全局上下文（ChangeNotifier）。
// 实现：移动/场景、角色状态、蛊虫操作、NPC交互、生存行为、系统指令、境界突破。
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/gu_model.dart';
import 'package:gzren/data_model/scene_model.dart';
import 'package:gzren/data_model/npc_model.dart';
import 'package:gzren/data_model/recipe_model.dart';
import 'gu_system.dart' as gu;
import 'player_core.dart' show levelRank, lifespanBase, canBreakthrough, breakthrough;
import 'world_timer.dart' show WorldTimer, actionHours;
import 'npc_ai.dart' show NPCAI, spawnNpcs, npcsInRoom;
import 'combat.dart' show CombatEngine, CombatResult, CombatStatus, TribulationResult;
import 'save_system.dart' as sv;

enum MsgType { system, scene, combat, fortune, danger, gu }

class Msg {
  final String text;
  final MsgType type;
  Msg(this.text, this.type);
}

class GameContext extends ChangeNotifier {
  // 静态数据
  Map<String, GuTemplate> guList = {};
  List<Recipe> recipes = [];
  List<EvolveRecipe> evolveRecipes = [];
  Map<String, Room> rooms = {};
  List<NpcTemplate> npcTemplates = [];
  Map<String, dynamic> materials = {};
  List<Map<String, dynamic>> events = [];
  Map<String, double> eventTriggerChance = {};
  String startRid = 'qingmao_01';

  // 运行时
  Player? player;
  Map<String, Npc> npcs = {};
  late WorldTimer worldTimer;
  late NPCAI npcAi;
  late CombatEngine combatEngine;

  List<Msg> log = [];
  bool inCombat = false;
  CombatResult? combat;
  TribulationResult? tribulation;
  bool inTribulation = false;
  bool gameOver = false;

  // 交互模式：false=图形触屏模式（默认，隐藏指令输入框）；true=进阶模式（显示底部指令输入框）
  bool advancedMode = false;

  void toggleAdvancedMode() {
    advancedMode = !advancedMode;
    notifyListeners();
  }

  void setAdvancedMode(bool v) {
    if (advancedMode == v) return;
    advancedMode = v;
    notifyListeners();
  }

  // ---------- 自定义蛊虫快捷栏（存于 player.flags，旧存档 flags 为空→无快捷栏，100%兼容） ----------
  /// 读取快捷栏蛊名列表（最多 3 个）。flags 无此键时返回空列表。
  List<String> get quickBar {
    final raw = player?.flags['quick_bar'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  /// 设置快捷栏（最多 3 个蛊名）。越界自动截断。
  void setQuickBar(List<String> names) {
    if (player == null) return;
    player!.flags['quick_bar'] = names.take(3).toList();
    notifyListeners();
  }

  // ---------- 新手引导进度（存于 player.flags） ----------
  /// 引导步骤完成集合。flags 无此键时返回空集。
  Set<String> get tutorialDone {
    final raw = player?.flags['tutorial_done'];
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return {};
  }

  void markTutorialDone(String step) {
    if (player == null) return;
    final done = tutorialDone..add(step);
    player!.flags['tutorial_done'] = done.toList();
    notifyListeners();
  }

  // ---------- 状态预警计算（只读，不改游戏状态） ----------
  /// 返回当前需要主动提示的预警列表。空列表表示状态健康。
  /// 用于 UI 主动弹窗：寿元低 / 真元不足 / 有伤势 / 空窍受损(slotBonus<0 或 slotMax 受损标志)。
  List<String> warnings() {
    if (player == null) return [];
    final p = player!;
    final w = <String>[];
    // 寿元低于最大值 20%
    if (p.lifeMax > 0 && p.lifeLeft / p.lifeMax < 0.2) {
      w.add('寿元告急：仅剩 ${p.lifeLeft.toStringAsFixed(0)} 年（不足两成），请尽快突破或服用寿元蛊。');
    }
    // 真元不足（低于 20%）
    if (p.trueyuanMax > 0 && p.trueyuan / p.trueyuanMax < 0.2) {
      w.add('真元不足：仅剩 ${p.trueyuan}/${p.trueyuanMax}，静坐恢复或避免催动高消耗蛊虫。');
    }
    // 有伤势
    if (p.injure.isNotEmpty) {
      w.add('身负伤势：${p.injure.join("、")}，影响战斗与行动，建议疗伤。');
    }
    // 空窍受损（slotBonus < 0 视为受损；原引擎死亡惩罚会 slotMax-=1，此处用 flags 标记）
    if (p.flags['slot_damaged'] == true) {
      w.add('空窍受创：蛊槽上限受损，影响装备蛊虫数量。');
    }
    return w;
  }

  // 死亡回滚快照
  Map<String, dynamic>? _snapshot;

  GameContext() {
    worldTimer = WorldTimer();
    combatEngine = CombatEngine({});
  }

  // ---------- 数据加载 ----------
  Future<void> loadStatic() async {
    final guJson = jsonDecode(await rootBundle.loadString('assets/static/gu_list.json')) as Map<String, dynamic>;
    final guArr = guJson['gu_list'] as List;
    guList = {for (var g in guArr) (g as Map<String, dynamic>)['gid'] as String: GuTemplate.fromJson(g)};
    combatEngine = CombatEngine(guList);

    final rJson = jsonDecode(await rootBundle.loadString('assets/static/recipe.json')) as Map<String, dynamic>;
    recipes = (rJson['recipes'] as List).map((e) => Recipe.fromJson(e as Map<String, dynamic>)).toList();
    evolveRecipes = (rJson['evolve_recipes'] as List? ?? [])
        .map((e) => EvolveRecipe.fromJson(e as Map<String, dynamic>))
        .toList();

    final mJson = jsonDecode(await rootBundle.loadString('assets/static/map.json')) as Map<String, dynamic>;
    final roomList = (mJson['rooms'] as List)
        .map((r) => Room.fromJson(r as Map<String, dynamic>))
        .toList();
    rooms = {for (final r in roomList) r.rid: r};
    startRid = mJson['start_rid'] ?? 'qingmao_01';

    final nJson = jsonDecode(await rootBundle.loadString('assets/static/npc_template.json')) as Map<String, dynamic>;
    npcTemplates = (nJson['npcs'] as List).map((e) => NpcTemplate.fromJson(e as Map<String, dynamic>)).toList();

    materials = jsonDecode(await rootBundle.loadString('assets/static/material.json')) as Map<String, dynamic>;

    final eJson = jsonDecode(await rootBundle.loadString('assets/static/random_event.json')) as Map<String, dynamic>;
    events = (eJson['events'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    eventTriggerChance = Map<String, double>.from(
        (eJson['trigger_chance'] ?? {}).map((k, v) => MapEntry(k, (v as num).toDouble())));
    npcAi = NPCAI(guList);
  }

  // ---------- 输出 ----------
  void out(String text, [MsgType type = MsgType.system]) {
    log.add(Msg(text, type));
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  /// 将当前游戏日志导出为 txt 文件到 APP 私有目录，返回文件路径。
  /// 日志按类型加前缀标签，便于离线查阅。仅写入本地，无网络。
  Future<String?> saveLogToFile() async {
    if (log.isEmpty) return null;
    try {
      final doc = await _docDir();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final f = File('${doc.path}/game_log_$stamp.txt');
      final buf = StringBuffer();
      buf.writeln('蛊真人单机MUD · 游戏日志');
      buf.writeln('角色：${player?.name ?? "-"}　导出时间：$stamp');
      buf.writeln('----------------------------------------');
      for (final m in log) {
        buf.writeln('[${_logTag(m.type)}] ${m.text}');
      }
      f.writeAsStringSync(buf.toString());
      return f.path;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _docDir() async {
    final doc = await getApplicationDocumentsDirectory();
    return doc;
  }

  String _logTag(MsgType t) {
    switch (t) {
      case MsgType.combat: return '战斗';
      case MsgType.fortune: return '机缘';
      case MsgType.danger: return '危险';
      case MsgType.gu: return '蛊';
      case MsgType.scene: return '场景';
      case MsgType.system: return '系统';
    }
  }

  // ---------- 场景/NPC ----------
  Room curRoom() => rooms[player!.location]!;
  List<Npc> npcsInCurRoom() => npcsInRoom(npcs, player!.location);

  // ---------- 新游戏 ----------
  void newGame(String name, String align) {
    final p = Player(name: name, align: align, level: '一转初阶');
    p.location = startRid;
    p.lifeLeft = lifespanBase(p.level);
    p.lifeMax = p.lifeLeft;
    p.inventory = ['探路蛊蛊方', '青茅蛊蛊方', '露水x5', '青茅草根x3', '野草露水x5', '原石x10'];
    p.guBag.add(gu.makeGuInstance('g002', guList));
    p.flags['need_tutorial'] = true; // 标记需要新手引导（UI 据此自动弹出）
    player = p;
    npcs = spawnNpcs(npcTemplates, rooms);
    takeSnapshot();
    clearLog();
    out('欢迎踏入蛊道，$name！你出生于青茅山，一转初阶，前路漫漫。', MsgType.fortune);
    out('提示：先 look 查看场景，gather 采集，refine 炼蛊，equip 装入空窍，help 查看全部指令。', MsgType.system);
    doLook();
  }

  // ---------- 存档 ----------
  Future<bool> saveToSlot(int slot) async {
    final ok = await sv.saveGame(slot, player!, npcs);
    if (ok) {
      takeSnapshot();
      out('【存档成功】已保存至存档位 $slot。', MsgType.system);
    } else {
      out('存档失败。', MsgType.danger);
    }
    return ok;
  }

  Future<bool> loadFromSlot(int slot) async {
    final (loaded, npcStates) = await sv.loadGame(slot);
    if (loaded == null) {
      out('该存档位为空或读档失败。', MsgType.danger);
      return false;
    }
    player = loaded;
    npcs = spawnNpcs(npcTemplates, rooms);
    for (final st in npcStates) {
      final n = npcs[st['nid']];
      if (n != null) n.fromJson(st);
    }
    takeSnapshot();
    clearLog();
    out('读档成功。', MsgType.fortune);
    doLook();
    return true;
  }

  void takeSnapshot() {
    if (player == null) return;
    _snapshot = {
      'player': player!.toJson(),
      'npcs': npcs.values.map((n) => n.toJson()).toList(),
    };
  }

  void restoreSnapshot() {
    if (_snapshot == null) return;
    player = Player.fromJson(Map<String, dynamic>.from(_snapshot!['player'] as Map));
    npcs = spawnNpcs(npcTemplates, rooms);
    for (final st in (_snapshot!['npcs'] as List)) {
      final m = Map<String, dynamic>.from(st as Map);
      final n = npcs[m['nid']];
      if (n != null) n.fromJson(m);
    }
  }

  // ---------- 世界推进 ----------
  void tick(double hours, {String? trigger, bool allowAmbush = false}) {
    if (player == null || !player!.alive) return;
    final tlog = <String>[];
    final ev = worldTimer.advance(player!, hours, tlog);
    for (final l in tlog) {
      out(l, l.contains('劫') || l.contains('耗尽') ? MsgType.danger : MsgType.system);
    }
    if (trigger != null) _maybeRandomEvent(trigger);
    npcAi.tick(npcs, player!, rooms, tlog, worldTimer, allowAmbush: allowAmbush);
    for (final l in tlog) {
      if (l.startsWith('⚠') || l.contains('伏击') || l.contains('击杀') || l.contains('厮杀')) {
        out(l, MsgType.danger);
      } else {
        out(l, MsgType.system);
      }
    }
    if (ev.contains('tribulation') && player!.alive) {
      startTribulation();
    }
    if (!player!.alive) _onNaturalDeath();
  }

  void _maybeRandomEvent(String trigger) {
    final chance = eventTriggerChance[trigger] ?? 0.1;
    final rng = DateTime.now().microsecondsSinceEpoch % 10000 / 10000;
    if (rng >= chance) return;
    final p = player!;
    final rank = levelRank(p.level);
    final pool = events
        .where((e) => e['trigger'] == trigger && (e['min_rank'] as int) <= rank && (e['max_rank'] as int) >= rank)
        .toList();
    if (pool.isEmpty) return;
    pool.shuffle();
    final ev = pool.first;
    _applyEvent(ev);
  }

  void _applyEvent(Map<String, dynamic> ev) {
    final p = player!;
    final isFortune = ev['type'] == 'fortune';
    out('【${ev['name']}】${ev['desc']}', isFortune ? MsgType.fortune : MsgType.danger);
    final eff = ev['effect'] as Map<String, dynamic>?;
    if (eff == null) return;
    if (eff['add_item'] != null) {
      for (final it in eff['add_item']) {
        final (n, c) = MatParser.parse(it);
        gu.addMaterial(p, n, c);
      }
    }
    if (eff['trueyuan'] != null) p.recoverTrueyuan(eff['trueyuan'] as int);
    if (eff['physique'] != null) p.physique = (p.physique + (eff['physique'] as num)).clamp(1, 9999).toInt();
    if (eff['soul_power'] != null) p.soulPower = (p.soulPower + (eff['soul_power'] as num)).clamp(1, 9999).toInt();
    if (eff['life_left'] != null) p.lifeLeft = dmax(0, p.lifeLeft + (eff['life_left'] as num).toDouble());
    if (eff['luck'] != null) p.luck = imax(0, p.luck + (eff['luck'] as int));
    if (eff['injure'] != null) p.addInjure(eff['injure'] as String);
    if (eff['dao_mark'] != null) {
      final dm = eff['dao_mark'] as Map<String, dynamic>;
      dm.forEach((k, v) => p.addDaoMark(k, (v as num).toDouble()));
    }
    if (eff['lose_random_material'] != null) {
      final n = eff['lose_random_material'] as int;
      p.inventory.shuffle();
      final lost = p.inventory.take(n).toList();
      final removeN = n.clamp(0, p.inventory.length).toInt();
      p.inventory.removeRange(0, removeN);
      if (lost.isNotEmpty) out('丢失材料：${lost.join(', ')}', MsgType.danger);
    }
    if (eff['add_gu_rank_max'] != null) {
      final maxr = eff['add_gu_rank_max'] as int;
      final cand = guList.values.where((g) => g.rank <= maxr).toList();
      if (cand.isNotEmpty) {
        cand.shuffle();
        final inst = gu.makeGuInstance(cand.first.gid, guList);
        p.guBag.add(inst);
        out('获得蛊虫：${inst.name}！', MsgType.gu);
      }
    }
  }

  void _onNaturalDeath() {
    out('【寿元已尽，大限将至】你的寿元归零，魂归天地……', MsgType.danger);
    final tlog = <String>[];
    sv.applyDeathPenalty(player!, tlog);
    for (final l in tlog) out(l, MsgType.danger);
    if (_snapshot != null) {
      out('一线生机，你从上次存档状态苏醒。', MsgType.fortune);
      restoreSnapshot();
    } else {
      player!.alive = true;
      player!.physique = imax(10, player!.physique);
      player!.location = startRid;
      player!.trueyuan = player!.trueyuanMax;
      player!.lifeLeft = dmax(5, player!.lifeMax * 0.1);
      out('你在青茅山山脚苏醒，寿元将尽，仅余残年。', MsgType.danger);
    }
  }

  // ===================== 指令 =====================
  void handle(String raw) {
    if (gameOver) return;
    final line = raw.trim();
    if (line.isEmpty) return;
    if (inCombat || inTribulation) return; // 战斗/渡劫由专用方法处理
    final parts = line.split(RegExp(r'\s+'));
    final cmd = parts[0].toLowerCase();
    final args = parts.sublist(1);

    switch (cmd) {
      case 'look': case 'l': doLook(); break;
      case 'go': case 'g': doGo(args); break;
      case 'map': doMap(); break;
      case 'status': case 'st': doStatus(); break;
      case 'inventory': case 'inv': case 'i': doInventory(); break;
      case 'kuang': doKuang(); break;
      case 'breakthrough': case 'bt': doBreakthrough(); break;
      case 'capture': doCapture(args); break;
      case 'refine': doRefine(args); break;
      case 'feed': doFeed(args); break;
      case 'equip': doEquip(args); break;
      case 'unequip': doUnequip(args); break;
      case 'use': doUse(args); break;
      case 'talk': doTalk(args); break;
      case 'trade': doTrade(args); break;
      case 'attack': doAttack(args); break;
      case 'rest': doRest(); break;
      case 'gather': doGather(); break;
      case 'flee': out('你并未身处战斗，无需逃亡。', MsgType.scene); break;
      case 'save': doSave(args); break;
      case 'load': doLoad(args); break;
      case 'help': case 'h': case '?': out(helpText, MsgType.system); break;
      case 'quit': case 'exit': gameOver = true; out('返回主菜单……', MsgType.system); break;
      default: out('未知指令：$cmd，输入 help 查看全部指令。', MsgType.danger);
    }
    notifyListeners();
  }

  void doLook() {
    final r = curRoom();
    out('【${r.name}】', MsgType.scene);
    out(r.description, MsgType.scene);
    if (r.envEffect.isNotEmpty) {
      out('  天地二气：${r.envEffect.entries.map((e) => '${e.key}${e.value.toStringAsFixed(2)}倍').join('、')}', MsgType.system);
    }
    if (r.exits.isNotEmpty) {
      const dirs = {'north': '北', 'south': '南', 'east': '东', 'west': '西'};
      out('  出口：${r.exits.keys.map((d) => dirs[d] ?? d).join('、')}', MsgType.system);
    }
    if (r.wildGu.isNotEmpty) {
      out('  野生蛊虫：${r.wildGu.map((g) => guList[g]?.name ?? g).join(', ')}', MsgType.gu);
    }
    for (final n in npcsInCurRoom()) {
      final tag = n.isHostile ? '[敌对]' : (n.isMerchant ? '[商人]' : '[NPC]');
      out('  $tag ${n.name}（${n.level}）', n.isHostile ? MsgType.danger : MsgType.fortune);
    }
  }

  void doGo(List<String> args) {
    if (args.isEmpty) { out('用法：go north/south/east/west', MsgType.danger); return; }
    const alias = {'n': 'north', 's': 'south', 'e': 'east', 'w': 'west',
      '北': 'north', '南': 'south', '东': 'east', '西': 'west'};
    final d = alias[args[0].toLowerCase()] ?? args[0].toLowerCase();
    final r = curRoom();
    if (!r.exits.containsKey(d)) { out('那个方向没有出路。', MsgType.danger); return; }
    player!.location = r.exits[d]!;
    tick(actionHours['move']!, trigger: 'move');
    doLook();
  }

  void doMap() {
    out('【青茅山 区域地图】', MsgType.scene);
    for (final entry in rooms.entries) {
      final mark = entry.key == player!.location ? '◀你在此' : '';
      out('  [${entry.key}] ${entry.value.name} $mark', MsgType.system);
    }
  }

  void doStatus() {
    final p = player!;
    out('═══ 角色状态 ═══', MsgType.fortune);
    out('  姓名：${p.name}　称号：${p.title.isEmpty ? '无' : p.title}　阵营：${p.align}', MsgType.system);
    out('  境界：${p.level}（${levelRank(p.level)}转）', MsgType.system);
    out('  蛊槽：${p.guInSlot.length}/${p.effectiveSlotMax}（基础${p.slotMax}+空窍加成${p.slotBonus}）', MsgType.system);
    out('  真元：${p.trueyuan}/${p.trueyuanMax}', MsgType.system);
    out('  体魄：${p.physique}　魂力：${p.soulPower}　气运：${p.luck}', MsgType.system);
    final lifeType = p.lifeLeft < 20 ? MsgType.danger : (p.lifeLeft < 50 ? MsgType.scene : MsgType.fortune);
    out('  寿元：${p.lifeLeft.toStringAsFixed(1)}/${p.lifeMax.toInt()} 年', lifeType);
    if (p.daoMark.isNotEmpty) {
      out('  道痕：${p.daoMark.entries.map((e) => '${e.key}:${e.value.toInt()}').join('、')}', MsgType.gu);
    }
    out('  伤势：${p.injure.isEmpty ? '无' : p.injure.join('、')}', p.injure.isEmpty ? MsgType.system : MsgType.danger);
    out('  劫数：${p.tribulation.toInt()}（积满触发天劫）', MsgType.scene);
    out('  杀戮：${p.kills}　炼蛊造诣：${p.refineProficiency.toInt()}', MsgType.system);
    out('  世界时间：已过 ${p.worldTime.toInt()} 小时（约 ${(p.worldTime / 1440).toStringAsFixed(2)} 年）', MsgType.system);
  }

  void doInventory() {
    final p = player!;
    out('【背包物资】', MsgType.fortune);
    if (p.inventory.isEmpty) out('  （空空如也）', MsgType.system);
    for (final it in p.inventory) out('  · $it', MsgType.system);
    out('【寄存蛊虫】', MsgType.gu);
    if (p.guBag.isEmpty) out('  （无）', MsgType.system);
    for (final g in p.guBag) {
      final mut = g.mutated ? '[变异]' : '';
      out('  · ${g.name} $mut（${g.rank}转/${g.school}）耐久 ${g.durability}/${g.durabilityMax}', MsgType.gu);
    }
  }

  void doKuang() {
    final p = player!;
    out('【空窍·蛊槽】已用 ${p.guInSlot.length}/${p.effectiveSlotMax}', MsgType.gu);
    if (p.guInSlot.isEmpty) out('  （空窍空空，尚未安放蛊虫）', MsgType.system);
    for (final g in p.guInSlot) {
      final mut = g.mutated ? '[变异]' : '';
      out('  · ${g.name} $mut（${g.rank}转/${g.school}）耐久 ${g.durability}/${g.durabilityMax}  真元消耗${g.costZhen}', MsgType.gu);
    }
  }

  void doBreakthrough() {
    final p = player!;
    if (!canBreakthrough(p)) { out('你已至九转巅峰，无更高境界可破。', MsgType.scene); return; }
    if (p.daoMark.isEmpty) { out('你尚未积累任何道痕，无法突破！需持续使用同流派蛊累积道痕。', MsgType.danger); return; }
    final maxDao = p.daoMark.values.reduce((a, b) => a > b ? a : b);
    final need = levelRank(p.level) * 15;
    if (maxDao < need) { out('道痕不足！当前最高道痕 ${maxDao.toInt()}，突破需 $need。继续修行。', MsgType.danger); return; }
    tick(actionHours['rest']!);
    final log2 = breakthrough(p);
    for (final l in log2) out(l, MsgType.fortune);
  }

  void doCapture(List<String> args) {
    if (args.isEmpty) { out('用法：capture [蛊虫名]（先 look 查看野生蛊虫）', MsgType.danger); return; }
    final target = args.join(' ');
    final gid = _resolveWildGid(target);
    if (gid == null) { out('当前场景没有名为 $target 的野生蛊虫。', MsgType.danger); return; }
    final l = gu.capture(player!, gid, guList, curRoom());
    for (final s in l) out(s, MsgType.gu);
    tick(actionHours['capture']!, allowAmbush: true);
  }

  void doRefine(List<String> args) {
    if (args.isEmpty) {
      out('用法：refine [蛊方名称]（你持有的蛊方见 inventory）', MsgType.danger);
      out('可炼蛊方：', MsgType.system);
      for (final r in recipes) {
        if (player!.inventory.contains(r.name)) {
          out('  · ${r.name} -> ${guList[r.outputGid]?.name ?? '?'}', MsgType.system);
        }
      }
      return;
    }
    final l = gu.refine(player!, args.join(' '), recipes, guList);
    for (final s in l) out(s, MsgType.gu);
    tick(actionHours['refine']!, allowAmbush: true);
  }

  void doFeed(List<String> args) {
    if (args.length < 2) { out('用法：feed [蛊名] [材料名]', MsgType.danger); return; }
    final l = gu.feed(player!, args[0], args.sublist(1).join(' '));
    for (final s in l) out(s, MsgType.gu);
    tick(actionHours['use_gu']!, allowAmbush: true);
  }

  void doEquip(List<String> args) {
    if (args.isEmpty) { out('用法：equip [蛊名]', MsgType.danger); return; }
    for (final s in gu.equip(player!, args.join(' '))) out(s, MsgType.gu);
  }

  void doUnequip(List<String> args) {
    if (args.isEmpty) { out('用法：unequip [蛊名]', MsgType.danger); return; }
    for (final s in gu.unequip(player!, args.join(' '))) out(s, MsgType.gu);
  }

  void doUse(List<String> args) {
    if (args.isEmpty) { out('用法：use [蛊名]', MsgType.danger); return; }
    for (final s in gu.useGu(player!, args[0])) out(s, MsgType.gu);
    tick(actionHours['use_gu']!, allowAmbush: true);
  }

  void doTalk(List<String> args) {
    if (args.isEmpty) { out('用法：talk [npc名]', MsgType.danger); return; }
    final n = _findNpc(args.join(' '));
    if (n == null) { out('这里没有这个人。', MsgType.danger); return; }
    if (!n.alive) { out('${n.name} 已死。', MsgType.danger); return; }
    if (n.dialogue.isNotEmpty) {
      out('${n.name}：${n.dialogue[DateTime.now().millisecond % n.dialogue.length]}', MsgType.fortune);
    } else {
      out('${n.name} 沉默不语。', MsgType.system);
    }
    tick(actionHours['talk']!);
  }

  void doTrade(List<String> args) {
    if (args.isEmpty) { out('用法：trade [npc名]', MsgType.danger); return; }
    final n = _findNpc(args.join(' '));
    if (n == null) { out('这里没有这个人。', MsgType.danger); return; }
    if (!n.isMerchant) { out('${n.name} 并非商人，无法交易。', MsgType.danger); return; }
    out('【${n.name} 的货物】（原石=通用货币）', MsgType.fortune);
    for (final e in n.tradeGoods.entries) out('  · ${e.key}  价格:${e.value}原石', MsgType.system);
    out('请在输入框输入：buy [物品名] [数量] / sell [材料名] [数量]', MsgType.scene);
    tick(actionHours['trade']!);
  }

  /// 交易指令由 UI 输入框直接传入处理
  void doTradeAction(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.isEmpty) return;
    final p = player!;
    final npc = npcsInCurRoom().firstWhere((n) => n.isMerchant, orElse: () => npcsInCurRoom().first);
    if (parts[0] == 'buy' && parts.length >= 2) {
      final item = parts.length >= 3 && int.tryParse(parts.last) != null ? parts.sublist(1, parts.length - 1).join(' ') : parts.sublist(1).join(' ');
      final cnt = int.tryParse(parts.last) ?? 1;
      final price = (npc.tradeGoods[item] ?? 0) * cnt;
      if (price == 0) { out('${npc.name} 不出售 $item。', MsgType.danger); return; }
      if (gu.countMaterial(p, '原石') < price) { out('原石不足，需 $price 原石。', MsgType.danger); return; }
      gu.consumeMaterial(p, '原石', price);
      gu.addMaterial(p, item, cnt);
      out('购入 ${item}x$cnt，消耗 $price 原石。', MsgType.fortune);
    } else if (parts[0] == 'sell' && parts.length >= 2) {
      final item = parts.length >= 3 && int.tryParse(parts.last) != null ? parts.sublist(1, parts.length - 1).join(' ') : parts.sublist(1).join(' ');
      final cnt = int.tryParse(parts.last) ?? 1;
      if (!gu.hasMaterial(p, item, cnt)) { out('背包中 $item 不足。', MsgType.danger); return; }
      final matInfo = (materials['materials'] ?? {}) as Map;
      final priceInfo = ((matInfo[item] ?? {}) as Map)['price'] ?? 1;
      final price = imax(1, ((priceInfo as num) * 0.6).toInt()) * cnt;
      gu.consumeMaterial(p, item, cnt);
      gu.addMaterial(p, '原石', price);
      out('出售 ${item}x$cnt，获得 $price 原石。', MsgType.fortune);
    } else {
      out('未识别的交易指令。', MsgType.danger);
    }
  }

  void doAttack(List<String> args) {
    if (args.isEmpty) { out('用法：attack [npc名]', MsgType.danger); return; }
    final n = _findNpc(args.join(' '));
    if (n == null) { out('这里没有可以攻击的目标。', MsgType.danger); return; }
    if (!n.alive) { out('${n.name} 已死。', MsgType.danger); return; }
    out('你向 ${n.name} 发起攻击！', MsgType.combat);
    final env = curRoom().envEffect;
    combat = combatEngine.startCombat(player!, n, env);
    inCombat = true;
    for (final l in combat!.log) out(l, l.contains('战斗') || l.contains('伤害') ? MsgType.combat : MsgType.system);
  }

  /// 战斗中玩家行动（由战斗UI调用）
  void combatAction(String action, [String? guName]) {
    if (combat == null) return;
    final before = combat!.log.length;
    combat = combatEngine.playerAction(combat!, action, guName);
    for (final l in combat!.log.sublist(before)) {
      out(l, l.contains('伤害') || l.contains('击败') || l.contains('逃') ? MsgType.combat : MsgType.system);
    }
    if (combat!.status != CombatStatus.ongoing) {
      inCombat = false;
      if (combat!.status == CombatStatus.win) {
        combat!.npc.alive = false;
        combat!.npc.deathTime = player!.worldTime;
        combat!.npc.hatePlayer = 0;
      } else if (combat!.status == CombatStatus.lose) {
        _onDefeated(combat!.npc);
      }
      tick(actionHours['combat_end']!);
      combat = null;
    }
  }

  void startTribulation() {
    out('⚡ 劫数已满，天劫将至！你须渡过雷劫。', MsgType.danger);
    tribulation = combatEngine.startTribulation(player!);
    inTribulation = true;
    for (final l in tribulation!.log) out(l, l.contains('劫') || l.contains('雷') ? MsgType.danger : MsgType.system);
  }

  void tribulationAction(String action) {
    if (tribulation == null) return;
    final before = tribulation!.log.length;
    tribulation = combatEngine.tribulationAction(tribulation!, action);
    for (final l in tribulation!.log.sublist(before)) {
      out(l, l.contains('成功') ? MsgType.fortune : (l.contains('失败') || l.contains('雷') ? MsgType.danger : MsgType.system));
    }
    if (tribulation!.finished) {
      inTribulation = false;
      if (!tribulation!.survived) _onDefeated(null, tribulation: true);
      tribulation = null;
    }
  }

  void _onDefeated(Npc? npc, {bool tribulation = false}) {
    final p = player!;
    if (tribulation) {
      out('【渡劫失败·陨落】天劫之威非你所能抗……', MsgType.danger);
    } else {
      out('【你被 ${npc!.name} 击败！】', MsgType.danger);
    }
    final tlog = <String>[];
    sv.applyDeathPenalty(p, tlog);
    for (final l in tlog) out(l, MsgType.danger);
    if (_snapshot != null) {
      out('冥冥中一线生机，你从上次存档的状态苏醒……', MsgType.fortune);
      restoreSnapshot();
    } else {
      p.alive = true;
      p.physique = imax(10, p.physique);
      p.location = startRid;
      p.trueyuan = p.trueyuanMax;
      p.lifeLeft = dmax(1, p.lifeLeft);
      out('你在青茅山山脚苏醒，劫后余生。', MsgType.fortune);
    }
  }

  void doRest() {
    final p = player!;
    final recover = 20 + levelRank(p.level) * 5;
    p.recoverTrueyuan(recover);
    p.physique = imin(100 + levelRank(p.level) * 20, p.physique + 5);
    if (p.injure.contains('轻伤') && DateTime.now().millisecond % 2 == 0) p.healInjure('轻伤');
    out('你静坐修炼，恢复 $recover 真元，体魄略有恢复。', MsgType.fortune);
    tick(actionHours['rest']!, trigger: 'rest', allowAmbush: true);
  }

  void doGather() {
    final r = curRoom();
    if (r.refreshResource.isEmpty) { out('这里没有可采集的资源。', MsgType.danger); return; }
    final gained = r.refreshResource[DateTime.now().millisecond % r.refreshResource.length];
    final cnt = 1 + DateTime.now().millisecond % 2;
    gu.addMaterial(player!, gained, cnt);
    out('你采集到 ${gained}x$cnt。', MsgType.fortune);
    if (DateTime.now().microsecond % 10 == 0) {
      gu.addMaterial(player!, '原石', 1);
      out('额外发现原石x1！原石是通用货币。', MsgType.fortune);
    }
    tick(actionHours['gather']!, trigger: 'gather', allowAmbush: true);
  }

  void doSave(List<String> args) {
    final slot = (args.isNotEmpty && int.tryParse(args[0]) != null) ? int.parse(args[0]) : 0;
    if (slot < 1 || slot > 5) { out('用法：save [1~5]', MsgType.danger); return; }
    saveToSlot(slot);
  }

  void doLoad(List<String> args) {
    final slot = (args.isNotEmpty && int.tryParse(args[0]) != null) ? int.parse(args[0]) : 0;
    if (slot < 1 || slot > 5) { out('用法：load [1~5]', MsgType.danger); return; }
    loadFromSlot(slot);
  }

  Npc? _findNpc(String name) {
    for (final n in npcsInCurRoom()) {
      if (n.name.contains(name) || name == n.nid) return n;
    }
    return null;
  }

  String? _resolveWildGid(String target) {
    final r = curRoom();
    for (final gid in r.wildGu) {
      final t = guList[gid];
      if (t != null && (target == gid || target == t.name || t.name.contains(target))) return gid;
    }
    return null;
  }
}

// 小工具（Dart 不支持函数重载，分别命名）
int imax(int a, int b) => a > b ? a : b;
double dmax(double a, double b) => a > b ? a : b;
int imin(int a, int b) => a < b ? a : b;

const String helpText = '''
══════════ 蛊真人单机MUD · 指令列表 ══════════

【移动与场景】
  look / go north|south|east|west / map
【角色状态】
  status / inventory / kuang / breakthrough(境界突破)
【蛊虫操作】
  capture [目标] / refine [蛊方] / feed [蛊] [材料]
  equip [蛊] / unequip [蛊] / use [蛊]
【NPC交互】
  talk [npc] / trade [npc] / attack [npc] / flee
【生存行为】
  rest / gather
【系统指令】
  save [1~5] / load [1~5] / help / quit
''';
