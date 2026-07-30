// help_page.dart
// 指令帮助页面。
import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = <(String, List<(String, String)>)>[
      ('移动与场景', [
        ('look', '查看当前场景详情'),
        ('go north/south/east/west', '移动'),
        ('map', '简易区域地图'),
      ]),
      ('角色状态', [
        ('status', '查看寿元、真元、道痕、伤势'),
        ('inventory', '查看背包物资'),
        ('kuang', '查看空窍内蛊虫'),
        ('breakthrough', '境界突破（需道痕积累，引发劫数）'),
      ]),
      ('蛊虫操作', [
        ('capture [目标]', '捕捉野生蛊虫'),
        ('refine [蛊方名]', '启动炼蛊'),
        ('feed [蛊名] [材料]', '投喂蛊虫恢复耐久'),
        ('equip [蛊名]', '将蛊放入空窍'),
        ('unequip [蛊名]', '从空窍取出蛊虫'),
        ('use [蛊名]', '催动蛊虫'),
      ]),
      ('NPC交互', [
        ('talk [npc名]', '和NPC对话'),
        ('trade [npc名]', '和NPC交易物资'),
        ('attack [npc名]', '发起战斗'),
        ('flee', '战斗中尝试逃亡'),
      ]),
      ('生存行为', [
        ('rest', '静坐恢复真元，推进世界时间'),
        ('gather', '采集当前场景资源'),
      ]),
      ('系统指令', [
        ('save [1~5]', '保存至对应存档位'),
        ('load [1~5]', '读取对应存档位'),
        ('help', '打印全部指令列表'),
        ('quit', '返回主菜单'),
      ]),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('游戏说明'), backgroundColor: const Color(0xFF2C1E3A)),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text('蛊真人单机MUD · 严格遵循原著设定',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF9B59B6))),
          const SizedBox(height: 4),
          const Text('纯单机离线，无任何联网功能。寿元枷锁、蛊槽、炼蛊、道痕、天劫、NPC AI、全局时间流逝均已实装。',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),
          ...sections.map((s) => _section(s)),
          const SizedBox(height: 16),
          const Text('核心规则', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF27AE60))),
          const SizedBox(height: 6),
          const Text(
            '· 蛊槽：一转3 → 九转11；空窍蛊扩容，重伤概率永久损坏。\n'
            '· 寿元：一转80年 → 九转近乎无尽；光阴蛊/重伤加速消耗，归零即陨落。\n'
            '· 炼蛊：需蛊方+材料，失败有反噬，极小概率变异蛊（限1~7转，禁九转自创）。\n'
            '· 战斗：玩家VS NPC/异兽，回合制，NPC具AI，击杀可搜尸掠夺。\n'
            '· 道痕冲突产生持续道伤；突破/杀戮/禁忌蛊累积劫数，满则天劫。\n'
            '· 死亡惩罚：丢失蛊虫物资，概率空窍受损；存档不保留死亡状态。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _section((String, List<(String, String)>) s) {
    final (title, items) = s;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1ABC9C))),
      ...items.map((it) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 180, child: Text(it.$1, style: const TextStyle(color: Color(0xFFE67E22), fontFamily: 'monospace'))),
          Expanded(child: Text(it.$2, style: const TextStyle(color: Colors.white70))),
        ]),
      )),
    ]);
  }
}
