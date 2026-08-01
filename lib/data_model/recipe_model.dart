// recipe_model.dart
// 蛊方与进化蛊方模型。
class Recipe {
  final String rid;
  final String name;
  final int rank;
  final List<String> material; // ["露水x3","青茅草根x1"]
  final double baseSuccess;
  final String outputGid;
  // V1.3 新增【炼蛊环境需求】：env_required 指定炼蛊所需场景流派倍率或时段/天气。
  // 示例：{"min_school": "毒道", "min_mul": 1.20} 需毒道≥1.20的场景；
  //       {"phase": "夜晚"} 需夜晚时段。缺失→无环境限制（旧JSON兼容）。
  final Map<String, dynamic> envRequired;

  Recipe({
    required this.rid,
    required this.name,
    required this.rank,
    this.material = const [],
    this.baseSuccess = 0.5,
    required this.outputGid,
    this.envRequired = const {},
  });

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        rid: j['rid'] ?? '',
        name: j['name'],
        rank: j['rank'] ?? 1,
        material: List<String>.from(j['material'] ?? []),
        baseSuccess: (j['base_success'] ?? 0.5).toDouble(),
        outputGid: j['output_gid'] ?? '',
        envRequired: Map<String, dynamic>.from(j['env_required'] ?? const {}),
      );
}

class EvolveRecipe {
  final String name;
  final String baseGu;
  final List<String> material;
  final String outputGid;
  final double baseSuccess;

  EvolveRecipe({
    required this.name,
    required this.baseGu,
    this.material = const [],
    required this.outputGid,
    this.baseSuccess = 0.3,
  });

  factory EvolveRecipe.fromJson(Map<String, dynamic> j) => EvolveRecipe(
        name: j['name'] ?? '',
        baseGu: j['base_gu'] ?? '',
        material: List<String>.from(j['material'] ?? []),
        outputGid: j['output_gid'] ?? '',
        baseSuccess: (j['base_success'] ?? 0.3).toDouble(),
      );
}

// 解析 "露水x3" -> ("露水", 3)
// V1.9 修复【商人交易读取原石为0 BUG】：旧版仅认 ASCII 小写 'x'，
//   库存条目若带前后空格 / 全角× / 大写X（JSON 拼接或旧存档残留），
//   解析出的名字会夹杂分隔符（如 "原石x10 "），与 "原石" 不等 → countMaterial 归零。
//   现统一 trim + 兼容 x/X/× 三种分隔符 + 名称去空格，彻底消除读取为 0。
class MatParser {
  static (String, int) parse(String s) {
    final s0 = s.trim();
    if (s0.isEmpty) return (s, 1);
    // 1. 匹配 "名称<分隔符>数量"：分隔符支持 x / X / ×（全角），从右向左找最后一个
    //    材料名/蛊方名均为中文，不含 ASCII 字母，故匹配字母分隔符安全。
    for (int i = s0.length - 1; i > 0; i--) {
      final ch = s0[i];
      if (ch == 'x' || ch == 'X' || ch == '×') {
        final cnt = int.tryParse(s0.substring(i + 1).trim());
        if (cnt != null && cnt > 0) {
          final name = s0.substring(0, i).trim();
          if (name.isNotEmpty) return (name, cnt);
        }
      }
    }
    // 2. 兼容旧版 "名称数量" 格式：从末尾向前扫描连续 ASCII 数字
    int end = s0.length;
    while (end > 0) {
      final code = s0.codeUnitAt(end - 1);
      if (code < 48 || code > 57) break; // 非 '0'~'9'
      end--;
    }
    if (end > 0 && end < s0.length) {
      final cnt = int.tryParse(s0.substring(end));
      if (cnt != null && cnt > 0) return (s0.substring(0, end).trim(), cnt);
    }
    return (s0, 1);
  }
}
