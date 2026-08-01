// trade_upgrade_model.dart
// 第二阶段新增：交易体系升级（黑市、悬赏榜、以物易物）（增量文件）。
// 设计原则：
//   - 100% 兼容旧存档：状态写入 player.flags['trade_v2']，旧存档无键回退
//   - 黑市商人：夜间 (worldTime%24>=20 || worldTime%24<=5) 出现，声望限制（青茅山 >=30 视为正道，黑市排斥），
//     售卖禁蛊赃物（高价）。
//   - 悬赏榜：内置 + 动态任务（存 flags），支持 kill / gather 两种目标；
//     完成后获得奖励（高阶蛊方/材料）与声望。
//   - 以物易物：与任意商人 NPC 协商，玩家选 X 物品换 Y 物品，基于价值比值判定成功率。
import 'dart:math' show max, min, Random;
import 'player_model.dart';
import 'recipe_model.dart' show MatParser;
import '../data_model/reputation_model.dart' show Reputation, Faction;

final _rng = Random();

// ---------- 黑市 ----------
class BlackMarketStock {
  final String name;
  final String desc;
  final int price;
  BlackMarketStock({required this.name, required this.desc, required this.price});
}

class BlackMarket {
  /// 夜间判定。
  static bool isNight(double worldTime) {
    final h = worldTime % 24;
    return h >= 20 || h <= 5;
  }

  /// 可否进入黑市：需夜间 + 青茅山声望 <30 否则视为正道，黑市排斥。
  static (bool, String) canEnter(Player p) {
    if (!isNight(p.worldTime)) return (false, '如今并非夜间，黑市尚未开摊（需入夜 20:00 之后或凌晨 05:00 之前）。');
    final r = Reputation.of(p, Faction.qingmao);
    if (r >= 30) return (false, '你与青茅山正道过从甚密（青茅山声望 $r >= 30），黑市拒你于门外。');
    return (true, '你踏入南疆地下黑市。瘴雾缭绕，蛊商们低声交谈，各类禁蛊赃物明码标价。');
  }

  /// 返回今夜黑市货物（伪随机，按 player.flags['trade_v2.black_seed'] 固定。）
  static List<BlackMarketStock> stock(Player p) {
    final raw = p.flags['trade_v2'];
    final Map<String, dynamic> m = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    // 固定种子：每世界日刷新一次
    final day = (p.worldTime ~/ 24);
    final seedKey = 'bm_day_seed_$day';
    int seed = (m[seedKey] as int?) ?? _rng.nextInt(99999);
    m[seedKey] = seed;
    p.flags['trade_v2'] = m;
    // 伪随机生成库存
    final rng2 = Random(seed);
    final candidates = [
      BlackMarketStock(name: '半残黑蛛蛊', desc: '三转禁蛊·毒道，黑市私藏，略有瑕疵', price: 380),
      BlackMarketStock(name: '锈蚀尸脑蛊', desc: '四转禁蛊·食道，传闻操控尸傀，来路不明', price: 800),
      BlackMarketStock(name: '失心香', desc: '二阶奇毒·心脉，无色无味，黑市禁售品', price: 220),
      BlackMarketStock(name: '断肠腐骨散', desc: '三阶奇毒·烈性，黑市最畅销毒物', price: 400),
      BlackMarketStock(name: '拓窍蛊残次', desc: '一次性拓窍容量+25（比正品少一半）', price: 900),
      BlackMarketStock(name: '储物囊·小', desc: '二转储物蛊，容量 +30', price: 600),
    ];
    final res = <BlackMarketStock>[];
    for (final c in candidates) {
      if (rng2.nextDouble() < 0.6) res.add(c);
    }
    // V1.4 新增【蛊潮周期刷新】：每3个游戏日（worldTime%72<24）触发蛊潮，黑市追加蛊潮专属货品
    final guchaoPhase = (p.worldTime % 72) < 24;
    if (guchaoPhase) {
      final guchaoStock = [
        BlackMarketStock(name: '蛊潮·万毒蛊方残片', desc: '蛊潮期间限定·毒道高阶蛊方残片', price: 1200),
        BlackMarketStock(name: '蛊潮·幽冥鬼砂', desc: '蛊潮期间限定·鬼道秘材', price: 350),
        BlackMarketStock(name: '蛊潮·血煞晶', desc: '蛊潮期间限定·血道秘材', price: 280),
        BlackMarketStock(name: '蛊潮·月华露', desc: '蛊潮期间限定·月道秘材', price: 200),
      ];
      for (final c in guchaoStock) {
        if (rng2.nextDouble() < 0.5) res.add(c);
      }
    }
    // V1.4 新增【VIP 扩展货品】：完成黑市委托任务（flags.blackmarket_vip）解锁高阶货品
    if (((p.flags['blackmarket_vip'] as num?)?.toInt() ?? 0) > 0) {
      res.add(BlackMarketStock(name: 'VIP·冥血蛊蛊方', desc: '黑市VIP专享·血煞宗镇宗蛊方', price: 2000));
      res.add(BlackMarketStock(name: 'VIP·风行蛊蛊方', desc: '黑市VIP专享·西漠通道关键蛊方', price: 1500));
    }
    return res.isEmpty ? candidates.sublist(0, 2) : res;
  }

