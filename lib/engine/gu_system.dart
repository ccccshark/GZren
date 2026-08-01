// gu_system.dart
// 蛊虫系统：蛊实例生成、捕捉、炼蛊、投喂、装备/取出、催动。
import 'dart:math';
import 'package:gzren/data_model/gu_model.dart';
import 'package:gzren/data_model/recipe_model.dart';
import 'package:gzren/data_model/player_model.dart';
import 'package:gzren/data_model/scene_model.dart';
import 'package:gzren/data_model/slot_capacity_model.dart' show SlotCapacity; // 第二阶段：空窍容量
import 'package:gzren/data_model/storage_gu_model.dart' show StorageGu;    // 第二阶段：储物蛊容量
import 'player_core.dart' show levelRank;
import 'poison_system.dart' show PoisonSystem;

final _rng = Random();

GuInstance makeGuInstance(String gid, Map<String, GuTemplate> guList,
    {int? durability, bool mutated = false}) {
  final t = guList[gid];
  if (t == null) return GuInstance(
      instId: '', gid: gid, name: '未知蛊', rank: 1, school: '气道',
      durabilityMax: 100, durability: 100);
  final durMax = t.durabilityMax;
  var name = t.name;
  var sideEffect = t.sideEffect;
  Map<String, dynamic> combat = Map<String, dynamic>.from(t.combat);
  if (mutated) {
    name = '变异·$name';
    final power = (combat['power'] as num? ?? 0).toInt();
    if (power > 0) combat['power'] = (power * 1.4).toInt();
    sideEffect = '变异反噬：$sideEffect';
  }
  return GuInstance(
    instId: _rng.nextInt(0xffffff).toRadixString(16),
    gid: gid,
    name: name,
    rank: t.rank,
    school: t.school,
    costZhen: t.costZhen,
    costLife: t.costLife,
    durabilityMax: durMax,
    durability: durability ?? durMax,
    feedMaterial: t.feedMaterial,
    sideEffect: sideEffect,
    combat: combat,
    mutated: mutated,
  );
}

// ---------- 背包材料 ----------
bool hasMaterial(Player p, String name, int count) =>
    countMaterial(p, name) >= count;

int countMaterial(Player p, String name) {
  int total = 0;
  for (final it in p.inventory) {
    final (n, c) = MatParser.parse(it);
    if (n == name) total += c;
  }
  return total;
}

bool consumeMaterial(Player p, String name, int count) {
  int need = count;
  final newInv = <String>[];
  for (final it in p.inventory) {
    final (n, c) = MatParser.parse(it);
    if (n == name && need > 0) {
      if (c <= need) {
        need -= c;
        continue;
      } else {
        final remain = c - need;
        newInv.add(remain > 1 ? '${name}x$remain' : name);
        need = 0;
      }
    } else {
      newInv.add(it);
    }
  }
  if (need > 0) return false;
  p.inventory = newInv;
  return true;
}

void addMaterial(Player p, String name, int count) {
  if (count <= 0) return;
  // 第二阶段：储物蛊容量检查（仅严格模式）
  if (StorageGu.strictMode(p)) {
    final (ok, reason) = StorageGu.canAdd(p, name, count);
    if (!ok) {
      // 容量已满：仅在可观察位置提示（不阻断已有逻辑，避免破坏旧存档）
      // 但为保证规则一致，不新增堆叠（已有同名仍可合并）。
      // 先尝试合并：
      for (var i = 0; i < p.inventory.length; i++) {
        final (n, c) = MatParser.parse(p.inventory[i]);
        if (n == name) {
          final total = c + count;
          p.inventory[i] = total > 1 ? '${name}x$total' : name;
          return;
        }
      }
      // 无同名且容量不足：丢弃多余物资
      return;
    }
  } else {
    // 首次启用严格模式（添加物资时触发）
    StorageGu.ensureStrictMode(p);
  }
  // 原有逻辑
  for (var i = 0; i < p.inventory.length; i++) {
    final (n, c) = MatParser.parse(p.inventory[i]);
    if (n == name) {
      final total = c + count;
      p.inventory[i] = total > 1 ? '${name}x$total' : name;
      return;
    }
  }
  p.inventory.add(count > 1 ? '${name}x$count' : name);
}

