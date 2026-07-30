// player_core.dart
// 玩家蛊师核心逻辑：境界体系、蛊槽、寿元基准、道痕冲突、境界突破。
import '../data_model/player_model.dart' show Player;

// 境界 -> 蛊槽上限（一转3 ~ 九转11）
const Map<String, int> levelSlot = {
  '一转初阶': 3, '一转中阶': 3, '一转高阶': 3, '一转巅峰': 3,
  '二转初阶': 4, '二转中阶': 4, '二转高阶': 4, '二转巅峰': 4,
  '三转初阶': 5, '三转中阶': 5, '三转高阶': 5, '三转巅峰': 5,
  '四转初阶': 6, '四转中阶': 6, '四转高阶': 6, '四转巅峰': 6,
  '五转初阶': 7, '五转中阶': 7, '五转高阶': 7, '五转巅峰': 7,
  '六转初阶': 8, '六转中阶': 8, '六转高阶': 8, '六转巅峰': 8,
  '七转初阶': 9, '七转中阶': 9, '七转高阶': 9, '七转巅峰': 9,
  '八转初阶': 10, '八转中阶': 10, '八转高阶': 10, '八转巅峰': 10,
  '九转初阶': 11, '九转中阶': 11, '九转高阶': 11, '九转巅峰': 11,
};

// 寿元基准
const Map<String, double> levelLifespan = {
  '一转': 80, '二转': 150, '三转': 300, '四转': 600,
  '五转': 1200, '六转': 2500, '七转': 5000, '八转': 10000,
  '九转': 999999,
};

const List<String> levelOrder = [
  '一转初阶', '一转中阶', '一转高阶', '一转巅峰',
  '二转初阶', '二转中阶', '二转高阶', '二转巅峰',
  '三转初阶', '三转中阶', '三转高阶', '三转巅峰',
  '四转初阶', '四转中阶', '四转高阶', '四转巅峰',
  '五转初阶', '五转中阶', '五转高阶', '五转巅峰',
  '六转初阶', '六转中阶', '六转高阶', '六转巅峰',
  '七转初阶', '七转中阶', '七转高阶', '七转巅峰',
  '八转初阶', '八转中阶', '八转高阶', '八转巅峰',
  '九转初阶', '九转中阶', '九转高阶', '九转巅峰',
];

const List<String> daoSchools = ['气道', '月道', '毒道', '地道', '寿道', '岁月道', '血道', '星道'];

// 互相冲突的大道
const List<(String, String)> conflictDaos = [
  ('气道', '血道'),
  ('月道', '毒道'),
  ('寿道', '岁月道'),
  ('地道', '星道'),
];

int levelRank(String level) {
  const chs = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
  for (var i = 0; i < chs.length; i++) {
    if (level.startsWith('${chs[i]}转')) return i + 1;
  }
  return 1;
}

double lifespanBase(String level) {
  const keys = ['一转', '二转', '三转', '四转', '五转', '六转', '七转', '八转', '九转'];
  final r = levelRank(level);
  return (levelLifespan[keys[r - 1]] ?? 80).toDouble();
}

double daoConflictDamage(Player p) {
  double total = 0;
  for (final (a, b) in conflictDaos) {
    if ((p.daoMark[a] ?? 0) > 0 && (p.daoMark[b] ?? 0) > 0) {
      total += (p.daoMark[a]! + p.daoMark[b]!) * 0.02;
    }
  }
  return total;
}

bool canBreakthrough(Player p) {
  final idx = levelOrder.indexOf(p.level);
  return idx >= 0 && idx < levelOrder.length - 1;
}

// 境界突破。返回日志行列表。突破累积劫数。
List<String> breakthrough(Player p) {
  final log = <String>[];
  if (!canBreakthrough(p)) {
    log.add('你已至九转巅峰，无更高境界可破。');
    return log;
  }
  final idx = levelOrder.indexOf(p.level);
  final oldRank = levelRank(p.level);
  p.level = levelOrder[idx + 1];
  final newRank = levelRank(p.level);
  p.slotMax = levelSlot[p.level] ?? p.slotMax;
  p.lifeMax = lifespanBase(p.level);
  if (newRank > oldRank) {
    p.lifeLeft = p.lifeMax;
    p.trueyuanMax += 50;
    p.trueyuan = p.trueyuanMax;
    p.physique += 15;
    p.soulPower += 15;
  }
  p.tribulation += 30;
  log.add('【突破】你突破至 ${p.level}！蛊槽上限 ${p.slotMax}，寿元重置为 ${p.lifeMax.toInt()} 年。');
  log.add('劫数暗生，天劫之兆渐显……');
  return log;
}