  /// V1.4 新增：当前是否处于蛊潮周期（用于 UI 提示与场景联动）。
  static bool isGuchaoActive(Player p) => (p.worldTime % 72) < 24;
}

// ---------- 悬赏任务 ----------
/// 任务类型：kill 击杀指定 NPC/异兽 nid；gather 采集指定材料。
class BountyQuest {
  final String qid;
  final String title;
  final String desc;
  final String faction;   // 发布势力
  final String type;      // 'kill' | 'gather'
  final String target;    // nid 或 material 名
  final int amount;       // 击杀数/采集数
  final int rewardRep;    // 奖励声望
  final List<String> rewardItems; // 奖励物品（name 或 namexN）
  final int minRep;       // 最低接取声望（-100~100）
  final String status;    // 'open' | 'accepted' | 'done' （运行时计算）

  BountyQuest({
    required this.qid,
    required this.title,
    required this.desc,
    required this.faction,
    required this.type,
    required this.target,
    required this.amount,
    required this.rewardRep,
    required this.rewardItems,
    this.minRep = -30,
    this.status = 'open',
  });

  /// 奖励简述（用于 UI）。
  String get rewardDesc {
    final parts = <String>[];
    if (rewardRep != 0) parts.add('${Faction.names[faction] ?? faction}声望+$rewardRep');
    if (rewardItems.isNotEmpty) parts.add(rewardItems.join('、'));
    return parts.isEmpty ? '（无奖励）' : parts.join(' + ');
  }

  Map<String, dynamic> toJson() => {
    'qid': qid, 'title': title, 'desc': desc, 'faction': faction,
    'type': type, 'target': target, 'amount': amount,
    'reward_rep': rewardRep, 'reward_items': rewardItems,
    'min_rep': minRep,
  };

  factory BountyQuest.fromJson(Map<String, dynamic> j) => BountyQuest(
    qid: j['qid'], title: j['title'] ?? '', desc: j['desc'] ?? '',
    faction: j['faction'] ?? Faction.sanxiu, type: j['type'] ?? 'kill',
    target: j['target'] ?? '', amount: (j['amount'] as num?)?.toInt() ?? 1,
    rewardRep: (j['reward_rep'] as num?)?.toInt() ?? 5,
    rewardItems: List<String>.from(j['reward_items'] ?? []),
    minRep: (j['min_rep'] as num?)?.toInt() ?? -30,
  );

  /// 复制一个带 status 的副本。
  BountyQuest copyWith({String? status}) => BountyQuest(
    qid: qid, title: title, desc: desc, faction: faction,
    type: type, target: target, amount: amount,
    rewardRep: rewardRep, rewardItems: rewardItems,
    minRep: minRep, status: status ?? this.status,
  );
}

