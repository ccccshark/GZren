// npc_ai.dart
// NPC 独立 AI 循环：采集、修炼、互相厮杀、伏击玩家、重生。
import 'dart:math';
import 'package:gzren/data_model/npc_model.dart';
import 'package:gzren/data_model/scene_model.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/gu_model.dart';
import 'world_timer.dart';
import 'player_core.dart' show levelRank;

final _rng = Random();

Map<String, Npc> spawnNpcs(List<NpcTemplate> templates, Map<String, Room> rooms) {
  final npcs = <String, Npc>{};
  final tmplMap = {for (var t in templates) t.nid: t};
  for (final entry in rooms.entries) {
    for (final nid in entry.value.npcList) {
      if (tmplMap.containsKey(nid) && !npcs.containsKey(nid)) {
        final npc = Npc.fromTemplate(tmplMap[nid]!);
        npc.homeRid = entry.key;
        npc.storeOriginals();
        npcs[nid] = npc;
      }
    }
  }
  return npcs;
}

List<Npc> npcsInRoom(Map<String, Npc> npcs, String rid) =>
    npcs.values.where((n) => n.alive && n.homeRid == rid).toList();

class NPCAI {
  final Map<String, GuTemplate> guList;
  NPCAI(this.guList);

  void tick(Map<String, Npc> npcs, Player player, Map<String, Room> rooms,
      List<String> log, WorldTimer worldTimer, {bool allowAmbush = false}) {
    // 同场景敌对异兽互斗
    final seenRooms = <String>{};
    for (final npc in npcs.values) {
      if (npc.alive && npc.isHostile && !seenRooms.contains(npc.homeRid)) {
        seenRooms.add(npc.homeRid!);
        _resolveRoomBrawl(npcs, npc.homeRid!, player.worldTime, log);
      }
    }
    for (final npc in npcs.values) {
      if (!npc.alive) {
        if (npc.deathTime != null && player.worldTime - npc.deathTime! >= 24) {
          npc.respawn();
          log.add('${npc.name} 在 ${rooms[npc.homeRid]?.name ?? ''} 重新出没。');
        }
        continue;
      }
      if (npc.isMerchant) continue;
      _act(npc, player, rooms, log, worldTimer, allowAmbush);
    }
  }

  void _act(Npc npc, Player player, Map<String, Room> rooms, List<String> log,
      WorldTimer worldTimer, bool allowAmbush) {
    final room = rooms[npc.homeRid];
    if (room == null) return;
    if (player.location == npc.homeRid && npc.isHostile) {
      if (allowAmbush && _rng.nextDouble() < 0.30 + npc.hatePlayer * 0.1) {
        _ambush(npc, player, log, worldTimer);
        return;
      }
      npc.lastAction = 'lurk';
      return;
    }
    final roll = _rng.nextDouble();
    if (roll < 0.45 && room.refreshResource.isNotEmpty) {
      final res = room.refreshResource[_rng.nextInt(room.refreshResource.length)];
      npc.inventory.add('${res}x1');
      npc.lastAction = '采集:$res';
    } else if (roll < 0.65) {
      npc.trueyuan = min(npc.trueyuanMax, npc.trueyuan + 5);
      npc.physique = min(npc.physiqueMax, npc.physique + 2);
      npc.lastAction = '修炼';
    } else {
      npc.lastAction = '巡猎';
    }
  }

  void _ambush(Npc npc, Player player, List<String> log, WorldTimer worldTimer) {
    final pRank = levelRank(player.level);
    final nRank = levelRank(npc.level);
    int power = 10;
    for (final gid in npc.guInSlot) {
      final t = guList[gid];
      if (t != null && (t.combat['power'] as num? ?? 0) > power) {
        power = (t.combat['power'] as num).toInt();
      }
    }
    var dmg = (power * (1 + max(0, nRank - pRank) * 0.2)).toInt();
    final defense = (player.physique * 0.1).toInt();
    dmg = max(1, dmg - defense);
    player.physique = max(0, player.physique - dmg);
    npc.hatePlayer += 1;
    log.add('⚠ ${npc.name} 突然向你发难伏击，造成 $dmg 点伤害！');
    worldTimer.advance(player, 1, log);
    if (player.physique <= 0) {
      player.alive = false;
      log.add('【伏击致命】你被异兽伏击身亡……');
    }
  }

  void _resolveRoomBrawl(Map<String, Npc> npcs, String rid, double worldTime, List<String> log) {
    final here = npcs.values
        .where((n) => n.alive && n.homeRid == rid && n.isHostile)
        .toList();
    if (here.length < 2) return;
    final a = here[0], b = here[1];
    final pa = a.physique + a.guInSlot.fold(0, (s, g) => s + _guPower(g));
    final pb = b.physique + b.guInSlot.fold(0, (s, g) => s + _guPower(g));
    final winner = pa >= pb ? a : b;
    final loser = pa >= pb ? b : a;
    loser.alive = false;
    loser.deathTime = worldTime;
    winner.inventory.addAll(loser.inventory);
    for (final g in List<String>.from(loser.guInSlot)) {
      if (_rng.nextDouble() < 0.4) {
        winner.guInSlot.add(g);
        loser.guInSlot.remove(g);
      }
    }
    loser.inventory.clear();
    log.add('${winner.name} 与 ${loser.name} 厮杀，${loser.name} 被击杀。');
  }

  int _guPower(String gid) {
    final t = guList[gid];
    if (t == null) return 10;
    return (t.combat['power'] as num? ?? 0).toInt() + t.rank * 5;
  }
}