// ---------- 捕捉野蛊 ----------
List<String> capture(Player p, String targetGid,
    Map<String, GuTemplate> guList, Room room, {double chanceMul = 1.0}) {
  final log = <String>[];
  final wild = room.wildGu;
  if (!wild.contains(targetGid)) {
    log.add('这里没有这种野生蛊虫：$targetGid');
    return log;
  }
  final t = guList[targetGid]!;
  final pRank = levelRank(p.level);
  if (t.rank > pRank) {
    log.add('${t.name}（${t.rank}转）境界高于你，无法捕捉！');
    return log;
  }
  final cost = 10 + t.rank * 5;
  if (p.trueyuan < cost) {
    log.add('真元不足，捕捉需 $cost 真元。');
    return log;
  }
  p.spendTrueyuan(cost);
  double base = 0.5 - max(0, t.rank - pRank + 1) * 0.1 + p.luck * 0.005;
  base = base.clamp(0.1, 0.85).toDouble();
  // V1.3 新增【环境联动】：昼夜/天气影响捕捉成功率（夜间/浓雾降低）。
  base *= chanceMul;
  base = base.clamp(0.05, 0.85).toDouble();
  if (_rng.nextDouble() < base) {
    final inst = makeGuInstance(targetGid, guList);
    p.guBag.add(inst);
    log.add('【捕捉成功】你捕捉到一只 ${inst.name}！已存入背包寄存蛊虫。');
    wild.remove(targetGid);
  } else {
    log.add('捕捉失败，${t.name} 逃脱了，你的真元白费 $cost 点。');
  }
  return log;
}

// ---------- 炼蛊 ----------
List<String> refine(Player p, String recipeName, List<Recipe> recipes,
    Map<String, GuTemplate> guList) {
  final log = <String>[];
  Recipe? recipe;
  for (final r in recipes) {
    if (r.name == recipeName) {
      recipe = r;
      break;
    }
  }
  if (recipe == null) {
    log.add('不存在蛊方：$recipeName');
    return log;
  }
  if (!p.inventory.contains(recipe.name)) {
    log.add('你未持有 ${recipe.name}，无法炼制！需先获得蛊方。');
    return log;
  }
  final needed = <(String, int)>[];
  for (final m in recipe.material) {
    final (n, c) = MatParser.parse(m);
    if (!hasMaterial(p, n, c)) {
      log.add('蛊材不足：缺少 ${n}x$c');
      return log;
    }
    needed.add((n, c));
  }
  for (final (n, c) in needed) {
    consumeMaterial(p, n, c);
  }
  final rankPen = recipe.rank * 0.05;
  double success = recipe.baseSuccess + p.refineProficiency * 0.02 - rankPen;
  success = success.clamp(0.05, 0.95).toDouble();
  if (_rng.nextDouble() < success) {
    bool mutated = false;
    // V1.4 新增【蛊虫变异机制】：基础变异概率3%；若输出蛊 is_mutate=true，变异概率提升至15%。
    final outT = guList[recipe.outputGid];
    final mutateChance = (outT?.isMutate ?? false) ? 0.15 : 0.03;
    if (recipe.rank >= 1 && recipe.rank <= 7 && _rng.nextDouble() < mutateChance) {
      mutated = true;
    }
    final inst = makeGuInstance(recipe.outputGid, guList, mutated: mutated);
    p.guBag.add(inst);
    p.refineProficiency += 1;
    log.add('【炼蛊成功】你炼制出 ${inst.name}！（成功率 ${(success * 100).round()}%）');
    if (mutated) {
      log.add('异变突生——竟炼出一只变异蛊！威力大增，但反噬更深。');
      if (outT?.isMutate ?? false) {
        log.add('此蛊本就易生异变，变异尤为剧烈。');
      }
    }
  } else {
    log.add('【炼蛊失败】材料尽毁……（成功率 ${(success * 100).round()}%）');
    if (_rng.nextDouble() < 0.3) {
      final dmg = 5 + recipe.rank * 4;
      p.physique = max(1, p.physique - dmg);
      p.addInjure('炸伤');
      log.add('蛊材爆炸！你被炸伤，体魄 -$dmg，新增伤势：炸伤。');
    }
    p.refineProficiency += 0.2;
  }
  return log;
}