/// 静态内置悬赏（南疆全域）。
List<BountyQuest> _builtinBounties() => [
  BountyQuest(
    qid: 'bq_qingmao_001',
    title: '清剿黑崖斥候',
    desc: '黑崖寨斥候频繁骚扰我族山麓，击杀 3 名巡逻者，以儆效尤。',
    faction: Faction.qingmao,
    type: 'kill',
    target: 'hei_patrol',
    amount: 3,
    rewardRep: 15,
    rewardItems: ['原石x20', '青茅真液x2'],
    minRep: -20,
  ),
  BountyQuest(
    qid: 'bq_qingmao_002',
    title: '收集瘴林药草',
    desc: '药堂急需瘴林深处的“瘴灵草”，采集 5 株送交即可。',
    faction: Faction.qingmao,
    type: 'gather',
    target: '瘴灵草',
    amount: 5,
    rewardRep: 10,
    rewardItems: ['解毒散x3', '原石x15'],
    minRep: -30,
  ),
  BountyQuest(
    qid: 'bq_heiya_001',
    title: '截杀青茅山商队',
    desc: '青茅山商队明日途经落雁谷，夺取物资并击杀护队者。',
    faction: Faction.heiya,
    type: 'kill',
    target: 'qm_caravan',
    amount: 2,
    rewardRep: 20,
    rewardItems: ['原石x35', '尸气丹x2'],
    minRep: -10,
  ),
  BountyQuest(
    qid: 'bq_heiya_002',
    title: '搜寻沼铁原矿',
    desc: '黑崖寨工匠铸造蛊兵，急需沼铁原矿 4 块。',
    faction: Faction.heiya,
    type: 'gather',
    target: '沼铁原矿',
    amount: 4,
    rewardRep: 12,
    rewardItems: ['锈蚀蛊料x2', '原石x20'],
    minRep: -30,
  ),
  BountyQuest(
    qid: 'bq_sanxiu_001',
    title: '猎捕异兽·青纹豹',
    desc: '散修蛊师收妖丹，青纹豹出没于南疆丘陵。',
    faction: Faction.sanxiu,
    type: 'kill',
    target: 'qingwen_panther',
    amount: 1,
    rewardRep: 8,
    rewardItems: ['原石x60', '豹魄晶x1'],
    minRep: -50,
  ),
  BountyQuest(
    qid: 'bq_sanxiu_002',
    title: '寻回散修遗失蛊囊',
    desc: '采集 3 枚“石壳菌”（生长于岩缝），换其线索酬金。',
    faction: Faction.sanxiu,
    type: 'gather',
    target: '石壳菌',
    amount: 3,
    rewardRep: 6,
    rewardItems: ['原石x25'],
    minRep: -80,
  ),
];

/// 悬赏榜工具。
class BountyBoard {
  static Map<String, dynamic> _raw(Player p) {
    final raw = p.flags['trade_v2'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static void _save(Player p, Map<String, dynamic> m) {
    p.flags['trade_v2'] = m;
  }

  /// 已接取悬赏 ID 集合。
  static Set<String> _acceptedIds(Player p) {
    final raw = _raw(p);
    final arr = raw['accepted_bounties'];
    if (arr is List) {
      return arr.map((e) => e is Map ? (e['qid'] ?? '').toString() : '').toSet();
    }
    return {};
  }

  /// 已完成（今日已交付）悬赏 ID 集合。
  static Set<String> _doneIds(Player p) {
    final raw = _raw(p);
    final arr = raw['done_bounties'];
    if (arr is List) return arr.map((e) => e.toString()).toSet();
    return {};
  }

  /// 玩家可浏览的悬赏列表（含内置 + 玩家自定义）。
  /// 每个 quest 带 status 字段：open / accepted / done。
  static List<BountyQuest> list(Player p) {
    final acc = _acceptedIds(p);
    final done = _doneIds(p);
    return _builtinBounties().map((q) {
      if (done.contains(q.qid)) return q.copyWith(status: 'done');
      if (acc.contains(q.qid)) return q.copyWith(status: 'accepted');
      return q.copyWith(status: 'open');
    }).toList();
  }

  /// 接取任务。
  static (bool, String) accept(Player p, BountyQuest q) {
    if (Reputation.of(p, q.faction) < q.minRep) {
      final fname = Faction.names[q.faction] ?? q.faction;
      return (false, '$fname声望不足（需 >= ${q.minRep}，当前 ${Reputation.of(p, q.faction)}），无法接取。');
    }
    final acc = _acceptedIds(p);
    if (acc.contains(q.qid)) return (false, '你已接取该悬赏。');
    if (acc.length >= 3) return (false, '最多同时接取 3 条悬赏（当前 ${acc.length}）。');
    // 加入接取列表
    final m = _raw(p);
    final arr = List<Map<String, dynamic>>.from(
        (m['accepted_bounties'] as List? ?? []).whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)));
    if (!arr.any((e) => e['qid'] == q.qid)) {
      arr.add(q.toJson());
    }
    m['accepted_bounties'] = arr;
    _save(p, m);
    return (true, '已接取悬赏【${q.title}】。目标：${q.type == 'kill' ? '击杀' : '采集'} ${q.target} x${q.amount}。');
  }

