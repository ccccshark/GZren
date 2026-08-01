// quest_model.dart
// V1.4 新增【主线/支线/循环委托任务系统】数据模型。
// 任务类型：main(主线)/side(支线)/loop(循环委托，可重复)。
// 目标类型：talk_npc/collect_item/kill_npc_count/own_gu_by_gid。
// 状态持久化于 player.flags['quest_states']，旧存档无此字段自动填充空 map，不报错。
class Quest {
  final String qid;
  final String name;
  final String type; // main / side / loop
  final String chain; // 主线链 ID（仅主线）
  final int chainStep;
  final int minRank;
  final bool autoAccept; // 进入满足条件场景自动接取
  final bool repeatable; // 循环委托可重复
  final int cooldownMinute; // 循环委托冷却（游戏时间分钟）
  final String desc;
  final String endingNote; // 完成后展示的结束语（伏笔等）
  final Map<String, dynamic> objective;
  final Map<String, dynamic> reward;
  final String nextQid; // 完成后自动接取的下一个任务

  Quest({
    required this.qid,
    required this.name,
    this.type = 'side',
    this.chain = '',
    this.chainStep = 0,
    this.minRank = 1,
    this.autoAccept = false,
    this.repeatable = false,
    this.cooldownMinute = 0,
    this.desc = '',
    this.endingNote = '',
    this.objective = const {},
    this.reward = const {},
    this.nextQid = '',
  });

  factory Quest.fromJson(Map<String, dynamic> j) => Quest(
        qid: j['qid'] ?? '',
        name: j['name'] ?? '',
        type: j['type'] ?? 'side',
        chain: j['chain'] ?? '',
        chainStep: j['chain_step'] ?? 0,
        minRank: j['min_rank'] ?? 1,
        autoAccept: j['auto_accept'] ?? false,
        repeatable: j['repeatable'] ?? false,
        cooldownMinute: j['cooldown_minute'] ?? 0,
        desc: j['desc'] ?? '',
        endingNote: j['ending_note'] ?? '',
        objective: Map<String, dynamic>.from(j['objective'] ?? const {}),
        reward: Map<String, dynamic>.from(j['reward'] ?? const {}),
        nextQid: j['next_qid'] ?? '',
      );
}

/// 单个任务的运行时状态。序列化到 player.flags['quest_states'][qid]。
class QuestState {
  String qid;
  String status; // active / completed / turned_in / locked
  int progress; // 通用进度计数（kill_npc_count 使用）
  double acceptedMinute; // 接取时的游戏时间（分钟），用于循环冷却
  double completedMinute; // 完成时间
  Map<String, int> killCounters; // npc_id -> 已击杀数

  QuestState({
    required this.qid,
    this.status = 'locked',
    this.progress = 0,
    this.acceptedMinute = 0,
    this.completedMinute = 0,
    Map<String, int>? killCounters,
  }) : killCounters = killCounters ?? {};

  Map<String, dynamic> toJson() => {
        'status': status,
        'progress': progress,
        'accepted_minute': acceptedMinute,
        'completed_minute': completedMinute,
        'kill_counters': killCounters,
      };

  factory QuestState.fromJson(String qid, Map<String, dynamic> j) => QuestState(
        qid: qid,
        status: j['status'] ?? 'locked',
        progress: j['progress'] ?? 0,
        acceptedMinute: (j['accepted_minute'] ?? 0).toDouble(),
        completedMinute: (j['completed_minute'] ?? 0).toDouble(),
        killCounters: Map<String, int>.from(
            (j['kill_counters'] ?? {}).map((k, v) => MapEntry(k, (v as num).toInt()))),
      );
}
