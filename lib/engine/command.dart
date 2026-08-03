// command.dart
// 指令解析与分发 + 游戏全局上下文（ChangeNotifier）。
// 实现：移动/场景、角色状态、蛊虫操作、NPC交互、生存行为、系统指令、境界突破。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:gzren/utils/safe_json_loader.dart' as safe_json;
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/gu_model.dart';
import 'package:gzren/data_model/scene_model.dart';
import 'package:gzren/data_model/npc_model.dart';
import 'package:gzren/data_model/recipe_model.dart';
import 'package:gzren/data_model/slot_capacity_model.dart' as slot_capacity_model; // 第二阶段：空窍容量
import 'package:gzren/data_model/storage_gu_model.dart' as storage_gu_model;     // 第二阶段：储物蛊
import 'package:gzren/data_model/food_model.dart' as food_model;               // 第二阶段：食物滋养
import 'package:gzren/data_model/killer_move_model.dart' as killer_move_model; // 第二阶段：杀招构筑
import 'package:gzren/data_model/reputation_model.dart' as reputation_model;   // 第二阶段：势力声望
import 'package:gzren/data_model/trade_upgrade_model.dart' as trade_upgrade;   // 第二阶段：交易升级（黑市/悬赏/以物易物）
import 'gu_system.dart' as gu;
import 'player_core.dart' show levelRank, lifespanBase, canBreakthrough, breakthrough;
import 'world_timer.dart' show WorldTimer, actionHours;
import 'npc_ai.dart' show NPCAI, spawnNpcs, npcsInRoom;
import 'combat.dart' show CombatEngine, CombatResult, CombatStatus, TribulationResult;
import 'save_system.dart' as sv;
import 'poison_system.dart' show PoisonSystem;
import 'phase2_core.dart' as phase2_core; // 第二阶段：每日结算钩子
import '../data_model/poison_model.dart' show PoisonStore, PoisonRank;
import '../data_model/slot_capacity_model.dart' show SlotCapacity; // 简化访问
import '../data_model/storage_gu_model.dart' show StorageGu;      // 简化访问
import '../data_model/food_model.dart' show FoodSystem, FoodEffect;
import '../data_model/killer_move_model.dart' show KillerMoveStore, KillerMove, PresetKillerMoveStore, PresetKillerMove;
import '../data_model/reputation_model.dart' show Reputation, Faction;
import '../data_model/trade_upgrade_model.dart' show BountyQuest, BountyBoard, Barter, BlackMarket;
import 'environment_system.dart' show EnvironmentSystem; // V1.3：昼夜/天气/BOSS环境系统
import 'quest_system.dart' show QuestSystem; // V1.4：主线/支线/循环委托任务系统
import 'npc_affinity_system.dart' show NpcAffinity; // V1.4：NPC好感度剧情分支

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
  // 第三阶段新增：战斗生态配置（环境增益/毒素叠加/暗伤叠加/NPC AI战术/战利品规则）
  Map<String, dynamic> battleConfig = {};
  String startRid = 'qingmao_01';

  // BUG修复【老槐翁原石循环刷取漏洞】：交易黑名单。
  // 货币类物品（原石）禁止作为商品买卖：NPC不出售（不显示在售卖列表），
  // 玩家也无法出售给NPC（杜绝 sell原石→得原石 的无限复制闭环）。
  // 兼容性：不改动JSON结构，纯代码层拦截，旧存档无影响。
  static const Set<String> tradeBlacklist = {'原石'};

  /// 判断物品是否在交易黑名单中（货币类，不可作为商品流通）。
  /// UI 交易面板据此过滤商品列表，底层 doTradeAction 据此拦截买卖。
  bool isTradeBlacklisted(String item) => tradeBlacklist.contains(item);

  // 运行时
  Player? player;
  Map<String, Npc> npcs = {};
  late WorldTimer worldTimer;
  late NPCAI npcAi;
  late CombatEngine combatEngine;

  // V2.0 内存优化【五域懒加载】：已加载地域集合，避免重复加载。
  // 启动时只加载核心资源（主地图+主蛊虫+基础配置），五域资源按需加载。
  final Set<String> _loadedRegions = {};

  // V1.9 新增【自动存档系统】
  Timer? _autoSaveTimer;
  bool get autoSaveEnabled => (player?.flags['auto_save_enabled'] as num?)?.toInt() != 0;
  set autoSaveEnabled(bool v) {
    player?.flags['auto_save_enabled'] = v ? 1 : 0;
    sv.SafeSaveManager.instance.autoSaveEnabled = v;
    notifyListeners();
  }
  /// 供 UI 监听的自动存档状态：(ok, msg, isError)
  sv.AutoSaveStatusFn? onAutoSaveStatus;
  String lastAutoSaveMsg = '';
  bool lastAutoSaveIsError = false;

  /// 游戏日志缓冲区（有上限管控，超出自动丢弃旧记录）。
  static const int maxLogEntries = 500;

  List<Msg> log = [];
  bool inCombat = false;
  CombatResult? combat;
  TribulationResult? tribulation;
  bool inTribulation = false;
  bool gameOver = false;

  // 第三阶段新增【11.随机事件系统】：待抉择事件。
  // 当触发的事件含 choices 数组时，引擎不自动结算，而是把事件挂起到 pendingEvent，
  // 由 UI 监听后弹出抉择弹窗，玩家点击选项回调 resolveEventChoice(idx) 结算。
  // 旧存档无此字段，默认 null，100% 兼容。
  Map<String, dynamic>? pendingEvent;

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

  /// 清除新手引导自动弹出标记（引导全部完成后调用）。
  void clearTutorialNeeded() {
    if (player == null) return;
    player!.flags['need_tutorial'] = false;
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
    // 中毒预警（接入【毒素中毒系统】）
    final poisons = PoisonStore.list(p);
    if (poisons.isNotEmpty) {
      final hasDao = poisons.any((x) => x.rank == PoisonRank.dao);
      final hasOdd = poisons.any((x) => x.rank == PoisonRank.odd);
      final hasFierce = poisons.any((x) => x.rank == PoisonRank.fierce);
      final sev = hasDao ? '道毒缠身，危及道基'
          : (hasOdd ? '奇毒攻心，寻常草药蛊虫难解'
          : (hasFierce ? '烈性毒素发作中' : '轻微毒素入体'));
      w.add('中毒状态：${poisons.map((x) => x.name).join("、")}（$sev）。'
          '可静坐代谢/服解毒草药/催动解毒蛊/燃烧寿元逼毒。');
    }
    // 第二阶段：空窍过载
    if (SlotCapacity.strictMode(p) && SlotCapacity.isOverloaded(p)) {
      w.add('【空窍容量过载】容量 ${SlotCapacity.usedCapacity(p)}/${SlotCapacity.capacityMax(p)}：真元恢复暴跌，且持续滋生暗伤。请取出高转蛊或服用拓窍蛊扩容。');
    }
    // 第二阶段：饥饿
    if (FoodSystem.strictMode(p)) {
      final left = FoodSystem.satietyHoursLeft(p);
      if (left <= 0) {
        w.add('【饥饿状态】久未进食，体魄每日持续流失，请尽快进食！');
      } else if (left < 6) {
        w.add('【半饥半饱】饱食仅剩 ${left.toStringAsFixed(0)} 小时，请尽快进食补充。');
      }
    }
    // 第二阶段：储物蛊容量
    if (StorageGu.strictMode(p) && StorageGu.freeCapacity(p) < 0) {
      w.add('【储物超载】背包 ${StorageGu.usedCapacity(p)}/${StorageGu.capacityMax(p)}，无法继续携带物资，请装备储物蛊或整理。');
    }
    return w;
  }

  // 死亡回滚快照
  Map<String, dynamic>? _snapshot;

  GameContext() {
    worldTimer = WorldTimer();
    combatEngine = CombatEngine({});
    // V1.9 新增【自动存档系统】：挂载状态回调 + 启动180s定时轮询。
    // 状态回调挂两次：先记录供 UI 读取，再调用外部 onAutoSaveStatus。
    sv.SafeSaveManager.instance.onStatus = (ok, msg, isErr) {
      lastAutoSaveMsg = msg;
      lastAutoSaveIsError = isErr;
      onAutoSaveStatus?.call(ok, msg, isErr);
      // 写入日志（小字提示用）
      out(msg, isErr ? MsgType.danger : MsgType.gu);
    };
    // 180s 轮询兜底自动存档（空闲态）
    _autoSaveTimer = Timer.periodic(
      const Duration(seconds: sv.autoPollIntervalSec),
      (_) => _triggerAutoSave('poll'),
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    sv.SafeSaveManager.instance.onStatus = null;
    super.dispose();
  }

  /// V1.9 新增【自动存档】：包装统一触发入口。
  /// 游戏未开始（无 player）直接跳过；节流由 SafeSaveManager 内部实现。
  Future<void> _triggerAutoSave(String reason) async {
    if (player == null || !player!.alive || gameOver) return;
    if (sv.SafeSaveManager.instance.isWriting) return;
    await sv.SafeSaveManager.instance.autoSave(
      player: player!,
      npcs: npcs,
      triggerReason: reason,
    );
  }

  /// V1.9 新增【自动存档触发③】：应用退至后台（onPause）触发。
  /// 公开方法供 UI 层 WidgetsBindingObserver 回调调用。
  /// force=true 跳过 3s 节流（切后台属于重要时机，必须尝试写盘）。
  Future<void> onPauseAutoSave() async {
    if (player == null || !player!.alive || gameOver) return;
    if (sv.SafeSaveManager.instance.isWriting) return;
    await sv.SafeSaveManager.instance.autoSave(
      player: player!,
      npcs: npcs,
      triggerReason: 'on_pause',
      force: true,
    );
  }

  // ---------- 数据加载 ----------
  /// V2.0 内存优化：启动时只加载核心资源，五域资源按需加载。
  /// 核心=主地图(map.json)+蛊虫主表(gu_list.json)+蛊方(recipe.json)+NPC模板主表+
  /// 材料主表+随机事件主表+战斗配置+杀招+时间天气+任务。
  /// 五域扩展(map_nanjiang/ximo/beiyuan/donghai/zhongzhou+配套gu/material/npc/event/weather)
  /// 在玩家首次进入对应地域时由 ensureRegionLoaded() 懒加载。
  Future<void> loadStatic() async {
    // V3.1 兼容调用：依次调用各分批加载方法，完整加载全部静态资源。
    await loadStaticGuList();
    await loadStaticRecipe();
    await loadStaticMap();
    await loadStaticNpc();
    await loadStaticMaterial();
    await loadStaticEvent();
    await loadStaticEnvironment();
    await loadStaticQuest();
    // 五域懒加载：南疆为起始区域，启动时加载
    _loadedRegions.add('南疆');
    await loadStaticRegion();
    npcAi = NPCAI(guList);
  }

  /// 批量加载：蛊虫主表 gu_list.json（核心资源，失败抛异常）。
  Future<void> loadStaticGuList() async {
    final result = await safe_json.loadAssetJson('assets/static/gu_list.json');
    if (result.isFailure) {
      debugPrint('${result.error}');
      throw Exception('gu_list.json 加载失败: ${result.error}');
    }
    final guJson = result.data as Map<String, dynamic>;
    final guArr = guJson['gu_list'] as List;
    guList = {for (var g in guArr) (g as Map<String, dynamic>)['gid'] as String: GuTemplate.fromJson(g)};
    combatEngine = CombatEngine(guList);
  }

  /// 批量加载：蛊方 recipe.json（失败时使用空列表）。
  Future<void> loadStaticRecipe() async {
    final result = await safe_json.loadAssetJson('assets/static/recipe.json');
    if (result.isFailure) {
      debugPrint('${result.error}');
      recipes = [];
      evolveRecipes = [];
      return;
    }
    final rJson = result.data as Map<String, dynamic>;
    recipes = (rJson['recipes'] as List).map((e) => Recipe.fromJson(e as Map<String, dynamic>)).toList();
    evolveRecipes = (rJson['evolve_recipes'] as List? ?? [])
        .map((e) => EvolveRecipe.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 批量加载：主地图 map.json（核心资源，失败抛异常）。
  Future<void> loadStaticMap() async {
    final result = await safe_json.loadAssetJson('assets/static/map.json');
    if (result.isFailure) {
      debugPrint('${result.error}');
      throw Exception('map.json 加载失败: ${result.error}');
    }
    final mJson = result.data as Map<String, dynamic>;
    final roomList = (mJson['rooms'] as List)
        .map((r) => Room.fromJson(r as Map<String, dynamic>))
        .toList();
    rooms = {for (final r in roomList) r.rid: r};
    startRid = mJson['start_rid'] ?? 'qingmao_01';
  }

  /// 批量加载：NPC模板主表 npc_template.json（失败时使用空列表）。
  Future<void> loadStaticNpc() async {
    final result = await safe_json.loadAssetJson('assets/static/npc_template.json');
    if (result.isFailure) {
      debugPrint('${result.error}');
      npcTemplates = [];
      return;
    }
    final nJson = result.data as Map<String, dynamic>;
    npcTemplates = (nJson['npcs'] as List).map((e) => NpcTemplate.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 批量加载：材料主表 material.json（失败时使用空 Map）。
  Future<void> loadStaticMaterial() async {
    final result = await safe_json.loadAssetJson('assets/static/material.json');
    if (result.isFailure) {
      debugPrint('${result.error}');
      materials = {};
      return;
    }
    materials = result.data as Map<String, dynamic>;
  }

  /// 批量加载：随机事件主表 random_event.json + 全局奇遇 event_global.json（失败时使用空数据）。
  Future<void> loadStaticEvent() async {
    final result = await safe_json.loadAssetJson('assets/static/random_event.json');
    if (result.isFailure) {
      debugPrint('${result.error}');
      events = [];
      eventTriggerChance = {};
      return;
    }
    final eJson = result.data as Map<String, dynamic>;
    events = (eJson['events'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    eventTriggerChance = Map<String, double>.from(
        (eJson['trigger_chance'] ?? {}).map((k, v) => MapEntry(k, (v as num).toDouble())));

    // 全局奇遇（可选，静默跳过）
    final egResult = await safe_json.loadAssetJson('assets/static/event_global.json', source: 'event_global.json');
    if (egResult.isSuccess) {
      final egJson = egResult.data as Map<String, dynamic>;
      for (final e in (egJson['events'] as List)) {
        events.add(Map<String, dynamic>.from(e as Map));
      }
    }

    // 战斗生态配置（可选，静默跳过）
    final bcResult = await safe_json.loadAssetJson('assets/static/battle_config.json', source: 'battle_config.json');
    if (bcResult.isSuccess) {
      battleConfig = bcResult.data as Map<String, dynamic>;
    } else {
      battleConfig = {};
    }

    // 仙道杀招预设（可选，静默跳过）
    final kmResult = await safe_json.loadAssetJson('assets/static/kill_move.json', source: 'kill_move.json');
    if (kmResult.isSuccess) {
      final kmJson = kmResult.data as Map<String, dynamic>;
      PresetKillerMoveStore.load((kmJson['preset_killer_moves'] as List?) ?? []);
    }
  }

  /// 批量加载：环境配置 time_config.json + weather_config.json（失败时使用默认值）。
  Future<void> loadStaticEnvironment() async {
    Map<String, dynamic>? timeCfg;
    Map<String, dynamic>? weatherCfg;
    final tResult = await safe_json.loadAssetJson('assets/static/time_config.json', source: 'time_config.json');
    if (tResult.isSuccess) timeCfg = tResult.data as Map<String, dynamic>;
    final wResult = await safe_json.loadAssetJson('assets/static/weather_config.json', source: 'weather_config.json');
    if (wResult.isSuccess) weatherCfg = wResult.data as Map<String, dynamic>;
    EnvironmentSystem.init(timeCfg, weatherCfg);
  }

  /// 批量加载：任务系统 quest.json（失败时使用空列表）。
  Future<void> loadStaticQuest() async {
    final qResult = await safe_json.loadAssetJson('assets/static/quest.json', source: 'quest.json');
    if (qResult.isSuccess) {
      final qJson = qResult.data as Map<String, dynamic>;
      QuestSystem.load(qJson['quests'] as List? ?? []);
    } else {
      QuestSystem.load([]);
    }
  }

  /// 批量加载：南疆扩展区域数据（起始区域，启动时加载）。
  Future<void> loadStaticRegion() async {
    await _loadRegionData('nanjiang');
  }

  // -----------------------------------------------------------------------
  // V2.0 内存优化【五域懒加载】
  // -----------------------------------------------------------------------
  // 五域资源按需加载：玩家首次进入某地域时，加载该域的 map/gu/material/npc/event/weather。
  // 已加载的地域标记在 _loadedRegions 中，避免重复加载。
  // 南疆为起始区域，启动时即加载；西漠/北原/东海/中州首次进入时加载。
  // -----------------------------------------------------------------------

  /// 五域配置表：地域名 → 对应 JSON 文件前缀。
  static const Map<String, String> _regionFilePrefix = {
    'nanjiang': 'nanjiang',
    '西漠': 'ximo',
    '北原': 'beiyuan',
    '东海': 'donghai',
    '中州': 'zhongzhou',
  };

  /// 确保指定地域的数据已加载。若未加载则执行懒加载。
  /// [regionKey] 为 _regionFilePrefix 中的 key（nanjiang/西漠/北原/东海/中州）。
  Future<void> ensureRegionLoaded(String regionKey) async {
    if (_loadedRegions.contains(regionKey)) return;
    await _loadRegionData(_regionFilePrefix[regionKey] ?? regionKey);
    _loadedRegions.add(regionKey);
  }

  /// 加载单个地域的全部配套资源（map+gu+material+npc+event+weather）。
  /// 【修复】V3.1 使用 safe_json 异步加载，避免 jsonDecode 阻塞主线程。
  Future<void> _loadRegionData(String prefix) async {
    // 地图房间
    try {
      final j = await safe_json.loadAssetJsonMap('assets/static/map_$prefix.json', source: 'map_$prefix.json');
      final rList = (j['rooms'] as List?)?.map((r) => Room.fromJson(r as Map<String, dynamic>)).toList() ?? [];
      for (final r in rList) {
        rooms.putIfAbsent(r.rid, () => r);
      }
    } catch (_) {}
    // 蛊虫模板
    try {
      final j = await safe_json.loadAssetJsonMap('assets/static/gu_$prefix.json', source: 'gu_$prefix.json');
      for (final g in (j['gu_list'] as List? ?? [])) {
        final t = GuTemplate.fromJson(g as Map<String, dynamic>);
        guList.putIfAbsent(t.gid, () => t);
      }
      combatEngine = CombatEngine(guList);
    } catch (_) {}
    // 材料表
    try {
      final j = await safe_json.loadAssetJsonMap('assets/static/material_$prefix.json', source: 'material_$prefix.json');
      final mats = j['materials'] as Map? ?? {};
      for (final e in mats.entries) {
        materials.putIfAbsent(e.key, () => e.value);
      }
    } catch (_) {}
    // NPC 模板
    try {
      final j = await safe_json.loadAssetJsonMap('assets/static/npc_$prefix.json', source: 'npc_$prefix.json');
      for (final n in (j['npcs'] as List? ?? [])) {
        final t = NpcTemplate.fromJson(n as Map<String, dynamic>);
        if (!npcTemplates.any((e) => e.nid == t.nid)) npcTemplates.add(t);
      }
    } catch (_) {}
    // 随机事件
    try {
      final j = await safe_json.loadAssetJsonMap('assets/static/event_$prefix.json', source: 'event_$prefix.json');
      for (final e in (j['events'] as List? ?? [])) {
        events.add(Map<String, dynamic>.from(e as Map));
      }
    } catch (_) {}
    // 区域天气（仅四域有独立天气配置，南疆用默认 weather_config）
    final regionName = const {
      'ximo': '西漠', 'beiyuan': '北原', 'donghai': '东海', 'zhongzhou': '中州',
    }[prefix];
    if (regionName != null) {
      try {
        final j = await safe_json.loadAssetJsonMap('assets/static/weather_$prefix.json', source: 'weather_$prefix.json');
        EnvironmentSystem.addRegionWeather(regionName, j);
      } catch (_) {}
    }
  }

  /// V2.0 内存优化：根据玩家当前房间 rid 确保对应地域已加载。
  /// 在 doGo/teleport 场景切换时调用。
  Future<void> _ensureRegionForRid(String rid) async {
    final region = EnvironmentSystem.regionOf(rid);
    // 南疆已启动时加载，其余四域按需加载
    if (region == '南疆') return;
    final key = const {
      '西漠': '西漠', '北原': '北原', '东海': '东海', '中州': '中州',
    }[region];
    if (key != null) {
      await ensureRegionLoaded(key);
    }
  }

  // ---------- 输出 ----------
  /// 输出一条游戏日志。超过 maxLogEntries 时自动丢弃最旧记录，防止内存无限增长。
  void out(String text, [MsgType type = MsgType.system]) {
    log.add(Msg(text, type));
    if (log.length > maxLogEntries) {
      log.removeRange(0, log.length - maxLogEntries);
    }
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
      // 【修复】V3.1 异步文件写入，禁止 writeAsStringSync。
      await f.writeAsString(buf.toString());
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
  /// 防御式获取当前房间：若玩家所在地域资源尚未懒加载或未知房间，
  /// 回退至 startRid（青茅山），避免 ! 空断言崩溃。
  /// 修复：读档入南疆外其他地域时 rooms 尚未加载导致的 Crash。
  Room curRoom() {
    final rid = player?.location ?? startRid;
    return rooms[rid] ?? rooms[startRid] ?? rooms.values.first;
  }
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
    // V1.9：使用 SafeSaveManager.safeSaveManual（原子写+备份，防坏档）
    final ok = await sv.SafeSaveManager.instance.safeSaveManual(slot, player!, npcs);
    if (ok) {
      takeSnapshot();
    }
    return ok;
  }

  Future<bool> loadFromSlot(int slot) async {
    final (loaded, npcStates) = await sv.loadGame(slot);
    if (loaded == null) {
      out('该存档位为空或读档失败。', MsgType.danger);
      return false;
    }
    await installLoadedSave(loaded, npcStates);
    return true;
  }

  /// V1.9 新增：安装已加载的存档数据到上下文（玩家+NPC状态+快照+清日志+look）。
  /// 由自动存档加载与手动读档共用。
  /// V2.0：改为 async，读档时确保玩家所在地域资源已懒加载。
  Future<void> installLoadedSave(Player loaded, List<Map<String, dynamic>> npcStates) async {
    player = loaded;
    // V1.9：从读档恢复自动存档开关（player.flags['auto_save_enabled'] → SafeSaveManager）
    sv.SafeSaveManager.instance.autoSaveEnabled = autoSaveEnabled;
    // V2.0 内存优化：确保玩家当前所在地域的数据已加载（读档可能在中州/东海等未加载区域）
    await _ensureRegionForRid(player!.location);
    npcs = spawnNpcs(npcTemplates, rooms);
    for (final st in npcStates) {
      final n = npcs[st['nid']];
      if (n != null) n.fromJson(st);
    }
    takeSnapshot();
    clearLog();
    out('读档成功。', MsgType.fortune);
    doLook();
    notifyListeners();
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
      // 毒发/寿元耗尽/劫数 用 danger（橙）色突出
      final danger = l.contains('劫') || l.contains('耗尽')
          || l.contains('毒发') || l.contains('毒解') || l.contains('暗伤')
          || l.contains('祛毒') || l.contains('逼毒') || l.contains('药到');
      out(l, danger ? MsgType.danger : MsgType.system);
    }
    if (trigger != null) _maybeRandomEvent(trigger);
    // 第三阶段新增【7.2/7.5 环境debuff自动生效】：毒瘴场景持续叠毒素。
    // 当前房间 env_effect 中"毒道"倍率 ≥1.20 视为浓瘴场景，每次行动有概率吸入瘴毒。
    // 纯上层逻辑（command.tick），不改动核心引擎；玉蟾蛊(g022)持有者免疫瘴毒。
    _maybeMiasmaPoison(hours);
    // V1.5 新增【西漠荒漠机制】：流沙沟壑沙陷伤害 + 沙暴天气真元大量消耗。
    //   ① quicksand_zone 房间：无流沙蛊(g_liusha)者持续受沙陷之害（体魄+寿元损耗）。
    //   ② 沙暴天气 + 西漠房间：移动/行动真元大量消耗（御沙护体）。
    //   纯上层逻辑，旧存档无西漠房间时不触发，100%兼容。
    _maybeDesertHazard(hours);
    // V1.6 新增【北原严寒机制】：cold_zone 房间（雪原林地/冻土荒原）无御寒蛊者持续消耗真元；
    //   暴风雪天气 + 北原房间：真元消耗大幅提升，野外高危野怪刷新概率上升。
    //   纯上层逻辑，旧存档无北原房间时不触发，100%兼容。
    _maybeColdHazard(hours);
    // V1.3 新增【昼夜/天气/BOSS环境系统】推进：
    // 1) 天气周期刷新（达到周期按权重刷新区域天气，播报变化）
    // 2) 梅雨天气真元缓慢消耗
    // 3) 副本BOSS重生倒计时判定（倒计时结束且时段/天气满足则复活）
    _tickEnvironment(hours);
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

  /// V1.3 新增【昼夜/天气/BOSS环境系统】推进：天气刷新 + 梅雨真元消耗 + BOSS重生判定。
  /// 纯上层逻辑，所有状态持久化于 player.flags，旧存档无键回退默认值。
  void _tickEnvironment(double hours) {
    final p = player;
    if (p == null || !p.alive) return;
    // 1) 天气周期刷新
    EnvironmentSystem.tickWeather(p, onWeatherChange: (old, neu) {
      out('  【天气变化】$old → $neu，环境效果随之改变。', MsgType.scene);
    });
    // 2) 梅雨天气真元缓慢消耗（每小时 -1 真元）
    if (EnvironmentSystem.weatherDrainsTrueyuan(p)) {
      final drain = hours.round().clamp(1, 999);
      p.trueyuan = (p.trueyuan - drain).clamp(0, p.trueyuanMax);
      // 不逐时播报，仅在被检测到时静默消耗（避免刷屏）
    }
    // 3) 副本BOSS重生判定
    final revived = EnvironmentSystem.tickBossRespawn(p, rooms);
    for (final l in revived) out(l, MsgType.danger);
    // 4) V1.6 新增【自动接取任务】：auto_accept=true 的任务在满足境界条件时自动接取
    //    （如青茅山新手引导『初入青茅山』，玩家进入青茅山域后自动接取，引导寻访茅婶）。
    final autoQuests = QuestSystem.autoAccept(p);
    for (final ql in autoQuests) out(ql, MsgType.fortune);
  }

  /// 第三阶段新增【7.2/7.5 环境debuff】：毒瘴场景持续叠毒素。
  /// 当前房间"毒道"环境倍率 ≥1.20 时，按行动时长累积中毒概率；
  /// 玉蟾蛊(g022)持有者免疫瘴毒。仅上层日志+毒素系统注入，不改核心引擎。
  void _maybeMiasmaPoison(double hours) {
    final p = player;
    if (p == null || !p.alive) return;
    final room = rooms[p.location];
    if (room == null) return;
    final miasmaLvl = room.envEffect['毒道'] ?? 1.0;
    if (miasmaLvl < 1.20) return;
    // 持有玉蟾蛊免疫
    final hasJadeToad = p.guInSlot.any((g) => g.gid == 'g022') ||
        p.guBag.any((g) => g.gid == 'g022');
    if (hasJadeToad) return;
    // 概率随倍率与时长提升：base 0.06/小时 × (倍率-1) × 小时
    final chance = (0.06 * (miasmaLvl - 1) * hours).clamp(0.0, 0.6);
    final rng = DateTime.now().microsecondsSinceEpoch % 10000 / 10000;
    if (rng >= chance) return;
    PoisonSystem.applyPoison(p,
      pid: 'miasma_${room.rid}_${p.worldTime.toInt()}',
      name: '瘴气之毒',
      rank: PoisonRank.minor,
      power: (4 + ((miasmaLvl - 1) * 10).round()),
      tickHours: 12,
      source: '场景瘴气 ${room.name}',
    );
    out('  ⚠ 浓瘴入体，你中毒了：瘴气之毒！', MsgType.danger);
  }

  /// V1.5 新增【西漠荒漠机制】：流沙沟壑沙陷伤害 + 沙暴天气真元消耗。
  /// 纯上层逻辑（command.tick），不改动核心引擎；旧存档无西漠房间时不触发。
  ///   ① quicksand_zone 房间（如流沙沟壑）：无流沙蛊(g_liusha)者持续受沙陷之害，
  ///      体魄大幅损耗、寿元微损；持流沙蛊者免疫。
  ///   ② 沙暴天气 + 西漠房间（rid 以 ximo_ 开头）：行动真元大量消耗（御沙护体），
  ///      持风沙道蛊(g_dust_devil/g_sandstorm_lord)或风行蛊(g_wind_walk)者减免。
  void _maybeDesertHazard(double hours) {
    final p = player;
    if (p == null || !p.alive) return;
    final room = rooms[p.location];
    if (room == null) return;
    final inXimo = p.location.startsWith('ximo_');
    // ① 流沙沟壑沙陷伤害
    if (room.secret == 'quicksand_zone') {
      final hasLiusha = p.guInSlot.any((g) => g.gid == 'g_liusha') ||
          p.guBag.any((g) => g.gid == 'g_liusha');
      if (!hasLiusha) {
        final dmg = (5 * hours).round().clamp(1, 999);
        p.physique = (p.physique - dmg).clamp(0, 99999);
        if (hours >= 1) {
          p.lifeLeft = (p.lifeLeft - 0.1 * hours).clamp(0.0, p.lifeMax);
        }
        out('  【流沙吞噬】你未持流沙蛊，脚下流沙汹涌吞噬，体魄 -$dmg${hours >= 1 ? '、寿元微损' : ''}！速离此地或炼制流沙蛊！', MsgType.danger);
      }
    }
    // ② 沙暴天气真元消耗（仅西漠房间）
    if (inXimo && EnvironmentSystem.curWeather(p) == '沙暴') {
      // 持风沙道/风行蛊者减免消耗
      final hasSandGuard = p.guInSlot.any((g) =>
          g.gid == 'g_dust_devil' || g.gid == 'g_sandstorm_lord' || g.gid == 'g_wind_walk') ||
          p.guBag.any((g) =>
              g.gid == 'g_dust_devil' || g.gid == 'g_sandstorm_lord' || g.gid == 'g_wind_walk');
      final raw = (4 * hours).round().clamp(1, 999);
      final drain = hasSandGuard ? (raw / 2).round() : raw;
      p.trueyuan = (p.trueyuan - drain).clamp(0, p.trueyuanMax);
      out('  【沙暴肆虐】漫天黄沙遮天蔽日，真元 -$drain 用于护体御沙${hasSandGuard ? '（风沙道蛊减免）' : ''}。', MsgType.danger);
    }
  }

  /// V1.6 新增【北原严寒机制】：cold_zone 房间严寒真元消耗 + 暴风雪天气真元大量消耗。
  /// 纯上层逻辑（command.tick），不改动核心引擎；旧存档无北原房间时不触发。
  ///   ① cold_zone 房间（如雪原林地/冻土荒原）：无御寒蛊者持续受严寒侵蚀，
  ///      真元缓慢消耗、体魄微损；持御寒蛊(g_hanyue/g_xuedun)者免疫。
  ///   ② 暴风雪天气 + 北原房间（rid 以 beiyuan_ 开头）：行动真元大量消耗（御寒护体），
  ///      持御寒蛊(g_hanyue/g_xuedun)者减免；野外高危野怪刷新概率上升（环境增益播报）。
  void _maybeColdHazard(double hours) {
    final p = player;
    if (p == null || !p.alive) return;
    final room = rooms[p.location];
    if (room == null) return;
    final inBeiyuan = p.location.startsWith('beiyuan_');
    // 御寒蛊判定：寒月蛊(g_hanyue) / 雪遁蛊(g_xuedun) 标记 is_anti_cold
    bool hasAntiCold() => p.guInSlot.any((g) =>
            g.gid == 'g_hanyue' || g.gid == 'g_xuedun') ||
        p.guBag.any((g) =>
            g.gid == 'g_hanyue' || g.gid == 'g_xuedun');
    // ① cold_zone 严寒侵蚀（雪原林地/冻土荒原）
    if (room.secret == 'cold_zone') {
      if (!hasAntiCold()) {
        final drain = (3 * hours).round().clamp(1, 999);
        final dmg = (2 * hours).round().clamp(1, 999);
        p.trueyuan = (p.trueyuan - drain).clamp(0, p.trueyuanMax);
        p.physique = (p.physique - dmg).clamp(0, 99999);
        out('  【严寒侵蚀】你未持御寒蛊，刺骨寒气侵体，真元 -$drain、体魄 -$dmg！速离此地或炼制御寒蛊！', MsgType.danger);
      }
    }
    // ② 暴风雪天气真元大量消耗（仅北原房间）
    if (inBeiyuan && EnvironmentSystem.curWeather(p) == '暴风雪') {
      final raw = (5 * hours).round().clamp(1, 999);
      final drain = hasAntiCold() ? (raw / 2).round() : raw;
      p.trueyuan = (p.trueyuan - drain).clamp(0, p.trueyuanMax);
      out('  【暴风雪肆虐】白毛风呼啸肆虐，真元 -$drain 用于护体御寒${hasAntiCold() ? '（御寒蛊减免）' : ''}，野外高危野怪活跃度上升。', MsgType.danger);
    }
  }

  void _maybeRandomEvent(String trigger) {
    final baseChance = eventTriggerChance[trigger] ?? 0.1;
    final p = player!;
    // 第三阶段新增【11.4 气运联动】：气运越高，事件触发概率略增（每点气运 +0.5%），低负气运略降。
    // 匹配底层气运系统预留接口，区间 [0.5×base, 1.5×base] 内浮动，避免极端。
    final luckFactor = (1 + (p.luck * 0.005)).clamp(0.5, 1.5);
    final chance = (baseChance * luckFactor).clamp(0.02, 0.95);
    final rng = DateTime.now().microsecondsSinceEpoch % 10000 / 10000;
    if (rng >= chance) return;
    final rank = levelRank(p.level);
    final curRid = p.location;
    // V1.6 新增【场景专属事件过滤】：事件含 scene_rids 字段时，仅当前房间 rid 命中方可触发；
    // 缺失 scene_rids 的事件保持全局通用（旧 JSON 兼容）。
    final pool = events
        .where((e) {
          if (e['trigger'] != trigger) return false;
          // 防御：缺失 min_rank/max_rank 或类型非 num 时，按 0/999 默认值兼容；
          // 避免 JSON 中为 double（如 1.0）或缺失导致 as int 抛 CastError。
          final minR = (e['min_rank'] as num?)?.toInt() ?? 0;
          final maxR = (e['max_rank'] as num?)?.toInt() ?? 999;
          return minR <= rank && maxR >= rank;
        })
        .where((e) {
          final sr = e['scene_rids'];
          if (sr is! List || sr.isEmpty) return true;
          return sr.contains(curRid);
        })
        .toList();
    if (pool.isEmpty) return;
    // 第三阶段新增【11.1 权重判定】：按 weight 字段做加权随机抽取（缺失 weight 默认 1）。
    // 同时【11.4 气运联动分支概率】：机缘类(type=fortune)权重随气运提升，劫难类(type=disaster)权重随气运降低。
    double totalW = 0;
    final weights = <double>[];
    for (final e in pool) {
      final baseW = ((e['weight'] as num?) ?? 1).toDouble();
      final isFortune = e['type'] == 'fortune';
      final isDisaster = e['type'] == 'disaster';
      // 气运影响：每点气运让机缘 +3%、劫难 -2%（劫难下限 0.2 防止完全消失）
      double w = baseW;
      if (isFortune) w *= (1 + p.luck * 0.03);
      if (isDisaster) w *= (1 - p.luck * 0.02).clamp(0.2, 1.5);
      weights.add(w);
      totalW += w;
    }
    final pick = (DateTime.now().microsecondsSinceEpoch % 100000 / 100000) * totalW;
    double acc = 0;
    int idx = 0;
    for (var i = 0; i < weights.length; i++) {
      acc += weights[i];
      if (pick <= acc) { idx = i; break; }
    }
    final ev = pool[idx];
    _applyEvent(ev);
  }

  void _applyEvent(Map<String, dynamic> ev) {
    final isFortune = ev['type'] == 'fortune';
    out('【${ev['name']}】${ev['desc']}', isFortune ? MsgType.fortune : MsgType.danger);
    // 第三阶段新增【11.2/11.3 抉择事件】：含 choices 数组的事件不自动结算，
    // 挂起到 pendingEvent，由 UI 弹出抉择弹窗，玩家选择后调用 resolveEventChoice。
    final choices = ev['choices'];
    if (choices is List && choices.isNotEmpty) {
      pendingEvent = ev;
      notifyListeners();
      return;
    }
    final eff = ev['effect'] as Map<String, dynamic>?;
    if (eff == null) return;
    _applyEventEffect(ev, eff);
  }

  /// 结算一个事件效果 Map（供 _applyEvent 与 resolveEventChoice 复用）。
  void _applyEventEffect(Map<String, dynamic> ev, Map<String, dynamic> eff) {
    final p = player!;
    // 第三阶段新增【11.3】：抉择购买类选项 add_item_cost（先扣代价，再发放 add_item）
    if (eff['add_item_cost'] != null) {
      for (final it in eff['add_item_cost']) {
        final (n, c) = MatParser.parse(it);
        if (gu.hasMaterial(p, n, c)) {
          gu.consumeMaterial(p, n, c);
        } else {
          out('  $n 不足（需 $c），该物品无法获得。', MsgType.danger);
        }
      }
    }
    if (eff['add_item'] != null) {
      for (final it in eff['add_item']) {
        final (n, c) = MatParser.parse(it);
        // 兼容负数数量（如"原石x-5"表示支付）：负数走消耗流程，避免 addMaterial 早退。
        if (c < 0) {
          gu.consumeMaterial(p, n, -c);
          out('  支付 $n×${-c}', MsgType.system);
        } else {
          gu.addMaterial(p, n, c);
        }
      }
    }
    // 防御：JSON 数值可能为 int 或 double，统一用 num?.toInt()/toDouble() 兼容，
    // 避免 as int 抛 CastError 导致事件结算崩溃。
    if (eff['trueyuan'] != null) {
      final v = (eff['trueyuan'] as num?)?.toInt() ?? 0;
      p.recoverTrueyuan(v);
    }
    if (eff['physique'] != null) {
      final v = (eff['physique'] as num?)?.toInt() ?? 0;
      p.physique = (p.physique + v).clamp(1, 9999).toInt();
    }
    if (eff['soul_power'] != null) {
      final v = (eff['soul_power'] as num?)?.toInt() ?? 0;
      p.soulPower = (p.soulPower + v).clamp(1, 9999).toInt();
    }
    if (eff['life_left'] != null) {
      final v = (eff['life_left'] as num?)?.toDouble() ?? 0;
      p.lifeLeft = dmax(0, p.lifeLeft + v);
    }
    if (eff['luck'] != null) {
      // 防御：JSON 中 luck 可能为 double（如 5.0），用 num?.toInt() 兼容；
      // 避免 as int 抛 CastError 导致随机事件结算崩溃。
      final delta = (eff['luck'] as num?)?.toInt() ?? 0;
      p.luck = imax(0, p.luck + delta);
    }
    if (eff['injure'] != null) {
      final inj = eff['injure'] as String;
      p.addInjure(inj);
      // 联动【毒素中毒系统】：若事件添加 '毒伤'，同时注入一层轻微毒素。
      if (inj == '毒伤' && !PoisonStore.hasAny(p)) {
        PoisonSystem.applyPoison(p,
          pid: 'event_${ev['eid']}_poison',
          name: '瘴气之毒',
          rank: PoisonRank.minor,
          power: 4,
          tickHours: 12,
          source: '随机事件 ${ev['name']}',
        );
      }
    }
    // 接入【毒素中毒系统】：effect.poison 字段直接注入毒素。
    if (eff['poison'] != null) {
      final pj = eff['poison'] as Map<String, dynamic>;
      PoisonSystem.applyPoison(p,
        pid: pj['pid'] ?? 'event_${ev['eid']}_poison',
        name: pj['name'] ?? '瘴气之毒',
        rank: PoisonRank.fromName(pj['rank'] as String?),
        power: (pj['power'] as num? ?? 5).toInt(),
        tickHours: (pj['tick_hours'] as num? ?? 12).toInt(),
        durationHours: (pj['duration_hours'] as num?)?.toDouble(),
        source: '随机事件 ${ev['name']}',
      );
      out('  ⚠ 你中毒了：${pj['name'] ?? '瘴气之毒'}！', MsgType.danger);
    }
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

  /// 第三阶段新增【11.2/11.3 抉择事件结算】：UI 抉择弹窗回调。
  /// 玩家点击某个选项后调用，应用对应 choice 的 effect，并清空 pendingEvent。
  /// 越界索引视为放弃（仅清空挂起，不再结算）。
  void resolveEventChoice(int idx) {
    final ev = pendingEvent;
    if (ev == null) return;
    final choices = ev['choices'];
    if (choices is! List || idx < 0 || idx >= choices.length) {
      pendingEvent = null;
      notifyListeners();
      return;
    }
    final choice = Map<String, dynamic>.from(choices[idx] as Map);
    out('▶ 你选择：${choice['text']}', MsgType.system);
    final eff = choice['effect'] as Map<String, dynamic>?;
    if (eff != null) _applyEventEffect(ev, eff);
    pendingEvent = null;
    notifyListeners();
  }

  /// 放弃当前抉择事件（UI 关闭弹窗不选时调用），仅清空挂起状态。
  void dismissPendingEvent() {
    if (pendingEvent == null) return;
    pendingEvent = null;
    notifyListeners();
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
      case 'go': case 'g': unawaited(doGo(args)); break;
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
      // 接入【毒素中毒系统】解毒指令
      case 'herb': case '服草药': case '解毒草药': doConsumeHerb(args); break;
      case 'burnlife': case '燃烧寿元': case '逼毒': doBurnLife(args); break;
      case 'poisonattack': case '以毒攻毒': doPoisonAttack(args); break;
      case 'detox': case '祛毒': case '解毒': doDetoxHelp(); break;
      // 第二阶段新增指令
      case 'eat': case '进食': case '吃': doEat(args); break;
      case 'km': case 'killermove': case '杀招': doKillerMove(args); break;
      case 'kmnew': case '新杀招': doKillerMoveNew(args); break;
      case 'kmdel': case '删除杀招': doKillerMoveDel(args); break;
      case 'pkm': case '仙道杀招': doPresetKillerMove(args); break;
      case 'reputation': case '声望': doReputation(); break;
      case 'bounty': case '悬赏榜': doBountyList(); break;
      case 'bountyaccept': case '接悬赏': doBountyAccept(args); break;
      case 'bountysubmit': case '交悬赏': doBountySubmit(args); break;
      case 'barter': case '以物易物': case '易物': doBarter(args); break;
      case 'storage': case '背包容量': case '储物资': doStorageInfo(); break;
      case 'slotinfo': case '空窍信息': doSlotInfo(); break;
      case 'blackmarket': case '黑市': doBlackMarket(); break;
      // V1.4 新增【任务系统】指令：任务列表/接取/交付
      case 'quest': case '任务': doQuest(args); break;
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
    final p = player!;
    // V1.3 新增【昼夜/天气状态展示】：场景头部展示当前时段+天气，场景描述跟随昼夜动态变化。
    final phase = EnvironmentSystem.curPhase(p);
    final weather = EnvironmentSystem.curWeather(p);
    out('【${r.name}】　第${EnvironmentSystem.gameDay(p)}天 · ${phase.phase} · $weather', MsgType.scene);
    out(r.description, MsgType.scene);
    if (phase.desc.isNotEmpty) {
      out('  〔${phase.phase}·$weather〕${phase.desc}', MsgType.system);
    }
    if (r.envEffect.isNotEmpty) {
      out('  天地二气：${r.envEffect.entries.map((e) => '${e.key}${e.value.toStringAsFixed(2)}倍').join('、')}', MsgType.system);
    }
    // V1.3 新增【时段/天气环境增益播报】
    final phaseBuff = phase.buff;
    final wBuff = EnvironmentSystem.weatherBuff(p);
    if (phaseBuff.isNotEmpty || wBuff.isNotEmpty) {
      final parts = <String>[];
      for (final e in phaseBuff.entries) parts.add('${e.key}×${e.value.toStringAsFixed(2)}');
      for (final e in wBuff.entries) parts.add('${e.key}×${e.value.toStringAsFixed(2)}');
      if (parts.isNotEmpty) out('  环境增益：${parts.join("、")}', MsgType.system);
    }
    if (r.exits.isNotEmpty) {
      const dirs = {'north': '北', 'south': '南', 'east': '东', 'west': '西'};
      out('  出口：${r.exits.keys.map((d) => dirs[d] ?? d).join('、')}', MsgType.system);
    }
    if (r.wildGu.isNotEmpty) {
      out('  野生蛊虫：${r.wildGu.map((g) => guList[g]?.name ?? g).join(', ')}', MsgType.gu);
    }
    // V1.3 新增【副本BOSS状态播报】：副本房间展示BOSS存活/复苏倒计时
    if (r.bossInfo.isNotEmpty) {
      final prompt = EnvironmentSystem.bossEnterPrompt(p, r.rid, r.bossInfo);
      if (prompt != null) {
        out('  ⚑ 首领：${r.bossInfo['boss_name'] ?? '未知'} —— $prompt', MsgType.danger);
      } else {
        out('  ⚑ 首领：${r.bossInfo['boss_name'] ?? '未知'}（存活）盘踞此地，警惕！', MsgType.danger);
      }
    }
    for (final n in npcsInCurRoom()) {
      // V1.3 新增：副本BOSS房间中已死亡BOSS不在场景NPC列表中显示
      // V1.6 加固：limit_daytime/limit_weather 条件不满足时 BOSS 未现身，同样不在场景列表显示
      //           （如寒雾蛇王仅夜晚+浓雾现身，白日入窟只见空窟）
      if (r.bossInfo.isNotEmpty && r.bossInfo['npc_id'] == n.nid &&
          !EnvironmentSystem.isBossPresent(p, r.rid, r.bossInfo)) {
        continue;
      }
      final tag = n.isHostile ? '[敌对]' : (n.isMerchant ? '[商人]' : '[NPC]');
      out('  $tag ${n.name}（${n.level}）', n.isHostile ? MsgType.danger : MsgType.fortune);
    }
  }

  Future<void> doGo(List<String> args) async {
    if (args.isEmpty) { out('用法：go north/south/east/west', MsgType.danger); return; }
    const alias = {'n': 'north', 's': 'south', 'e': 'east', 'w': 'west',
      '北': 'north', '南': 'south', '东': 'east', '西': 'west'};
    final d = alias[args[0].toLowerCase()] ?? args[0].toLowerCase();
    final r = curRoom();
    if (!r.exits.containsKey(d)) { out('那个方向没有出路。', MsgType.danger); return; }
    final targetRid = r.exits[d]!;
    // V1.3 新增【场景传送防穿墙】：仅允许经由当前房间 exits 中的出口传送（已由 containsKey 校验）。
    // 双重校验：目标房间必须真实存在于 rooms，且不能通过伪造指令直接传送至任意 rid。
    final target = rooms[targetRid];
    if (target == null) {
      out('前方道路断裂，无法通行（目标场景不存在）。', MsgType.danger);
      return;
    }
    // 第三阶段新增【14.域外通道伏笔】：识别 border_ 前缀的域外通道，封锁跨域通行
    // V1.5 改造：西漠通道（border_west_pass）满足条件可解锁通行；其余 border_ 持续封锁。
    // V1.6 改造：北原通道（border_north_pass）满足条件可解锁通行；东海/中州持续封锁。
    // V1.9 改造：五地全部开放——东海通道(border_east_pass)、中州通道(border_center_pass)
    //   满足条件可解锁通行；仅余太古遗迹域外通道持续封锁（主线伏笔，不开放）。
    if (targetRid.startsWith('border_')) {
      if (targetRid == 'border_west_pass') {
        // 【南疆→西漠】通道解锁判定：需完成南疆主线（xisha_unlock_ready）且修为≥5转
        final unlocked = (player!.flags['xisha_unlocked'] as num?)?.toInt() ?? 0;
        final ready = (player!.flags['xisha_unlock_ready'] as num?)?.toInt() ?? 0;
        final rank = levelRank(player!.level);
        if (unlocked > 0) {
          // 已解锁，自由通行（关口房间，连接南疆与西漠）
        } else if (ready > 0 && rank >= 5) {
          player!.flags['xisha_unlocked'] = 1;
          out('【禁制破除】你催动风行蛊御风沙、沙遁蛊穿沙海，双蛊合一，西漠通道的千年禁制轰然崩裂！', MsgType.fortune);
          out('  黄沙漫天扑面而来——西漠，已为你敞开。', MsgType.scene);
        } else {
          out('【域外古道·禁制封锁】前方通往 ${target.name} 的通道被一道上古禁制封锁，符文隐现。', MsgType.danger);
          if (ready == 0) {
            out('  （需完成南疆主线『西漠之钥』集齐风行蛊与沙遁蛊方可破禁）', MsgType.system);
          } else if (rank < 5) {
            out('  （禁制反噬剧烈，需五转以上修为方可承受破禁之力，当前 $rank 转）', MsgType.system);
          }
          return;
        }
      } else if (targetRid == 'border_north_pass') {
        // 【南疆→北原】通道解锁判定：需已解锁西漠（xisha_unlocked）且修为≥5转
        //   设计依据：南疆→西漠→北原 自然递进；北原环境更险恶，需御寒蛊方可深入。
        final unlocked = (player!.flags['beiyuan_unlocked'] as num?)?.toInt() ?? 0;
        final xishaDone = (player!.flags['xisha_unlocked'] as num?)?.toInt() ?? 0;
        final rank = levelRank(player!.level);
        if (unlocked > 0) {
          // 已解锁，自由通行（关口房间，连接南疆与北原）
        } else if (xishaDone > 0 && rank >= 5) {
          player!.flags['beiyuan_unlocked'] = 1;
          out('【禁制破除】你以五转修为强催玄冰禁制，寒霜符文寸寸崩裂，北原通道的千年禁制轰然洞开！', MsgType.fortune);
          out('  朔风裹挟碎雪扑面而来——北原，已为你敞开。', MsgType.scene);
        } else {
          out('【域外古道·禁制封锁】前方通往 ${target.name} 的通道被一道寒冰禁制封锁，符文隐现。', MsgType.danger);
          if (xishaDone == 0) {
            out('  （需先解锁西漠通道，方可循迹破除北原禁制）', MsgType.system);
          } else if (rank < 5) {
            out('  （禁制反噬剧烈，需五转以上修为方可承受破禁之力，当前 $rank 转）', MsgType.system);
          }
          return;
        }
      } else if (targetRid == 'border_east_pass') {
        // V1.9【南疆→东海】通道解锁判定：需修为≥5转（与西漠/北原同阶，五地全面开放）
        //   设计依据：东海滨海，水道蛊气充沛，需五转修为方可抵御海妖暗流。
        final unlocked = (player!.flags['donghai_unlocked'] as num?)?.toInt() ?? 0;
        final rank = levelRank(player!.level);
        if (unlocked > 0) {
          // 已解锁，自由通行（关口房间，连接南疆与东海）
        } else if (rank >= 5) {
          player!.flags['donghai_unlocked'] = 1;
          out('【禁制破除】你以五转修为强催水道真元，咸湿水幕符文寸寸崩裂，东海通道的千年禁制轰然洞开！', MsgType.fortune);
          out('  咸湿海风裹挟浪花扑面而来——东海，已为你敞开。', MsgType.scene);
        } else {
          out('【域外古道·禁制封锁】前方通往 ${target.name} 的通道被一道水幕禁制封锁，符文隐现。', MsgType.danger);
          out('  （禁制反噬剧烈，需五转以上修为方可承受破禁之力，当前 $rank 转）', MsgType.system);
          return;
        }
      } else if (targetRid == 'border_center_pass') {
        // V1.9【南疆→中州】通道解锁判定：需修为≥5转（与西漠/北原同阶，五地全面开放）
        //   设计依据：中州官道通达中原，需五转修为方可破除古道禁制。
        final unlocked = (player!.flags['zhongzhou_unlocked'] as num?)?.toInt() ?? 0;
        final rank = levelRank(player!.level);
        if (unlocked > 0) {
          // 已解锁，自由通行（关口房间，连接南疆与中州）
        } else if (rank >= 5) {
          player!.flags['zhongzhou_unlocked'] = 1;
          out('【禁制破除】你以五转修为强催气道真元，青石官道禁制符文寸寸崩裂，中州通道的千年禁制轰然洞开！', MsgType.fortune);
          out('  中原麦浪的清香扑面而来——中州，已为你敞开。', MsgType.scene);
        } else {
          out('【域外古道·禁制封锁】前方通往 ${target.name} 的通道被一道石碑禁制封锁，符文隐现。', MsgType.danger);
          out('  （禁制反噬剧烈，需五转以上修为方可承受破禁之力，当前 $rank 转）', MsgType.system);
          return;
        }
      } else {
        // 其余 border_ 通道持续锁定（太古遗迹域外通道，主线伏笔，版本未开放）
        out('【域外古道·禁制封锁】前方通往 ${target.name} 的通道被一道上古禁制封锁，符文隐现，似在诉说着昔日纷争。', MsgType.danger);
        out('  （版本未开放，域外通道暂不可通行）', MsgType.system);
        return;
      }
    }
    // V1.3 新增【环境联动·秘境时段限制】：night_only 前缀场景仅夜晚开启（如夜市黑市入口）
    if (target.secret == 'night_only' && !EnvironmentSystem.isNight(player!)) {
      out('【禁制】${target.name} 白日里只是一堵残墙，门户未现——传闻唯有夜幕降临，黑市入口方会浮现。', MsgType.danger);
      return;
    }
    // 第三阶段新增【7.隐藏秘境判定】：need_gu_ 前缀秘境需持有指定蛊虫方可进入
    if (target.secret.startsWith('need_gu_')) {
      final needGid = target.secret.substring('need_gu_'.length);
      final hasGu = player!.guInSlot.any((g) => g.gid == needGid) ||
          player!.guBag.any((g) => g.gid == needGid);
      final guName = guList[needGid]?.name ?? needGid;
      if (!hasGu) {
        out('【秘境禁制】前方通往「${target.name}」的入口被一道毒瘴禁制封锁，需持有 $guName 方可踏入。', MsgType.danger);
        return;
      }
      out('你以 $guName 护体，毒瘴避让，踏入「${target.name}」。', MsgType.fortune);
    }
    // V2.0 内存优化：跨域移动时懒加载目标地域资源
    await _ensureRegionForRid(targetRid);
    player!.location = targetRid;
    tick(actionHours['move']!, trigger: 'move');
    doLook();
    // V1.9：①场景切换后自动存档
    unawaited(_triggerAutoSave('scene_change'));
  }

  /// V1.9 新增【大地图传送】（与步行探索双模式共存）。
  /// 设计约束：
  ///   ① 不改动 doGo 步行逻辑与边境解锁判定，传送独立校验；
  ///   ② 仅允许传送到已解锁大区内的非秘境/非关口场景；
  ///   ③ 秘境（need_gu_）即使地图可见也不可传送进入，必须步行持蛊进入（原版规则不变）；
  ///   ④ 传送消耗真元 + 冷却（存于 player.flags['teleport_cd']，持久化，重启不重置）；
  ///   ⑤ 目标场景必须真实存在于 rooms，杜绝伪造 rid 传送。
  /// 返回：true=传送成功，false=失败（已通过 out 输出原因）。
  Future<bool> teleportTo(String targetRid) async {
    if (player == null || gameOver) return false;
    if (inCombat || inTribulation) {
      out('【传送受限】战斗/渡劫中无法传送。', MsgType.danger);
      return false;
    }
    final target = rooms[targetRid];
    if (target == null) {
      out('【传送失败】目标场景不存在。', MsgType.danger);
      return false;
    }
    // 禁止传送至域外关口（border_）与太古遗迹/逆流河
    if (targetRid.startsWith('border_') ||
        targetRid.contains('taigu') || targetRid.contains('niliu') ||
        target.name.contains('太古') || target.name.contains('逆流')) {
      out('【传送受限】域外关口与终极秘地无法直接传送抵达。', MsgType.danger);
      return false;
    }
    // 禁止传送至秘境（need_gu_ / night_only）——必须步行持蛊/按时段进入
    if (target.secret.startsWith('need_gu_')) {
      final needGid = target.secret.substring('need_gu_'.length);
      final guName = guList[needGid]?.name ?? needGid;
      out('【秘境禁制】${target.name} 乃隐秘之地，须步行抵达并持 $guName 方可进入，无法直接传送。', MsgType.danger);
      return false;
    }
    if (target.secret == 'night_only') {
      out('【传送受限】${target.name} 仅夜间开启，须步行按时段前往。', MsgType.danger);
      return false;
    }
    // 大区解锁校验：目标 rid 所属大区必须已解锁
    final region = EnvironmentSystem.regionOf(targetRid);
    if (!_isRegionUnlocked(region)) {
      out('【区域锁定】$region 尚未贯通，需达成更高修为、推进主线剧情后方可通行。', MsgType.danger);
      return false;
    }
    // 当前位置校验
    if (player!.location == targetRid) {
      out('你已在此地。', MsgType.system);
      return false;
    }
    // 冷却校验（游戏分钟，持久化）
    final lastTp = (player!.flags['teleport_cd'] as num?)?.toInt() ?? 0;
    final nowMin = (player!.worldTime * 60).toInt();
    const cdMin = 30; // 30 游戏分钟冷却
    final left = cdMin - (nowMin - lastTp);
    if (lastTp > 0 && left > 0) {
      out('【传送冷却】大地图传送冷却中，剩余 $left 分钟（游戏时间）。', MsgType.system);
      return false;
    }
    // 真元消耗（按目标区域危险度递增）
    final cost = _teleportCost(region);
    if (player!.trueyuan < cost) {
      out('【真元不足】传送需消耗 $cost 真元（当前 ${player!.trueyuan}），无法传送。', MsgType.danger);
      return false;
    }
    // 执行传送
    player!.spendTrueyuan(cost);
    player!.flags['teleport_cd'] = nowMin;
    out('【大地图传送】你催动真元，破空而至「${target.name}」，消耗真元 $cost。', MsgType.fortune);
    // V2.0 内存优化：跨域传送时懒加载目标地域资源
    await _ensureRegionForRid(targetRid);
    player!.location = targetRid;
    tick((actionHours['move']! ~/ 2).toDouble(), trigger: 'move'); // 传送耗时减半
    doLook();
    notifyListeners();
    // V1.9：传送=场景切换，自动存档
    unawaited(_triggerAutoSave('scene_change'));
    return true;
  }

  /// 判断大区是否已解锁（复用 doGo 的 border_ 解锁条件，保持双模式规则一致）。
  bool _isRegionUnlocked(String region) {
    if (region == '南疆') return true; // 起始区域
    if (region == '西漠') return (player!.flags['xisha_unlocked'] as num?)?.toInt() != 0;
    if (region == '北原') return (player!.flags['beiyuan_unlocked'] as num?)?.toInt() != 0;
    if (region == '东海') return (player!.flags['donghai_unlocked'] as num?)?.toInt() != 0;
    if (region == '中州') return (player!.flags['zhongzhou_unlocked'] as num?)?.toInt() != 0;
    return false; // 太古遗迹/逆流河等未知区域永久锁定
  }

  /// 传送真元消耗（按区域危险度）。
  int _teleportCost(String region) {
    switch (region) {
      case '南疆': return 20;
      case '西漠': return 28;
      case '北原': return 32;
      case '东海': return 32;
      case '中州': return 35;
      default: return 50;
    }
  }

  /// 大地图传送剩余冷却分钟（供 UI 展示）。
  int teleportCooldownLeft() {
    if (player == null) return 0;
    final lastTp = (player!.flags['teleport_cd'] as num?)?.toInt() ?? 0;
    if (lastTp <= 0) return 0;
    final nowMin = (player!.worldTime * 60).toInt();
    const cdMin = 30;
    final left = cdMin - (nowMin - lastTp);
    return left > 0 ? left : 0;
  }

  /// 判断场景是否对玩家可见（秘境需持蛊方可见，用于大地图展示）。
  bool isRoomVisibleOnMap(Room room) {
    if (room.secret.startsWith('need_gu_')) {
      final needGid = room.secret.substring('need_gu_'.length);
      return player!.guInSlot.any((g) => g.gid == needGid) ||
          player!.guBag.any((g) => g.gid == needGid);
    }
    return true;
  }

  /// 供 UI 调用：根据 rid 返回所属大区名（包装 EnvironmentSystem.regionOf）。
  String regionOf(String rid) => EnvironmentSystem.regionOf(rid);

  /// 供 UI 调用：根据大区名返回传送真元消耗（包装 _teleportCost）。
  int teleportCostOf(String region) => _teleportCost(region);

  void doMap() {
    // V1.5 改造【世界地图】：按区域分组展示南疆、西漠两大区域，当前位置高亮。
    // V1.6 改造：新增北原区域，展示南疆+西漠+北原三大区域。
    // V1.9 改造：五地全面开放——新增东海、中州区域，展示南疆+西漠+北原+东海+中州五大区域。
    //   依据 rid 前缀判定区域：ximo_ → 西漠，beiyuan_ → 北原，donghai_ → 东海，
    //   zhongzhou_ → 中州，其余 → 南疆；border_ 为域外古道关口。
    //   域外通道中西漠/北原/东海/中州通道均可解锁，仅太古遗迹域外通道持续封锁。
    final nanjiang = <MapEntry<String, Room>>[];
    final ximo = <MapEntry<String, Room>>[];
    final beiyuan = <MapEntry<String, Room>>[];
    final donghai = <MapEntry<String, Room>>[];
    final zhongzhou = <MapEntry<String, Room>>[];
    for (final entry in rooms.entries) {
      if (entry.key.startsWith('ximo_')) {
        ximo.add(entry);
      } else if (entry.key.startsWith('beiyuan_')) {
        beiyuan.add(entry);
      } else if (entry.key.startsWith('donghai_')) {
        donghai.add(entry);
      } else if (entry.key.startsWith('zhongzhou_')) {
        zhongzhou.add(entry);
      } else {
        nanjiang.add(entry);
      }
    }
    out('═══ 世界地图 ═══', MsgType.scene);
    out('【南疆·区域地图】', MsgType.scene);
    for (final entry in nanjiang) {
      final mark = entry.key == player!.location ? '◀你在此' : '';
      final isBorder = entry.key.startsWith('border_');
      final isWestPass = entry.key == 'border_west_pass';
      final isNorthPass = entry.key == 'border_north_pass';
      final isEastPass = entry.key == 'border_east_pass';
      final isCenterPass = entry.key == 'border_center_pass';
      final passName = isWestPass
          ? '西漠'
          : (isNorthPass
              ? '北原'
              : (isEastPass ? '东海' : (isCenterPass ? '中州' : '')));
      final borderTag = isBorder
          ? (passName.isNotEmpty
              ? ' [${passName}边境通道·可解锁]'
              : ' [域外古道·禁制封锁]')
          : '';
      out('  [${entry.key}] ${entry.value.name}$borderTag $mark',
          isBorder && passName.isEmpty ? MsgType.danger : MsgType.system);
    }
    if (ximo.isNotEmpty) {
      out('【西漠·区域地图】', MsgType.scene);
      for (final entry in ximo) {
        final mark = entry.key == player!.location ? '◀你在此' : '';
        final isSecret = entry.value.secret.startsWith('need_gu_');
        final secretTag = isSecret ? ' [秘境·需钥匙蛊]' : '';
        out('  [${entry.key}] ${entry.value.name}$secretTag $mark',
            isSecret ? MsgType.fortune : MsgType.system);
      }
    }
    if (beiyuan.isNotEmpty) {
      out('【北原·区域地图】', MsgType.scene);
      for (final entry in beiyuan) {
        final mark = entry.key == player!.location ? '◀你在此' : '';
        final isSecret = entry.value.secret.startsWith('need_gu_');
        final secretTag = isSecret ? ' [秘境·需钥匙蛊]' : '';
        out('  [${entry.key}] ${entry.value.name}$secretTag $mark',
            isSecret ? MsgType.fortune : MsgType.system);
      }
    }
    if (donghai.isNotEmpty) {
      out('【东海·区域地图】', MsgType.scene);
      for (final entry in donghai) {
        final mark = entry.key == player!.location ? '◀你在此' : '';
        final isSecret = entry.value.secret.startsWith('need_gu_');
        final secretTag = isSecret ? ' [秘境·需钥匙蛊]' : '';
        out('  [${entry.key}] ${entry.value.name}$secretTag $mark',
            isSecret ? MsgType.fortune : MsgType.system);
      }
    }
    if (zhongzhou.isNotEmpty) {
      out('【中州·区域地图】', MsgType.scene);
      for (final entry in zhongzhou) {
        final mark = entry.key == player!.location ? '◀你在此' : '';
        final isSecret = entry.value.secret.startsWith('need_gu_');
        final secretTag = isSecret ? ' [秘境·需钥匙蛊]' : '';
        out('  [${entry.key}] ${entry.value.name}$secretTag $mark',
            isSecret ? MsgType.fortune : MsgType.system);
      }
    }
  }

  void doStatus() {
    final p = player!;
    out('═══ 角色状态 ═══', MsgType.fortune);
    out('  姓名：${p.name}　称号：${p.title.isEmpty ? '无' : p.title}　阵营：${p.align}', MsgType.system);
    out('  境界：${p.level}（${levelRank(p.level)}转）', MsgType.system);
    // 第二阶段：空窍容量显示（启用严格模式才显式展示）
    if (SlotCapacity.strictMode(p)) {
      final overload = SlotCapacity.isOverloaded(p);
      out('  蛊槽：${p.guInSlot.length}/${p.effectiveSlotMax}　空窍容量：${SlotCapacity.usedCapacity(p)}/${SlotCapacity.capacityMax(p)}${overload ? '【过载】' : ''}（基准 ${SlotCapacity.baseCapacity(p)}+拓窍${SlotCapacity.expandBonus(p)}）', overload ? MsgType.danger : MsgType.system);
    } else {
      out('  蛊槽：${p.guInSlot.length}/${p.effectiveSlotMax}（基础${p.slotMax}+空窍加成${p.slotBonus}）', MsgType.system);
    }
    out('  真元：${p.trueyuan}/${p.trueyuanMax}', MsgType.system);
    out('  体魄：${p.physique}　魂力：${p.soulPower}　气运：${p.luck}', MsgType.system);
    final lifeType = p.lifeLeft < 20 ? MsgType.danger : (p.lifeLeft < 50 ? MsgType.scene : MsgType.fortune);
    out('  寿元：${p.lifeLeft.toStringAsFixed(1)}/${p.lifeMax.toInt()} 年', lifeType);
    if (p.daoMark.isNotEmpty) {
      out('  道痕：${p.daoMark.entries.map((e) => '${e.key}:${e.value.toInt()}').join('、')}', MsgType.gu);
    }
    // 第二阶段：饱食度
    if (FoodSystem.strictMode(p)) {
      final left = FoodSystem.satietyHoursLeft(p);
      final tag = left <= 0 ? '【饥饿】' : (left < 6 ? '【半饱】' : '');
      out('  饱食：剩余 ${left.toStringAsFixed(0)} 小时 $tag', left <= 0 ? MsgType.danger : MsgType.system);
    }
    out('  伤势：${p.injure.isEmpty ? '无' : p.injure.join('、')}', p.injure.isEmpty ? MsgType.system : MsgType.danger);
    // 接入【毒素中毒系统】毒素详情
    final poisons = PoisonStore.list(p);
    if (poisons.isEmpty) {
      out('  毒素：无', MsgType.system);
    } else {
      out('  毒素（共${poisons.length}种）：', MsgType.danger);
      for (final x in poisons) {
        out('    · ${x.brief()}', MsgType.danger);
      }
      out('  解毒：herb [草药名] / use [解毒蛊] / burnlife [年数] / poisonattack [毒物]', MsgType.system);
    }
    // 第二阶段：储物容量
    if (StorageGu.strictMode(p)) {
      final used = StorageGu.usedCapacity(p);
      final max = StorageGu.capacityMax(p);
      out('  储物：$used/$max（随身${StorageGu.carryBase}+蛊加成${StorageGu.storageBonus(p)}）', used > max ? MsgType.danger : MsgType.system);
    }
    out('  劫数：${p.tribulation.toInt()}（积满触发天劫）', MsgType.scene);
    out('  杀戮：${p.kills}　炼蛊造诣：${p.refineProficiency.toInt()}', MsgType.system);
    out('  世界时间：已过 ${p.worldTime.toInt()} 小时（约 ${(p.worldTime / 1440).toStringAsFixed(2)} 年）', MsgType.system);
    // 第二阶段：势力声望简览
    final repSummary = Reputation.summary(player!);
    if (repSummary.isNotEmpty) {
      out('  声望：$repSummary', MsgType.system);
    }
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
    // V1.3 新增【环境联动】：昼夜/天气影响捕捉成功率
    // V1.6 加固：浓雾下密林/洞窟场景额外藏匿，捕捉率进一步降低
    final curRm = curRoom();
    final chanceMul = EnvironmentSystem.captureChanceMul(player!, room: curRm);
    final l = gu.capture(player!, gid, guList, curRm, chanceMul: chanceMul);
    for (final s in l) out(s, MsgType.gu);
    if (chanceMul < 0.95) {
      out('  〔环境〕当前时段/天气/场景使捕捉成功率降至 ${(chanceMul * 100).round()}%。', MsgType.system);
    }
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
    final recipeName = args.join(' ');
    // V1.3 新增【炼蛊环境需求校验】：不满足场景环境条件时禁止启动炼制并给出提示。
    Recipe? recipe;
    for (final r in recipes) {
      if (r.name == recipeName) { recipe = r; break; }
    }
    if (recipe == null) {
      out('不存在蛊方：$recipeName', MsgType.danger);
      return;
    }
    final envErr = _checkRefineEnv(recipe);
    if (envErr != null) {
      out(envErr, MsgType.danger);
      return;
    }
    final l = gu.refine(player!, recipeName, recipes, guList);
    for (final s in l) out(s, MsgType.gu);
    tick(actionHours['refine']!, allowAmbush: true);
    // V1.9: ② 炼蛊结束自动存档
    unawaited(_triggerAutoSave('alchemy'));
  }

  /// V1.3 新增【炼蛊环境需求校验】：检查蛊方 env_required（流派倍率/时段/天气）。
  /// 返回 null 表示满足，否则返回失败提示文本。
  String? _checkRefineEnv(Recipe recipe) {
    final env = recipe.envRequired;
    if (env.isEmpty) return null;
    final p = player!;
    final room = curRoom();
    // 流派倍率要求：{"min_school": "毒道", "min_mul": 1.20}
    final minSchool = env['min_school'];
    final minMul = env['min_mul'];
    if (minSchool is String && minMul is num) {
      final curMul = EnvironmentSystem.schoolMultiplier(p, room, minSchool);
      if (curMul < minMul.toDouble()) {
        return '【环境不足】炼制 ${recipe.name} 需 ${minSchool}环境倍率 ≥${minMul}（当前 ${curMul.toStringAsFixed(2)}），请前往对应场景。';
      }
    }
    // 时段要求：{"phase": "夜晚"}
    final phase = env['phase'];
    if (phase is String) {
      final curPhase = EnvironmentSystem.curPhase(p).phase;
      if (curPhase != phase) {
        return '【环境不足】炼制 ${recipe.name} 需在「$phase」时段进行（当前 $curPhase）。';
      }
    }
    // 天气要求：{"weather": "小雨"}
    final weather = env['weather'];
    if (weather is String) {
      final curW = EnvironmentSystem.curWeather(p);
      if (curW != weather) {
        return '【环境不足】炼制 ${recipe.name} 需在「$weather」天气下进行（当前 $curW）。';
      }
    }
    return null;
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
    // V1.4 新增【任务系统】：与NPC对话推进 talk_npc 类任务
    final questLogs = QuestSystem.onTalkNpc(player!, n.nid);
    for (final ql in questLogs) {
      out(ql, MsgType.fortune);
    }
    // V1.4 新增【NPC好感度剧情分支】：根据好感度解锁专属情报/蛊方兑换
    final affinityLogs = NpcAffinity.onTalk(player!, n.nid, n.name);
    for (final al in affinityLogs) {
      out(al, MsgType.fortune);
    }
    NpcAffinity.onTalkEnd(player!, n.nid);
    tick(actionHours['talk']!);
  }

  void doTrade(List<String> args) {
    if (args.isEmpty) { out('用法：trade [npc名]', MsgType.danger); return; }
    final n = _findNpc(args.join(' '));
    if (n == null) { out('这里没有这个人。', MsgType.danger); return; }
    if (!n.isMerchant) { out('${n.name} 并非商人，无法交易。', MsgType.danger); return; }
    out('【${n.name} 的货物】（原石=通用货币）', MsgType.fortune);
    // BUG修复【老槐翁原石循环刷取】：过滤黑名单商品（原石为货币，不出售）
    for (final e in n.tradeGoods.entries) {
      if (isTradeBlacklisted(e.key)) continue;
      out('  · ${e.key}  价格:${e.value}原石', MsgType.system);
    }
    out('请在输入框输入：buy [物品名] [数量] / sell [材料名] [数量]', MsgType.scene);
    tick(actionHours['trade']!);
  }

  /// 交易指令由 UI 输入框直接传入处理
  /// BUG修复【老槐翁原石循环刷取漏洞】：
  ///   - 黑名单物品（原石=货币）禁止作为商品买卖，杜绝 sell 原石→得原石 的闭环兑换
  ///   - 购买侧：黑名单物品不可购买（NPC不出售货币）
  ///   - 出售侧：黑名单物品不可出售（货币不能卖给NPC换货币，否则无限复制）
  void doTradeAction(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.isEmpty) return;
    final p = player!;
    final npc = npcsInCurRoom().firstWhere((n) => n.isMerchant, orElse: () => npcsInCurRoom().first);
    if (parts[0] == 'buy' && parts.length >= 2) {
      final item = parts.length >= 3 && int.tryParse(parts.last) != null ? parts.sublist(1, parts.length - 1).join(' ') : parts.sublist(1).join(' ');
      final cnt = int.tryParse(parts.last) ?? 1;
      // BUG修复：黑名单物品（原石）禁止购买
      if (isTradeBlacklisted(item)) {
        out('${npc.name} 不出售 $item（$item 为通用货币，不可购买）。', MsgType.danger);
        return;
      }
      final price = (npc.tradeGoods[item] ?? 0) * cnt;
      if (price == 0) { out('${npc.name} 不出售 $item。', MsgType.danger); return; }
      if (gu.countMaterial(p, '原石') < price) { out('原石不足，需 $price 原石。', MsgType.danger); return; }
      gu.consumeMaterial(p, '原石', price);
      gu.addMaterial(p, item, cnt);
      out('购入 ${item}x$cnt，消耗 $price 原石。', MsgType.fortune);
      // V1.9: ② 交易完成自动存档（购买）
      unawaited(_triggerAutoSave('trade'));
    } else if (parts[0] == 'sell' && parts.length >= 2) {
      final item = parts.length >= 3 && int.tryParse(parts.last) != null ? parts.sublist(1, parts.length - 1).join(' ') : parts.sublist(1).join(' ');
      final cnt = int.tryParse(parts.last) ?? 1;
      if (!gu.hasMaterial(p, item, cnt)) { out('背包中 $item 不足。', MsgType.danger); return; }
      // BUG修复：黑名单物品（原石=货币）禁止出售，杜绝 sell原石→得原石 的无限复制闭环
      if (isTradeBlacklisted(item)) {
        out('$item 为通用货币，不可出售给商人（禁止货币闭环兑换）。', MsgType.danger);
        return;
      }
      final matInfo = (materials['materials'] ?? {}) as Map;
      final priceInfo = ((matInfo[item] ?? {}) as Map)['price'] ?? 1;
      final price = imax(1, ((priceInfo as num) * 0.6).toInt()) * cnt;
      gu.consumeMaterial(p, item, cnt);
      gu.addMaterial(p, '原石', price);
      out('出售 ${item}x$cnt，获得 $price 原石。', MsgType.fortune);
      // V1.9: ② 交易完成自动存档（出售）
      unawaited(_triggerAutoSave('trade'));
    } else {
      out('未识别的交易指令。', MsgType.danger);
    }
  }

  void doAttack(List<String> args) {
    if (args.isEmpty) { out('用法：attack [npc名]', MsgType.danger); return; }
    final n = _findNpc(args.join(' '));
    if (n == null) { out('这里没有可以攻击的目标。', MsgType.danger); return; }
    if (!n.alive) { out('${n.name} 已死。', MsgType.danger); return; }
    // V1.6 加固【BOSS现身条件拦截】：BOSS 房间中未现身的 BOSS（时段/天气不满足）不可被攻击。
    // 例：寒雾蛇王仅夜晚+浓雾现身，白日 attack 蛇王会被拦截并提示。
    final r = curRoom();
    if (r.bossInfo.isNotEmpty && r.bossInfo['npc_id'] == n.nid &&
        !EnvironmentSystem.isBossPresent(player!, r.rid, r.bossInfo)) {
      final limitDay = r.bossInfo['limit_daytime'];
      final limitW = r.bossInfo['limit_weather'];
      final parts = <String>[];
      if (limitDay is List && limitDay.isNotEmpty) parts.add('${limitDay.join("/")}时段');
      if (limitW is List && limitW.isNotEmpty) parts.add('${limitW.join("/")}天气');
      out('${n.name} 当前并未现身——${parts.isEmpty ? "尚未复苏" : "需${parts.join("、")}方会现身"}。', MsgType.danger);
      return;
    }
    out('你向 ${n.name} 发起攻击！', MsgType.combat);
    final env = curRoom().envEffect;
    // 第三阶段新增【12.4 战斗日志播报环境效果】：场景环境对流派蛊术的加成提示。
    // 引擎 _calcAttack 已按 env[school] 放大伤害，此处仅做上层日志播报，不改引擎。
    if (env.isNotEmpty) {
      final buffSchools = env.entries
          .where((e) => (e.value as num) > 1)
          .map((e) => '${e.key}×${(e.value as num).toStringAsFixed(2)}')
          .join('、');
      if (buffSchools.isNotEmpty) {
        out('  【环境增益】${curRoom().name}：$buffSchools 流派威力提升。', MsgType.scene);
      }
    }
    // 第三阶段新增【10.2/12.4 AI战术播报】：根据 ai_type 提示 NPC 战斗倾向。
    // 引擎内置 AI 钩子已按 isHostile 触发伏击、低血量逃跑；此处仅日志提示战术风格。
    out('  【敌方战术】${n.name}（${_aiTacticDesc(n.aiType)}）', MsgType.system);
    combat = combatEngine.startCombat(player!, n, env);
    inCombat = true;
    for (final l in combat!.log) out(l, l.contains('战斗') || l.contains('伤害') ? MsgType.combat : MsgType.system);
  }

  /// 第三阶段新增【10】：ai_type 战术描述（上层日志用，不改动引擎 AI 逻辑）。
  String _aiTacticDesc(String aiType) {
    switch (aiType) {
      case 'aggressive': return '凶猛主动，低血量亦不退缩';
      case 'defend': return '防御自保，优先固守反击';
      case 'smart': return '高阶智能，善用防御疗伤蛊';
      case 'calm':
      default: return '中立平和，攻守均衡';
    }
  }

  /// 战斗中玩家行动（由战斗UI调用）
  void combatAction(String action, [String? guName]) {
    if (combat == null) return;
    // V1.6 新增【冰岩峡谷不可逃跑】：no_flee_zone 房间（如冰岩峡谷）地形狭窄，
    //   一旦遭遇战斗便无路可逃，唯有死战方能脱身。拦截逃亡指令并提示。
    final act = action.toLowerCase();
    if (act == 'flee' || act == '逃亡') {
      final room = rooms[player!.location];
      if (room != null && room.secret == 'no_flee_zone') {
        out('【地形所限】此处地势狭窄，无路可逃！唯有死战方能脱身。', MsgType.danger);
        return;
      }
    }
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
        // V1.3 新增【副本BOSS定时重生】：击杀副本BOSS后标记死亡并启动重生倒计时。
        // 通过当前房间 boss_info 的 npc_id 匹配判定是否为BOSS；状态持久化于 player.flags。
        final room = curRoom();
        if (room.bossInfo.isNotEmpty && room.bossInfo['npc_id'] == combat!.npc.nid) {
          EnvironmentSystem.markBossDead(player!, room.rid, room.bossInfo);
          final respawnMin = (room.bossInfo['respawn_game_time'] as num?)?.toInt() ?? 120;
          out('  【首领陨落】${combat!.npc.name} 已被斩杀，约 $respawnMin 分钟（游戏时间）后将重新复苏。', MsgType.danger);
        }
        // V1.4 新增【任务系统】：击杀NPC后推进 kill_npc_count 类任务进度
        final questLogs = QuestSystem.onKillNpc(player!, combat!.npc.nid);
        for (final ql in questLogs) {
          out(ql, MsgType.fortune);
        }
        // V3.5 修复【悬赏 kill 类任务 BUG】：同步写入 kill_counts，供 BountyBoard 提交校验。
        // 原 BUG：BountyBoard._killCount 读 flags['kill_counts'][nid]，但全代码库无写入，
        // 导致 kill 类悬赏（清剿黑崖斥候/截杀青茅山商队/猎捕青纹豹）永远无法完成。
        final killedNid = combat!.npc.nid;
        final kcRaw = player!.flags['kill_counts'];
        final kcMap = Map<String, dynamic>.from(kcRaw is Map ? kcRaw : <String, dynamic>{});
        kcMap[killedNid] = ((kcMap[killedNid] as num?) ?? 0).toInt() + 1;
        player!.flags['kill_counts'] = kcMap;
      } else if (combat!.status == CombatStatus.lose) {
        _onDefeated(combat!.npc);
      }
      tick(actionHours['combat_end']!);
      combat = null;
      // V1.9: ② 战斗结算自动存档
      unawaited(_triggerAutoSave('combat'));
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
      // 防御：正常战斗战败时 npc 必不为空，极端异常下用"野怪"兜底避免 npe
      out('【你被 ${npc?.name ?? "野怪"} 击败！】', MsgType.danger);
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
    // 第二阶段：真元恢复倍率（空窍超限 + 饱食
    final mul = phase2_core.restRecoverMultiplier(p);
    // V1.5 新增【绿洲安全区休憩加成】：safe_zone 房间（如戈壁绿洲）灵气充沛，
    //   真元恢复倍率 ×1.5，且不受沙暴/流沙侵扰，是西漠唯一的安心修炼之地。
    final curRm = curRoom();
    final isSafeZone = curRm.secret == 'safe_zone';
    final zoneMul = isSafeZone ? mul * 1.5 : mul;
    final baseRecover = 20 + levelRank(p.level) * 5;
    final recover = (baseRecover * zoneMul).toInt();
    p.recoverTrueyuan(recover);
    p.physique = imin(100 + levelRank(p.level) * 20, p.physique + 5);
    if (p.injure.contains('轻伤') && DateTime.now().millisecond % 2 == 0) p.healInjure('轻伤');
    final mulDesc = (zoneMul - 1.0).abs() < 0.01 ? '' : '（倍率 ${zoneMul.toStringAsFixed(2)}）';
    out('你静坐修炼，恢复 $recover 真元$mulDesc，体魄略有恢复。', MsgType.fortune);
    if (isSafeZone) {
      out('  〔绿洲灵泉〕此地灵气充沛、远离沙暴沙盗，真元恢复倍率 ×1.5。', MsgType.fortune);
    }
    if (mul < 0.9) {
      out('  （真元恢复受阻：'
          '${slot_capacity_model.SlotCapacity.isOverloaded(p) ? '空窍容量过载' : ''}'
          '${food_model.FoodSystem.isHungry(p) ? '饥饿状态' : ''}'
          '。', MsgType.danger);
    }
    // 接入【毒素中毒系统】途径①：静坐可缓慢代谢轻微毒素，高阶仅延缓。
    final detoxLogs = PoisonSystem.detoxByRest(p, actionHours['rest']!);
    for (final l in detoxLogs) out(l, l.contains('成功') || l.contains('化解') ? MsgType.fortune : MsgType.system);
    // 第二阶段：饱食辅助解轻微毒
    final foodLogs = phase2_core.restFoodDetox(p, actionHours['rest']!);
    for (final l in foodLogs) out(l, MsgType.fortune);
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
    // V1.9: ② 采集完成自动存档
    unawaited(_triggerAutoSave('collect'));
  }

  // ===================== 【毒素中毒系统】解毒指令 =====================

  /// 解毒帮助：列出当前毒素与可用解毒手段。
  void doDetoxHelp() {
    final p = player!;
    final poisons = PoisonStore.list(p);
    out('═══ 祛毒指南 ═══', MsgType.fortune);
    if (poisons.isEmpty) {
      out('  你体内无毒，一身轻松。', MsgType.system);
    } else {
      out('  当前中毒（共${poisons.length}种）：', MsgType.danger);
      for (final x in poisons) out('    · ${x.brief()}', MsgType.danger);
    }
    out('  解毒途径：', MsgType.system);
    out('    ① rest 静坐休养 —— 缓慢代谢轻微毒素，高阶仅延缓', MsgType.system);
    out('    ② herb [草药名] —— 解毒草药，解轻微压制烈性（重复效果衰减）', MsgType.system);
    out('    ③ use [解毒蛊名] —— 解毒蛊虫，主流手段（凡蛊不解道毒）', MsgType.system);
    out('    ④ burnlife [年数] —— 燃烧寿元强行逼毒（永久削寿，失败叠加）', MsgType.system);
    out('    ⑤ poisonattack [毒物名] —— 以毒攻毒（失败毒素叠加）', MsgType.system);
    out('  可向老槐翁购入解毒草药（青茅草、银针花、解毒散）。', MsgType.scene);
  }

  /// 服用解毒草药。读取 material.json 的 effect.detox 字段判定药力。
  /// 凡蛊/草药硬限制：无法解除奇毒与道毒。
  void doConsumeHerb(List<String> args) {
    final p = player!;
    if (args.isEmpty) {
      out('用法：herb [草药名]（如 青茅草/银针花/解毒散）', MsgType.danger);
      out('可服用的解毒草药需从老槐翁处购入。', MsgType.system);
      return;
    }
    final name = args.join(' ');
    if (!gu.hasMaterial(p, name, 1)) {
      out('背包中没有 $name。', MsgType.danger);
      return;
    }
    // 读取 material.json 的 effect 字段
    final matInfo = (materials['materials'] ?? {}) as Map;
    final info = (matInfo[name] ?? {}) as Map;
    final effect = info['effect'];
    if (effect == null || (effect is Map && effect['type'] != 'detox')) {
      out('$name 并非解毒草药，无法服用解毒。', MsgType.danger);
      return;
    }
    final herbPower = ((effect as Map)['power'] ?? 5) as num;
    gu.consumeMaterial(p, name, 1);
    final uses = PoisonSystem.herbUsesToday(p);
    final logs = PoisonSystem.detoxByHerb(p, herbPower.toInt(), usesToday: uses);
    PoisonSystem.incHerbUses(p);
    for (final l in logs) {
      out(l, l.contains('成功') || l.contains('药到') || l.contains('化解') ? MsgType.fortune : MsgType.system);
    }
    tick(actionHours['use_gu']!, allowAmbush: true);
  }

  /// 燃烧寿元强行逼毒（高危手段，永久削减寿元，失败毒素叠加）。
  void doBurnLife(List<String> args) {
    final p = player!;
    double years;
    if (args.isEmpty) {
      years = 2.0; // 默认燃烧 2 年
    } else {
      final v = double.tryParse(args[0]);
      if (v == null || v <= 0) {
        out('用法：burnlife [年数]（如 burnlife 3，默认 2 年）', MsgType.danger);
        return;
      }
      years = v;
    }
    if (!PoisonStore.hasAny(p)) {
      out('你体内无毒，何须燃烧寿元逼毒。', MsgType.danger);
      return;
    }
    if (p.lifeLeft <= years + 1) {
      out('寿元仅剩 ${p.lifeLeft.toStringAsFixed(1)} 年，不敢燃烧 $years 年，恐当场陨落。', MsgType.danger);
      return;
    }
    final logs = PoisonSystem.detoxByBurnLife(p, years);
    for (final l in logs) {
      out(l, l.contains('成功') ? MsgType.fortune
          : (l.contains('失败') || l.contains('反扑') ? MsgType.danger : MsgType.system));
    }
    tick(actionHours['rest']!, allowAmbush: true);
  }

  /// 以毒攻毒：使用一种毒素材料/蛊去攻体内最高阶毒素，失败则叠加。
  /// 仅支持持有"毒囊""蛇蜕""黑莲花瓣"三种毒素材料，或持有毒道蛊虫。
  void doPoisonAttack(List<String> args) {
    final p = player!;
    if (args.isEmpty) {
      out('用法：poisonattack [毒物名]（如 毒囊/蛇蜕/黑莲花瓣）', MsgType.danger);
      return;
    }
    final name = args.join(' ');
    if (!gu.hasMaterial(p, name, 1)) {
      out('背包中没有 $name，无法以毒攻毒。', MsgType.danger);
      return;
    }
    // 内置毒物映射表（不依赖 material.json 扩展字段，保持兼容）
    final (pName, pRank, pPower) = switch (name) {
      '毒囊'       => ('毒囊之毒', PoisonRank.fierce, 15),
      '蛇蜕'       => ('蛇瘴之毒', PoisonRank.minor, 8),
      '黑莲花瓣'   => ('黑莲奇毒', PoisonRank.odd, 25),
      _            => ('', PoisonRank.minor, 0),
    };
    if (pPower == 0) {
      out('$name 不含可用之毒，无法以毒攻毒。', MsgType.danger);
      return;
    }
    if (!PoisonStore.hasAny(p)) {
      out('你体内无毒，以毒攻毒多此一举。', MsgType.danger);
      return;
    }
    gu.consumeMaterial(p, name, 1);
    final logs = PoisonSystem.detoxByPoisonAttack(p,
      attackPid: 'attack_$name',
      attackName: pName,
      attackRank: pRank,
      poisonPower: pPower,
    );
    for (final l in logs) {
      out(l, l.contains('成功') ? MsgType.fortune : MsgType.danger);
    }
    tick(actionHours['use_gu']!, allowAmbush: true);
  }

  void doSave(List<String> args) {
    final slot = (args.isNotEmpty && int.tryParse(args[0]) != null) ? int.parse(args[0]) : 0;
    if (slot < 1 || slot > 5) { out('用法：save [1~5]', MsgType.danger); return; }
    unawaited(saveToSlot(slot));
  }

  void doLoad(List<String> args) {
    final slot = (args.isNotEmpty && int.tryParse(args[0]) != null) ? int.parse(args[0]) : 0;
    if (slot < 1 || slot > 5) { out('用法：load [1~5]', MsgType.danger); return; }
    unawaited(loadFromSlot(slot));
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

  // ============== 第二阶段：新增系统指令处理 ==============

  /// 空窍容量详情
  void doSlotInfo() {
    final p = player!;
    SlotCapacity.ensureStrictMode(p);
    out('═══ 空窍·承载容量 ═══', MsgType.fortune);
    out('  境界基准容量：${SlotCapacity.baseCapacity(p)}', MsgType.system);
    out('  拓窍加成：+${SlotCapacity.expandBonus(p)}', MsgType.system);
    out('  总上限：${SlotCapacity.capacityMax(p)}', MsgType.system);
    out('  已占用：${SlotCapacity.usedCapacity(p)}（剩余 ${SlotCapacity.freeCapacity(p)}）', MsgType.system);
    if (SlotCapacity.isOverloaded(p)) {
      out('  【警告】容量过载！真元恢复倍率 ${SlotCapacity.trueyuanRecoverMultiplier(p).toStringAsFixed(2)}，每日滋生暗伤。', MsgType.danger);
    } else {
      out('  真元恢复倍率：${SlotCapacity.trueyuanRecoverMultiplier(p).toStringAsFixed(2)}', MsgType.system);
    }
    out('  已装备蛊占用明细：', MsgType.gu);
    for (final g in p.guInSlot) {
      out('    · ${g.name}（${g.rank}转）占用 ${SlotCapacity.guUse(g)}', MsgType.gu);
    }
  }

  /// 储物容量详情
  void doStorageInfo() {
    final p = player!;
    StorageGu.ensureStrictMode(p);
    out('═══ 储物蛊·背包容量 ═══', MsgType.fortune);
    out('  随身基础：${StorageGu.carryBase}', MsgType.system);
    out('  储物蛊加成：+${StorageGu.storageBonus(p)}', MsgType.system);
    out('  总上限：${StorageGu.capacityMax(p)}', MsgType.system);
    out('  已占用：${StorageGu.usedCapacity(p)}（剩余 ${StorageGu.freeCapacity(p)}）', StorageGu.freeCapacity(p) < 0 ? MsgType.danger : MsgType.system);
    if (p.guInSlot.isNotEmpty || p.guBag.isNotEmpty) {
      out('  储物蛊明细（已装备+寄存中生效）：', MsgType.gu);
      for (final g in [...p.guInSlot, ...p.guBag]) {
        if (StorageGu.storageCapOf(g) > 0) {
          out('    · ${g.name} +${StorageGu.storageCapOf(g)}', MsgType.gu);
        }
      }
    }
  }

  /// 进食系统
  void doEat(List<String> args) {
    final p = player!;
    FoodSystem.ensureStrictMode(p);
    if (args.isEmpty) {
      out('用法：eat [食物名] 或 数量。当前背包中可直接食用物资：', MsgType.system);
      int found = 0;
      for (final it in p.inventory) {
        final (n, c) = MatParser.parse(it);
        final info = materials[n] as Map<String, dynamic>?;
        final fe = FoodSystem.parseFoodEffect(info?['effect'] as Map<String, dynamic>?);
        if (fe != null) {
          out('  · $n x$c (${fe.desc()})', MsgType.system);
          found++;
        }
      }
      if (found == 0) out('  （无可直接食用物资，建议前往山寨厨房或采集野果/兽肉。）', MsgType.scene);
      return;
    }
    final name = args[0];
    final count = args.length >= 2 ? int.tryParse(args[1]) ?? 1 : 1;
    // 检查库存
    if (!gu.hasMaterial(p, name, count)) {
      out('物资不足：$name 需要 $count 份。', MsgType.danger);
      return;
    }
    // 解析效果
    final info = materials[name] as Map<String, dynamic>?;
    final fe = FoodSystem.parseFoodEffect(info?['effect'] as Map<String, dynamic>?);
    if (fe == null) {
      out('$name 不能直接食用。', MsgType.danger);
      return;
    }
    gu.consumeMaterial(p, name, count);
    final logs = FoodSystem.consume(p, name, count, fe,
        detoxMinorByFoodOnly: (power) => PoisonSystem.detoxMinorByFoodOnly(p, power));
    for (final l in logs) out(l, MsgType.fortune);
    tick(1);
  }

  /// 杀招构筑：列/释放
  void doKillerMove(List<String> args) {
    final p = player!;
    if (args.isEmpty) {
      final list = KillerMoveStore.list(p);
      out('═══ 已构筑杀招 ═══', MsgType.fortune);
      if (list.isEmpty) out('  （尚未构筑杀招，使用 kmnew 杀招名 蛊名1,蛊名2 创建）', MsgType.system);
      for (int i = 0; i < list.length; i++) {
        final km = list[i];
        out('  [$i] ${km.name}（${km.guInstIds.length}蛊）：${km.schoolsBrief()}', MsgType.gu);
        out('       蛊：${km.guNames(p).join("、")}', MsgType.system);
      }
      return;
    }
    final target = args.join(' ');
    final km = KillerMoveStore.find(p, target);
    if (km == null) { out('未找到杀招：$target', MsgType.danger); return; }
    final (dmg, logs, backlash) = km.cast(p);
    for (final l in logs) out(l, backlash ? MsgType.danger : MsgType.combat);
    out('【${km.name}】造成 $dmg 点综合伤害（已扣除气血）。', backlash ? MsgType.danger : MsgType.combat);
    tick((actionHours['rest']! ~/ 3).toDouble());
  }

  /// 新建杀招
  void doKillerMoveNew(List<String> args) {
    if (args.length < 2) {
      out('用法：kmnew 杀招名 蛊名1,蛊名2,蛊名3', MsgType.system);
      return;
    }
    final name = args[0];
    final gus = args[1].split(',').where((x) => x.trim().isNotEmpty).toList();
    if (gus.length < 2) {
      out('杀招至少需要2只蛊虫组合。', MsgType.danger);
      return;
    }
    final ok = KillerMoveStore.add(player!, name, gus);
    if (ok) {
      out('杀招「$name」构筑成功！组合 ${gus.length} 只蛊，可使用 km $name 施放。', MsgType.fortune);
    } else {
      out('构筑失败：至少需要组合中蛊虫需在空窍或背包中存在。', MsgType.danger);
    }
  }

  /// 删除杀招
  void doKillerMoveDel(List<String> args) {
    if (args.isEmpty) { out('用法：kmdel 杀招名/编号', MsgType.system); return; }
    final ok = KillerMoveStore.remove(player!, args.join(' '));
    out(ok ? '已删除杀招。' : '未找到该杀招（支持名称或数字编号）。', ok ? MsgType.system : MsgType.danger);
  }

  /// V1.9 专项【仙道杀招·原著预设】：列/释放。
  /// 用法：pkm         → 列出全部预设杀招（解锁/锁定/冷却状态）
  ///       pkm 杀招名  → 释放指定预设杀招
  void doPresetKillerMove(List<String> args) {
    final p = player!;
    // V1.9 专项：每次操作预设杀招前刷新解锁（集齐全套蛊虫自动解锁）
    final newlyUnlocked = PresetKillerMoveStore.refreshUnlock(p);
    if (newlyUnlocked != null) {
      out('【仙道杀招·解锁】你集齐了配套蛊虫，仙道杀招『$newlyUnlocked』自行领悟，可催动释放！', MsgType.fortune);
      notifyListeners();
    }
    if (args.isEmpty) {
      final list = PresetKillerMoveStore.presets;
      out('═══ 仙道杀招·原著预设 ═══', MsgType.fortune);
      if (list.isEmpty) {
        out('  （暂无预设仙道杀招）', MsgType.system);
        return;
      }
      for (int i = 0; i < list.length; i++) {
        final m = list[i];
        final unlocked = PresetKillerMoveStore.isUnlocked(p, m);
        final hasGu = PresetKillerMoveStore.hasAllGu(p, m);
        final cooling = PresetKillerMoveStore.isCoolingDown(p, m);
        String status;
        MsgType st;
        if (unlocked && hasGu) {
          if (cooling) {
            final left = PresetKillerMoveStore.cooldownLeft(p, m);
            status = ' [冷却中·剩余${left}分钟]';
            st = MsgType.system;
          } else {
            status = ' [已解锁·可释放]';
            st = MsgType.gu;
          }
        } else {
          status = ' [锁定·缺少配套蛊虫]';
          st = MsgType.danger;
        }
        out('  [$i] ${m.name}$status', st);
        out('       原著：${m.source}', MsgType.system);
        out('       所需蛊虫：${m.requiredGu.join("、")}　消耗：${m.costZhen}真元　冷却：${m.cooldown}分钟', MsgType.system);
        if (m.backlash.isNotEmpty) {
          out('       反噬：${m.backlash}', MsgType.danger);
        }
      }
      return;
    }
    final key = args.join(' ');
    final m = PresetKillerMoveStore.find(key);
    if (m == null) {
      out('未找到仙道杀招：$key', MsgType.danger);
      return;
    }
    // 释放前再次刷新解锁（防止刚刚集齐未播报）
    PresetKillerMoveStore.refreshUnlock(p);
    final (dmg, logs, backlash) = PresetKillerMoveStore.cast(p, m);
    for (final l in logs) {
      out(l, backlash ? MsgType.danger : MsgType.combat);
    }
    if (dmg > 0) {
      out('【${m.name}】造成 $dmg 点综合伤害。', backlash ? MsgType.danger : MsgType.combat);
    }
    notifyListeners();
    tick((actionHours['rest']! ~/ 3).toDouble());
  }

  /// 势力声望面板
  void doReputation() {
    final p = player!;
    out('═══ 南疆·势力声望 ═══', MsgType.fortune);
    for (final f in Faction.all) {
      final v = Reputation.of(p, f);
      final fname = Faction.names[f] ?? f;
      final grade = Reputation.gradeLabel(v);
      final mul = Reputation.priceMul(p, f);
      final enter = Reputation.canEnter(p, f) ? '可通行' : '禁止进入';
      final hostile = Reputation.isHostile(p, f) ? '【敌对】' : '';
      out('  $fname $hostile：$v（$grade）', Reputation.isHostile(p, f) ? MsgType.danger : MsgType.system);
      out('       交易倍率 ${mul.toStringAsFixed(2)}x，地图：$enter，专属解锁：${Reputation.canUnlockExclusive(p, f) ? '已解锁' : '未解锁'}', MsgType.system);
    }
  }

  /// 悬赏榜
  void doBountyList() {
    final list = BountyBoard.list(player!);
    out('═══ 全域悬赏榜 ═══', MsgType.fortune);
    if (list.isEmpty) out('  （当前无悬赏任务）', MsgType.system);
    for (int i = 0; i < list.length; i++) {
      final q = list[i];
      final status = q.status == 'accepted' ? '【进行中】' : (q.status == 'done' ? '【已完成】' : '');
      out('  [$i] ${q.title} $status', MsgType.system);
      out('       ${q.desc}', MsgType.scene);
      out('       奖励：${q.rewardDesc} | 提交方式：bountysubmit $i', MsgType.fortune);
    }
  }

  /// 接取悬赏
  void doBountyAccept(List<String> args) {
    if (args.isEmpty) { out('用法：bountyaccept [编号]', MsgType.system); return; }
    final idx = int.tryParse(args[0]) ?? -1;
    final list = BountyBoard.list(player!);
    if (idx < 0 || idx >= list.length) { out('编号无效。', MsgType.danger); return; }
    final (ok, msg) = BountyBoard.accept(player!, list[idx]);
    out(msg, ok ? MsgType.fortune : MsgType.danger);
  }

  /// 提交悬赏
  void doBountySubmit(List<String> args) {
    if (args.isEmpty) { out('用法：bountysubmit [编号]', MsgType.system); return; }
    final idx = int.tryParse(args[0]) ?? -1;
    final list = BountyBoard.list(player!);
    if (idx < 0 || idx >= list.length) { out('编号无效。', MsgType.danger); return; }
    final (ok, logs, rewards) = BountyBoard.submit(player!, list[idx]);
    for (final l in logs) out(l, ok ? MsgType.fortune : MsgType.danger);
    if (ok && rewards.isNotEmpty) {
      for (final e in rewards.entries) {
        gu.addMaterial(player!, e.key, e.value);
      }
      out('获得奖励：${rewards.entries.map((e) => '${e.key}x${e.value}').join(", ")}', MsgType.fortune);
    }
  }

  /// 以物易物
  void doBarter(List<String> args) {
    if (args.length < 3) {
      out('用法：barter [npc名] [你出物资]x[数量]=[想要物资]x[数量]', MsgType.system);
      return;
    }
    final npcName = args[0];
    final expr = args.sublist(1).join(' ');
    // parse: giveMat x giveCnt = wantMat x wantCnt
    final parts = expr.split('=');
    if (parts.length != 2) { out('格式错误：需 "give=want" 格式', MsgType.danger); return; }
    final givePart = parts[0].split('x');
    final wantPart = parts[1].split('x');
    if (givePart.isEmpty || wantPart.isEmpty) { out('格式错误', MsgType.danger); return; }
    final giveName = givePart[0].trim();
    final giveCount = givePart.length > 1 ? (int.tryParse(givePart[1].trim()) ?? 1) : 1;
    final wantName = wantPart[0].trim();
    final wantCount = wantPart.length > 1 ? (int.tryParse(wantPart[1].trim()) ?? 1) : 1;
    final (ok, logs) = Barter.trade(
      player!,
      giveMat: {giveName: giveCount},
      wantMat: {wantName: wantCount},
    );
    for (final l in logs) out(l, ok ? MsgType.fortune : MsgType.danger);
    if (ok) {
      // 执行物资交换
      gu.consumeMaterial(player!, giveName, giveCount);
      gu.addMaterial(player!, wantName, wantCount);
    }
    tick(1);
  }

  /// 黑市
  void doBlackMarket() {
    final (ok, msg) = BlackMarket.canEnter(player!);
    if (!ok) { out(msg, MsgType.danger); return; }
    out('═══ 南疆黑市（夜间/地下集市） ═══', MsgType.fortune);
    out(msg, MsgType.scene);
    // V1.4 新增【蛊潮周期提示】
    if (BlackMarket.isGuchaoActive(player!)) {
      out('  ⚡ 蛊潮将至！黑市追加蛊潮专属货品。', MsgType.danger);
    }
    if (((player!.flags['blackmarket_vip'] as num?)?.toInt() ?? 0) > 0) {
      out('  ★ VIP 通道已开启，可选购高阶蛊方。', MsgType.fortune);
    }
    final stock = BlackMarket.stock(player!);
    if (stock.isEmpty) {
      out('  （今夜无新货……）', MsgType.scene);
    } else {
      for (final s in stock) {
        out('  · ${s.name}（${s.desc}）：${s.price} 原石', MsgType.system);
      }
      out('  （购买使用 trade 指令或后续 UI 入口）', MsgType.system);
    }
  }

  // V1.4 新增【任务系统】指令处理：quest / quest accept <qid> / quest turnin <qid>
  void doQuest(List<String> args) {
    if (args.isEmpty) {
      // 列出所有任务概览
      final list = QuestSystem.overview(player!);
      if (list.isEmpty) {
        out('当前无任何任务。', MsgType.system);
        return;
      }
      out('═══ 任务列表 ═══', MsgType.fortune);
      for (final q in list) {
        final typeLabel = {'main': '主线', 'side': '支线', 'loop': '循环'}[q['type']] ?? q['type']!;
        final statusLabel = {
          'locked': '〔未解锁〕', 'available': '〔可接取〕', 'active': '〔进行中〕',
          'completed': '〔已完成·待交付〕', 'turned_in': '〔已交付〕'
        }[q['status']] ?? q['status']!;
        final prog = q['progress']!.isNotEmpty ? '  进度:${q['progress']}' : '';
        out('[$typeLabel] ${q['name']} $statusLabel$prog', MsgType.system);
        out('  ${q['desc']}', MsgType.scene);
      }
      out('用法：quest accept <任务名> 接取 | quest turnin <任务名> 交付', MsgType.system);
      return;
    }
    final sub = args[0].toLowerCase();
    if (sub == 'accept' || sub == '接取') {
      if (args.length < 2) { out('用法：quest accept <任务名>', MsgType.danger); return; }
      final name = args.sublist(1).join(' ');
      final qid = _findQuestIdByName(name);
      if (qid == null) { out('未找到任务「$name」。', MsgType.danger); return; }
      out(QuestSystem.accept(player!, qid), MsgType.fortune);
      return;
    }
    if (sub == 'turnin' || sub == '交付' || sub == 'submit') {
      if (args.length < 2) { out('用法：quest turnin <任务名>', MsgType.danger); return; }
      final name = args.sublist(1).join(' ');
      final qid = _findQuestIdByName(name);
      if (qid == null) { out('未找到任务「$name」。', MsgType.danger); return; }
      out(QuestSystem.turnIn(player!, qid), MsgType.fortune);
      return;
    }
    out('未知子指令：$sub（支持 accept/turnin）', MsgType.danger);
  }

  // 模糊匹配任务ID（支持任务名 / qid 前缀）
  String? _findQuestIdByName(String name) {
    for (final q in QuestSystem.quests) {
      if (q.name == name || q.qid == name) return q.qid;
    }
    for (final q in QuestSystem.quests) {
      if (q.name.contains(name) || name.contains(q.name)) return q.qid;
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
  南疆大地图已开放：瘴林/落雁谷/青茅山宗族/沼泽/黑崖寨/散修营地/秘境
  域外古道（border_前缀）禁制封锁，版本未开放
【角色状态】
  status / inventory / kuang / breakthrough(境界突破)
  slotinfo (空窍容量详情) / storage (储物容量详情)
  reputation / 声望 (势力声望)
【蛊虫操作】
  capture [目标] / refine [蛊方] / feed [蛊] [材料]
  equip [蛊] / unequip [蛊] / use [蛊]
  1~6转全流派蛊虫已补齐：力道/毒道/气道/血道/兽道/鬼道/食道/运道
【杀招构筑（第二阶段）】
  km / kmnew 杀招名 蛊名1,蛊名2,蛊名3...
  km 杀招名 (释放) / kmdel 杀招名
【仙道杀招·原著预设（V1.9）】
  pkm (列出全部预设杀招·解锁/锁定/冷却状态)
  pkm 杀招名 (释放·集齐蛊虫自动解锁·含冷却与反噬)
【生存行为】
  rest / gather / eat [食物名] (进食滋养)
【解毒系统】
  herb [草药名] / burnlife [年数] / poisonattack [毒物] / detox
【交易升级（第二阶段）】
  bounty / 悬赏榜 (全域悬赏)
  bountyaccept [编号] / bountysubmit [编号]
  barter [npc] [出价]x数量=目标x数量 (以物易物)
  blackmarket / 黑市 (夜间黑市)
【NPC交互】
  talk [npc] / trade [npc] / attack [npc] / flee
  三大势力：青茅山宗族/黑崖寨/南疆散修联盟，好感与声望影响交互
【系统指令】
  save [1~5] / load [1~5] / help / quit

提示：图形模式下点击日志中NPC名/野生蛊名可直接交互；
  点击场景标题行弹出地图导航；背包面板中点击材料/蛊虫名查看详情。
''';
