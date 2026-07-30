// recipe_model.dart
// 蛊方与进化蛊方模型。
class Recipe {
  final String rid;
  final String name;
  final int rank;
  final List<String> material; // ["露水x3","青茅草根x1"]
  final double baseSuccess;
  final String outputGid;

  Recipe({
    required this.rid,
    required this.name,
    required this.rank,
    this.material = const [],
    this.baseSuccess = 0.5,
    required this.outputGid,
  });

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        rid: j['rid'] ?? '',
        name: j['name'],
        rank: j['rank'] ?? 1,
        material: List<String>.from(j['material'] ?? []),
        baseSuccess: (j['base_success'] ?? 0.5).toDouble(),
        outputGid: j['output_gid'] ?? '',
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
// 兼容两种格式：
//   1. 标准格式 "原石x10"（带 'x' 分隔符，初始背包/蛊方/修复后写入均用此格式）
//   2. 旧版损坏格式 "原石10"（旧 addMaterial/consumeMaterial 漏写 'x' 产生，
//      兼容已有存档，避免交易面板读到数量 0）
class MatParser {
  static (String, int) parse(String s) {
    // 1. 优先匹配标准 "名称x数量" 格式
    final xIdx = s.lastIndexOf('x');
    if (xIdx > 0) {
      final cnt = int.tryParse(s.substring(xIdx + 1));
      if (cnt != null) return (s.substring(0, xIdx), cnt);
    }
    // 2. 兼容旧版 "名称数量" 格式：从末尾向前扫描连续数字
    //    材料名（露水/原石/月光石…）与蛊方名均不含 ASCII 数字，安全。
    int end = s.length;
    while (end > 0) {
      final code = s.codeUnitAt(end - 1);
      if (code < 48 || code > 57) break; // 非 '0'~'9'
      end--;
    }
    if (end > 0 && end < s.length) {
      final cnt = int.tryParse(s.substring(end));
      if (cnt != null && cnt > 0) return (s.substring(0, end), cnt);
    }
    return (s, 1);
  }
}
