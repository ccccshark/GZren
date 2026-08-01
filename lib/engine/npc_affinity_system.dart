// npc_affinity_system.dart
// V1.4 新增【NPC好感度完整剧情分支、专属情报、专属蛊方兑换】。
// 好感度持久化于 player.flags['npc_affinity'][nid]，范围 -100~100。
// 旧存档无此字段自动填充 0，不报错。
// 与对话系统联动：好感度达到阈值时解锁专属剧情分支、情报提示、蛊方兑换。
import '../data_model/player_model.dart';
import 'gu_system.dart' show addMaterial;

class NpcAffinity {
  /// 读取玩家对某 NPC 的好感度（旧存档默认 0）。
  static int get(Player p, String nid) {
    final raw = p.flags['npc_affinity'];
    if (raw is! Map) return 0;
    final v = raw[nid];
    if (v is num) return v.toInt().clamp(-100, 100);
    return 0;
  }

  /// 增减好感度（自动 clamp 到 -100~100）。返回变动后的值。
  static int add(Player p, String nid, int delta) {
    final raw = p.flags['npc_affinity'];
    final Map<String, dynamic> m = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final cur = ((m[nid] as num?) ?? 0).toInt().clamp(-100, 100);
    final nv = (cur + delta).clamp(-100, 100);
    m[nid] = nv;
    p.flags['npc_affinity'] = m;
    return nv;
  }

  /// 好感度等级标签。
  static String levelLabel(int affinity) {
    if (affinity >= 80) return '莫逆之交';
    if (affinity >= 50) return '挚友';
    if (affinity >= 20) return '友善';
    if (affinity >= -20) return '普通';
    if (affinity >= -50) return '冷淡';
    if (affinity >= -80) return '敌视';
    return '仇敌';
  }

  /// 与 NPC 对话时，根据好感度返回专属剧情分支 / 情报 / 兑换提示。
  /// 返回的字符串列表会追加到对话日志输出。
  static List<String> onTalk(Player p, String nid, String npcName) {
    final out = <String>[];
    final aff = get(p, nid);
    final label = levelLabel(aff);
    out.add('〔好感度·$label ($aff)〕');

    // 按 NPC 解锁专属内容
    if (nid == 'npc_xisha_hermit') {
      // 西漠隐士：好感度越高，透露越多西漠线索
      if (aff >= 20) {
        out.add('$npcName：风行蛊蛊方在万毒蟒君身上，沙遁蛊蛊方在古蛊师残魂手中——此乃公开的秘密。');
      }
      if (aff >= 50) {
        out.add('$npcName：炼制双蛊需在特定环境——风行蛊需晴朗天气，沙遁蛊需凌晨时段，切记。');
      }
      if (aff >= 80) {
        out.add('$npcName：集齐双蛊后，西漠禁制自破。但西漠凶险万分，非六转以上不可深入。望你珍重。');
      }
    } else if (nid == 'npc_blackmarket_broker') {
      // 黑市掮客：好感度解锁专属蛊方兑换
      if (aff >= 20) {
        out.add('$npcName：嘿，看在咱们熟络的份上，告诉你个消息——血煞宗主身上有冥血蛊蛊方。');
      }
      if (aff >= 50) {
        out.add('$npcName：你若帮我跑腿，我可低价卖你高阶蛊方。quest accept 黑市·掮客的委托 试试？');
      }
      if (aff >= 80) {
        out.add('$npcName：莫逆之交！这枚风行蛊蛊方残片送你了，算老哥一点心意。');
        // 好感度达 80 时一次性赠送风行蛊蛊方残片（通过 flag 防重复）
        final given = (p.flags['broker_gift_given'] as num?)?.toInt() ?? 0;
        if (given == 0) {
          addMaterial(p, '风行蛊蛊方残片', 1);
          p.flags['broker_gift_given'] = 1;
          out.add('  （获得：风行蛊蛊方残片 ×1）');
        }
      }
    } else if (nid == 'npc_trader_lao') {
      // 老槐翁：好感度解锁专属情报
      if (aff >= 20) {
        out.add('老槐翁：青茅山近来有魔修出没，听说血煞宗在南疆立了分舵，你可要当心。');
      }
      if (aff >= 50) {
        out.add('老槐翁：黑崖寨背后有处万丈深渊，崖底藏有鬼道秘境，老朽年轻时曾见过鬼火磷磷。');
      }
    }
    return out;
  }

  /// 对话后小幅提升好感度（每次 +1，上限友善）。
  /// 战斗胜利对中立NPC会降低好感度（在 command.dart 中调用）。
  static void onTalkEnd(Player p, String nid) {
    final cur = get(p, nid);
    if (cur < 50) {
      add(p, nid, 1);
    }
  }

  /// 完成该NPC发布的任务后大幅提升好感度。
  static void onQuestTurnIn(Player p, String nid, int amount) {
    add(p, nid, amount);
  }
}
