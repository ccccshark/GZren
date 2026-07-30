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
class MatParser {
  static (String, int) parse(String s) {
    final idx = s.lastIndexOf('x');
    if (idx > 0) {
      final cnt = int.tryParse(s.substring(idx + 1));
      if (cnt != null) return (s.substring(0, idx), cnt);
    }
    return (s, 1);
  }
}