  /// 辅助：读取玩家某材料实际数量。
  static int _matCount(Player p, String name) {
    for (final it in p.inventory) {
      final (n, c) = MatParser.parse(it);
      if (n == name) return c;
    }
    return 0;
  }

  /// 辅助：读取玩家今日击杀某 nid 数。（简化：从 flags.kills_$nid 读，否则 0）
  /// 未实装击杀计数则按 0，玩家需自行确保采集类型提交的准确性。
  static int _killCount(Player p, String nid) {
    final raw = p.flags['kill_counts'];
    if (raw is Map) return ((raw[nid] as num?) ?? 0).toInt();
    return 0;
  }

  /// 提交/完成检查：返回 (ok, logs, rewards{name:count})。
  /// rewards 中列出奖励，供调用端发放。
  static (bool, List<String>, Map<String, int>) submit(Player p, BountyQuest q) {
    final logs = <String>[];
    final rewards = <String, int>{};
    final acc = _acceptedIds(p);
    if (!acc.contains(q.qid)) {
      logs.add('尚未接取悬赏【${q.title}】，请先 bountyaccept。');
      return (false, logs, rewards);
    }
    final done = _doneIds(p);
    if (done.contains(q.qid)) {
      logs.add('【${q.title}】今日已交付，明日再试。');
      return (false, logs, rewards);
    }
    // 采集类：扣除材料
    if (q.type == 'gather') {
      final have = _matCount(p, q.target);
      if (have < q.amount) {
        logs.add('进度不足：需 ${q.target} x${q.amount}，你仅有 $have。请继续采集。');
        return (false, logs, rewards);
      }
      // 扣除
      int left = q.amount;
      final newInv = <String>[];
      for (final it in p.inventory) {
        final (n, c) = MatParser.parse(it);
        if (n == q.target && left > 0) {
          final take = left < c ? left : c;
          left -= take;
          final remain = c - take;
          if (remain > 0) newInv.add(remain > 1 ? '${n}x$remain' : n);
        } else {
          newInv.add(it);
        }
      }
      p.inventory = newInv;
    } else {
      // kill 类：检查数量
      final have = _killCount(p, q.target);
      if (have < q.amount) {
        logs.add('击杀进度不足：需击杀 ${q.target} x${q.amount}，当前 $have。');
        return (false, logs, rewards);
      }
    }
    // 发放奖励声望
    Reputation.add(p, q.faction, q.rewardRep);
    logs.add('【悬赏完成】${q.title}！');
    final fname = Faction.names[q.faction] ?? q.faction;
    logs.add('  $fname 声望 +${q.rewardRep}。');
    // 发放奖励物品（解析 rewardItems）
    for (final it in q.rewardItems) {
      final (n, c) = MatParser.parse(it);
      rewards[n] = (rewards[n] ?? 0) + c;
      logs.add('  获得：$n x$c。');
    }
    // 从接取移除；加入今日已完成
    final m = _raw(p);
    final arr = List<Map<String, dynamic>>.from(
        (m['accepted_bounties'] as List? ?? []).whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)));
    arr.removeWhere((e) => e['qid'] == q.qid);
    m['accepted_bounties'] = arr;
    final doneArr = List<String>.from((m['done_bounties'] as List? ?? []).whereType<String>());
    if (!doneArr.contains(q.qid)) doneArr.add(q.qid);
    m['done_bounties'] = doneArr;
    _save(p, m);
    return (true, logs, rewards);
  }
}

