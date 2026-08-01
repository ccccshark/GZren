// quest_system.dart
// V1.4 新增【主线/支线/循环委托任务系统】核心引擎。
// 任务状态全部持久化于 player.flags['quest_states']，旧存档自动填充空 map，不报错。
// 与 EnvironmentSystem 联动：循环委托冷却基于游戏时间分钟计算。
import '../data_model/player_model.dart';
import '../data_model/quest_model.dart';
import 'gu_system.dart' show countMaterial, consumeMaterial, addMaterial;
import 'player_core.dart' show levelRank;
import 'environment_system.dart' show EnvironmentSystem;

class QuestSystem {
  static List<Quest> quests = [];

  /// 加载静态任务配置（loadStatic 时调用，文件缺失时静默跳过）。
  static void load(List<dynamic> raw) {
    quests = raw
        .map((e) => Quest.fromJson(e as Map<String, dynamic>))
        .where((q) => q.qid.isNotEmpty)
        .toList();
  }

  /// 读取玩家任务状态表（旧存档自动初始化空表）。
  static Map<String, QuestState> states(Player p) {
    final raw = p.flags['quest_states'];
    if (raw is! Map) {
      p.flags['quest_states'] = <String, dynamic>{};
      return <String, QuestState>{};
    }
    final out = <String, QuestState>{};
    for (final e in raw.entries) {
      if (e.value is Map) {
        out[e.key as String] =
            QuestState.fromJson(e.key as String, e.value as Map<String, dynamic>);
      }
    }
    return out;
  }

  static void _save(Player p, Map<String, QuestState> st) {
    p.flags['quest_states'] = {for (final e in st.entries) e.key: e.value.toJson()};
  }

  static Quest? find(String qid) {
    for (final q in quests) {
      if (q.qid == qid) return q;
    }
    return null;
  }

  /// 接取任务。返回接取结果消息（用于日志输出）。
  static String accept(Player p, String qid) {
    final q = find(qid);
    if (q == null) return '未找到任务「$qid」。';
    final st = states(p);
    final cur = st[qid];
    if (cur != null && cur.status == 'active') return '任务「${q.name}」已在进行中。';
    if (cur != null && cur.status == 'completed' && !q.repeatable) {
      return '任务「${q.name}」已完成，不可重复。';
    }
    // 循环委托冷却校验
    if (q.repeatable && cur != null && cur.completedMinute > 0) {
      final now = EnvironmentSystem.gameMinute(p).toDouble();
      final elapsed = now - cur.completedMinute;
      if (elapsed < q.cooldownMinute) {
        final remain = q.cooldownMinute - elapsed.toInt();
        return '循环委托「${q.name}」冷却中，剩余约 $remain 分钟（游戏时间）。';
      }
    }
    st[qid] = QuestState(
      qid: qid,
      status: 'active',
      acceptedMinute: EnvironmentSystem.gameMinute(p).toDouble(),
    );
    _save(p, st);
    return '【接取任务】${q.name}\n${q.desc}';
  }

  /// 自动接取满足条件的主线任务（auto_accept=true）。
  /// 在玩家进入场景 / 升级时由 command.dart 调用。
  static List<String> autoAccept(Player p) {
    final out = <String>[];
    final st = states(p);
    final rank = levelRank(p.level);
    for (final q in quests) {
      if (!q.autoAccept) continue;
      if (q.minRank > rank) continue;
      final cur = st[q.qid];
      // 从未接取 / 已完成且可重复 → 自动接取
      if (cur == null || (q.repeatable && cur.status == 'turned_in')) {
        out.add(accept(p, q.qid));
      }
    }
    return out;
  }

  /// 记录击杀 NPC，推进 kill_npc_count 类任务进度。
  /// 返回触发完成提示的任务消息列表。
  static List<String> onKillNpc(Player p, String npcId) {
    final out = <String>[];
    final st = states(p);
    bool changed = false;
    for (final q in quests) {
      final cur = st[q.qid];
      if (cur == null || cur.status != 'active') continue;
      if (q.objective['type'] != 'kill_npc_count') continue;
      final target = q.objective['target'];
      if (target is! Map) continue;
      final need = (target[npcId] as num?)?.toInt() ?? 0;
      if (need <= 0) continue;
      cur.killCounters[npcId] = (cur.killCounters[npcId] ?? 0) + 1;
      changed = true;
      out.add('【任务进度】${q.name}：击杀 $npcId ${cur.killCounters[npcId]}/$need');
      if (_objectiveMet(p, q, cur)) {
        cur.status = 'completed';
        cur.completedMinute = EnvironmentSystem.gameMinute(p).toDouble();
        out.add('【任务完成】${q.name}！可前往任务面板领取奖励。');
      }
    }
    if (changed) _save(p, st);
    return out;
  }

  /// 记录与 NPC 对话，推进 talk_npc 类任务。
  static List<String> onTalkNpc(Player p, String npcId) {
    final out = <String>[];
    final st = states(p);
    bool changed = false;
    for (final q in quests) {
      final cur = st[q.qid];
      if (cur == null || cur.status != 'active') continue;
      if (q.objective['type'] != 'talk_npc') continue;
      if (q.objective['target'] != npcId) continue;
      cur.status = 'completed';
      cur.completedMinute = EnvironmentSystem.gameMinute(p).toDouble();
      changed = true;
      out.add('【任务完成】${q.name}！可前往任务面板领取奖励。');
    }
    if (changed) _save(p, st);
    return out;
  }