// ---------- 投喂 ----------
List<String> feed(Player p, String guName, String materialName) {
  final log = <String>[];
  GuInstance? target = _findGu(p, guName);
  if (target == null) {
    log.add('你未拥有名为 $guName 的蛊虫。');
    return log;
  }
  if (!target.feedMaterial.contains(materialName)) {
    log.add('${target.name} 不吃 $materialName，它只进食：${target.feedMaterial.join('、')}。');
    return log;
  }
  if (!hasMaterial(p, materialName, 1)) {
    log.add('背包中没有 $materialName。');
    return log;
  }
  consumeMaterial(p, materialName, 1);
  const recover = 30;
  target.durability = min(target.durabilityMax, target.durability + recover);
  log.add('你投喂 $materialName 给 ${target.name}，耐久恢复 $recover（当前 ${target.durability}/${target.durabilityMax}）。');
  return log;
}

// ---------- 装备/取出 ----------
List<String> equip(Player p, String guName) {
  final log = <String>[];
  if (p.freeSlotCount <= 0) {
    log.add('空窍已满！有效蛊槽上限 ${p.effectiveSlotMax}，无法再装备。');
    return log;
  }
  GuInstance? target;
  for (final g in p.guBag) {
    if (g.name == guName || g.instId == guName) {
      target = g;
      break;
    }
  }
  if (target == null) {
    log.add('背包寄存蛊虫中没有 $guName。');
    return log;
  }
  // 第二阶段：空窍容量检查
  final (okCap, reasonCap) = SlotCapacity.canEquip(p, target);
  if (!okCap) {
    log.add(reasonCap);
    return log;
  }
  p.guBag.remove(target);
  p.guInSlot.add(target);
  if (target.gid == 'g015') {
    p.slotBonus += 1;
    log.add('${target.name} 安入空窍，蛊槽上限 +1（当前有效上限 ${p.effectiveSlotMax}）。');
  } else {
    // 第二阶段：显示容量
    final capMsg = SlotCapacity.strictMode(p)
        ? ' 空窍容量 ${SlotCapacity.usedCapacity(p)}/${SlotCapacity.capacityMax(p)}。'
        : '';
    log.add('${target.name} 已安入空窍。空窍剩余 ${p.freeSlotCount} 槽。$capMsg');
  }
  return log;
}

List<String> unequip(Player p, String guName) {
  final log = <String>[];
  GuInstance? target;
  for (final g in p.guInSlot) {
    if (g.name == guName || g.instId == guName) {
      target = g;
      break;
    }
  }
  if (target == null) {
    log.add('空窍中没有 $guName。');
    return log;
  }
  p.guInSlot.remove(target);
  p.guBag.add(target);
  if (target.gid == 'g015') {
    p.slotBonus = max(0, p.slotBonus - 1);
    log.add('${target.name} 取出空窍，蛊槽上限 -1。');
  } else {
    log.add('${target.name} 已取出空窍，存入背包。');
  }
  return log;
}