// ---------- 以物易物 ----------
class Barter {
  /// 简单估值（参考价/价值指数）：若有 materials[name].price 用之，否则按常见材料估值。
  static int _estimate(String name, int count, Map<String, dynamic> materials) {
    final m = materials[name];
    int price = 1;
    if (m is Map) {
      price = ((m['price'] as num?) ?? 1).toInt();
    } else {
      // 常见材料 fallback
      if (name == '原石') price = 1;
      else if (name.contains('蛊')) price = 80;
      else if (name.contains('丹') || name.contains('散')) price = 40;
      else if (name.contains('矿') || name.contains('铁')) price = 20;
      else if (name.contains('草') || name.contains('花')) price = 5;
      else price = 3;
    }
    return price * count;
  }

  /// 谈判成功率：offer_value / want_value 比值 + 玩家 luck + 商人阵营声望影响。
  static double successChance(int offerVal, int wantVal, int luck, int factionRep) {
    if (wantVal <= 0) return 0;
    final ratio = offerVal / wantVal;
    final r = ratio * 0.7 + (luck / 100) * 0.1 + (factionRep / 200) * 0.2;
    return r.clamp(0.05, 0.95);
  }

  /// 执行以物易物：
  ///   giveMat: 玩家给出 {name:count}
  ///   wantMat: 玩家想要 {name:count}（仅支持 1 种 wanted 便于 UI）
  ///   faction: 商人所属势力（影响成功率声望加成），默认散修。
  ///   materials: 全局材料信息映射，用于估值；可传 <String, dynamic>{}（走 fallback）。
  static (bool, List<String>) trade(Player p, {
    required Map<String, int> giveMat,
    required Map<String, int> wantMat,
    String faction = 'sanxiu',
    Map<String, dynamic>? materials,
  }) {
    final mats = materials ?? <String, dynamic>{};
    final logs = <String>[];
    if (giveMat.isEmpty || wantMat.isEmpty) {
      return (false, ['需指定出价与想要的物资。']);
    }
    // 检查玩家有足够 giveMat
    for (final e in giveMat.entries) {
      int have = 0;
      for (final it in p.inventory) {
        final (n, c) = MatParser.parse(it);
        if (n == e.key) { have = c; break; }
      }
      if (have < e.value) {
        logs.add('物资不足：出价 ${e.key} x${e.value}，你仅有 $have。');
        return (false, logs);
      }
    }
    int offerVal = 0;
    for (final e in giveMat.entries) {
      offerVal += _estimate(e.key, e.value, mats);
    }
    int wantVal = 0;
    for (final e in wantMat.entries) {
      wantVal += _estimate(e.key, e.value, mats);
    }
    if (offerVal <= 0 || wantVal <= 0) {
      logs.add('价值无法估算，交易失败。');
      return (false, logs);
    }
    final giveStr = giveMat.entries.map((e) => '${e.key}x${e.value}').join(' + ');
    final wantStr = wantMat.entries.map((e) => '${e.key}x${e.value}').join(' + ');
    logs.add('你提出以 $giveStr（估值 $offerVal 原石）换取 $wantStr（估值 $wantVal 原石）。');
    final rep = Reputation.of(p, faction);
    final chance = successChance(offerVal, wantVal, p.luck, rep);
    logs.add('  谈判成功率：${(chance * 100).round()}%（含幸运 ${p.luck} 与 ${Faction.names[faction] ?? faction} 声望 $rep 加成）。');
    if (_rng.nextDouble() < chance) {
      logs.add('【以物易物·成功】商人沉吟片刻，接受了你的提议。');
      return (true, logs);
    } else {
      logs.add('【以物易物·失败】商人摇了摇头，露出不屑的神色，不肯成交。');
      return (false, logs);
    }
  }
}