  /// 通用完成判定（采集/持有类任务由 turnIn 时实时判定，无需事件推送）。
  static bool _objectiveMet(Player p, Quest q, QuestState cur) {
    final type = q.objective['type'];
    if (type == 'talk_npc') return cur.status == 'completed';
    if (type == 'kill_npc_count') {
      final target = q.objective['target'];
      if (target is! Map) return false;
      for (final e in target.entries) {
        final need = (e.value as num).toInt();
        final have = cur.killCounters[e.key] ?? 0;
        if (have < need) return false;
      }
      return true;
    }
    if (type == 'collect_item') {
      final target = q.objective['target'];
      if (target is! Map) return false;
      for (final e in target.entries) {
        final need = (e.value as num).toInt();
        if (countMaterial(p, e.key as String) < need) return false;
      }
      return true;
    }
    if (type == 'own_gu_by_gid') {
      final target = q.objective['target'];
      if (target is! Map) return false;
      for (final e in target.entries) {
        final need = (e.value as num).toInt();
        final gid = e.key as String;
        int have = 0;
        for (final g in p.guInSlot) {
          if (g.gid == gid) have++;
        }
        for (final g in p.guBag) {
          if (g.gid == gid) have++;
        }
        if (have < need) return false;
      }
      return true;
    }
    return false;
  }

  /// 交付任务并发放奖励。返回结果消息。
  /// collect_item 类会消耗对应材料；kill_npc_count / talk_npc / own_gu_by_gid 不消耗。
  static String turnIn(Player p, String qid) {
    final q = find(qid);
    if (q == null) return '未找到任务「$qid」。';
    final st = states(p);
    final cur = st[qid];
    if (cur == null) return '任务「${q.name}」尚未接取。';
    if (cur.status == 'turned_in') {
      if (!q.repeatable) return '任务「${q.name}」已交付，不可重复。';
    }
    if (cur.status != 'completed' && cur.status != 'turned_in') {
      // 实时校验：可能玩家已满足但未触发事件完成标记
      if (_objectiveMet(p, q, cur)) {
        cur.status = 'completed';
      } else {
        return '任务「${q.name}」目标尚未达成，无法交付。';
      }
    }
    // 消耗采集类材料
    if (q.objective['type'] == 'collect_item') {
      final target = q.objective['target'];
      if (target is Map) {
        for (final e in target.entries) {
          final need = (e.value as num).toInt();
          if (!consumeMaterial(p, e.key as String, need)) {
            return '任务「${q.name}」交付失败：${e.key} 数量不足。';
          }
        }
      }
    }
    // 发放奖励
    final out = StringBuffer('【任务交付】${q.name} 完成！\n');
    final reward = q.reward;
    final rawMaterials = reward['原石'];
    if (rawMaterials is num && rawMaterials.toInt() > 0) {
      addMaterial(p, '原石', rawMaterials.toInt());
      out.writeln('  获得原石 ×${rawMaterials.toInt()}');
    }
    final flags = reward['flags'];
    if (flags is Map) {
      for (final e in flags.entries) {
        final cur2 = (p.flags[e.key] as num?)?.toInt() ?? 0;
        final add = (e.value as num).toInt();
        p.flags[e.key] = cur2 + add;
      }
      out.writeln('  声望/标记更新');
    }
    // 循环委托重置为可再次接取；非循环任务标记为已交付
    if (q.repeatable) {
      cur.status = 'turned_in';
      cur.killCounters.clear();
      cur.progress = 0;
    } else {
      cur.status = 'turned_in';
    }
    _save(p, st);
    // 自动接取下一个任务（主线链）
    if (q.nextQid.isNotEmpty) {
      final next = accept(p, q.nextQid);
      out.writeln(next);
    }
    if (q.endingNote.isNotEmpty) {
      out.writeln(q.endingNote);
    }
    return out.toString().trimRight();
  }

  /// 列出玩家所有任务的展示信息（任务面板用）。
  static List<Map<String, String>> overview(Player p) {
    final st = states(p);
    final out = <Map<String, String>>[];
    final rank = levelRank(p.level);
    for (final q in quests) {
      final cur = st[q.qid];
      String status;
      String progress = '';
      if (cur == null) {
        status = (q.minRank > rank) ? 'locked' : 'available';
      } else {
        status = cur.status;
      }
      // 计算进度文本
      if (cur != null && cur.status == 'active') {
        final type = q.objective['type'];
        if (type == 'kill_npc_count') {
          final target = q.objective['target'];
          if (target is Map) {
            final parts = <String>[];
            for (final e in target.entries) {
              final have = cur.killCounters[e.key] ?? 0;
              final need = (e.value as num).toInt();
              parts.add('$have/$need');
            }
            progress = parts.join(' ');
          }
        } else if (type == 'collect_item') {
          final target = q.objective['target'];
          if (target is Map) {
            final parts = <String>[];
            for (final e in target.entries) {
              final have = countMaterial(p, e.key as String);
              final need = (e.value as num).toInt();
              parts.add('$have/$need');
            }
            progress = parts.join(' ');
          }
        }
      }
      out.add({
        'qid': q.qid,
        'name': q.name,
        'type': q.type,
        'status': status,
        'progress': progress,
        'desc': q.desc,
      });
    }
    return out;
  }
}