// ---------- 催动（非战斗） ----------
List<String> useGu(Player p, String guName) {
  final log = <String>[];
  GuInstance? target;
  for (final g in p.guInSlot) {
    if (g.name == guName || g.instId == guName) {
      target = g;
      break;
    }
  }
  if (target == null) {
    log.add('空窍中没有 $guName，无法催动。需先 equip 装入空窍。');
    return log;
  }
  if (target.durability <= 0) {
    log.add('${target.name} 耐久耗尽，无法催动，请先投喂。');
    return log;
  }
  if (p.trueyuan < target.costZhen) {
    log.add('真元不足，催动 ${target.name} 需 ${target.costZhen} 真元。');
    return log;
  }
  p.spendTrueyuan(target.costZhen);
  target.durability = max(0, target.durability - 2);
  final ctype = target.combat['type'] ?? 'passive';
  final power = (target.combat['power'] as num? ?? 0).toInt();

  switch (ctype) {
    case 'heal_zhen':
      p.recoverTrueyuan(power);
      log.add('你催动 ${target.name}，恢复 $power 真元。');
      break;
    case 'heal_body':
      p.physique = min(p.physique + power, 200);
      p.healInjure('轻伤');
      log.add('你催动 ${target.name}，体魄恢复 $power。');
      break;
    case 'detox':
      // 解毒蛊（主流解毒手段）：低阶(rank<=2)仅解 fierce；中阶(rank 3-4)可解 odd；高阶(rank>=5)可解 dao
      // 强力解毒蛊(rank>=3)催动会消耗气血真元。凡蛊绝对无法解道毒。
      final detoxRank = target.rank;
      final detoxLogs = PoisonSystem.detoxByGu(p, detoxRank, power);
      log.add('你催动 ${target.name}，蛊力游走经脉，搜刮毒素……');
      log.addAll(detoxLogs);
      break;
    case 'extend_life':
      p.lifeLeft = min(p.lifeMax, p.lifeLeft + 30);
      p.luck = max(0, p.luck - 3);
      p.soulPower = max(1, p.soulPower - 2);
      p.tribulation += 50;
      log.add('你催动 ${target.name}，延寿 30 年！但寿道诅咒缠身，气运-3、魂力-2，劫数大增。');
      break;
    case 'utility':
      log.add('你催动 ${target.name}：感知到周边资源与道路。');
      break;
    case 'time_reversal':
      p.lifeLeft -= 1;
      p.refineProficiency += 5;
      p.tribulation += 80;
      log.add('你催动禁忌 ${target.name}，岁月逆流！炼蛊造诣大增，但耗寿1年，劫数暴涨！');
      break;
    case 'expand_slot':
      // 第二阶段：拓窍蛊（空窍容量扩容，一次性消耗耐久耐久上限）
      final add = (target.combat['expand_capacity'] as num? ?? (10 + target.rank * 10)).toInt();
      SlotCapacity.addExpandBonus(p, add);
      target.durability = 0;
      log.add('【拓窍】你催动 ${target.name}，生生拓宽空窍壁障！空窍容量 +$add'
          '（当前总上限 ${SlotCapacity.capacityMax(p)}）。'
          '${target.name} 化作流光融入空窍，永久损毁。');
      break;
    case 'storage':
      // 第二阶段：储物蛊（已装备即生效；催动时整理背包：合并同类堆叠）
      final before = p.inventory.length;
      final merged = <String>[];
      final cnt = <String, int>{};
      for (final it in p.inventory) {
        final (n, c) = MatParser.parse(it);
        cnt[n] = (cnt[n] ?? 0) + c;
      }
      cnt.forEach((n, c) {
        merged.add(c > 1 ? '${n}x$c' : n);
      });
      p.inventory = merged;
      final bonus = StorageGu.storageBonus(p);
      log.add('你催动 ${target.name}，储物空间光华流转，物资整理完毕'
          '（${before}→${merged.length}格，当前容量 ${StorageGu.usedCapacity(p)}/${StorageGu.capacityMax(p)}，储物加成 $bonus）。');
      break;
    default:
      log.add('${target.name} 是战斗/防御/遁/替身蛊，请在战斗中使用。');
  }
  return log;
}

GuInstance? _findGu(Player p, String guName) {
  for (final g in [...p.guInSlot, ...p.guBag]) {
    if (g.name == guName || g.instId == guName) return g;
  }
  return null;
}
