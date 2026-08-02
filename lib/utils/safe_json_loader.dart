// safe_json_loader.dart
// JSON 安全解析工具：compute isolate 异步解析 + try-catch 兜底 + 文件批量加载。
// 所有 JSON 解析必须经过此模块，禁止直接调用 jsonDecode 处理外部资产。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// JSON 解析结果包装，携带具体错误信息。
class JsonResult<T> {
  final T? data;
  final String? error;
  final String source;

  const JsonResult({this.data, this.error, required this.source});

  bool get isSuccess => data != null;
  bool get isFailure => error != null;

  /// 成功时返回 data，失败时返回 [fallback]。
  T? or(T? fallback) => data ?? fallback;
}

/// 在独立 Isolate 中执行 jsonDecode，不阻塞 UI 主线程。
/// [jsonString] 原始 JSON 字符串，[source] 用于错误提示的文件名。
Future<JsonResult<dynamic>> decodeInIsolate(
    String jsonString, String source) async {
  try {
    // compute 将 jsonDecode 放入独立 Isolate 执行，返回值通过消息传递回主 Isolate。
    final result = await compute(_isolateJsonDecode, jsonString);
    return JsonResult(data: result, source: source);
  } catch (e) {
    return JsonResult(
      error: '[$source] JSON 解析失败: $e',
      source: source,
    );
  }
}

/// 在 Isolate 中运行的顶层函数（必须为顶层函数，不能是闭包或类方法）。
@pragma('vm:entry-point')
dynamic _isolateJsonDecode(String jsonString) {
  return jsonDecode(jsonString);
}

/// 从 assets 中加载 JSON 文件，在独立 Isolate 中解析，返回类型安全的 result。
/// [path] assets 路径，如 'assets/static/gu_list.json'。
/// [source] 用于错误日志的标识名，默认取文件 basename。
Future<JsonResult<dynamic>> loadAssetJson(String path, {String? source}) async {
  final tag = source ?? path.split('/').last;
  try {
    // 1. 主线程读取文件内容（I/O 操作，非 CPU 密集，无需 Isolate）
    final jsonString = await rootBundle.loadString(path);
    // 2. 在 Isolate 中解析 JSON
    return decodeInIsolate(jsonString, tag);
  } catch (e) {
    return JsonResult(
      error: '[$tag] 文件读取失败: $e',
      source: tag,
    );
  }
}

/// 从文件系统加载 JSON 文件（异步方式，替代 readAsStringSync）。
/// [path] 文件系统绝对路径。
Future<JsonResult<dynamic>> loadFileJson(String path, {String? source}) async {
  final tag = source ?? path.split('/').last;
  try {
    final file = File(path);
    final exists = await file.exists();
    if (!exists) {
      return JsonResult(error: '[$tag] 文件不存在: $path', source: tag);
    }
    final jsonString = await file.readAsString();
    return decodeInIsolate(jsonString, tag);
  } catch (e) {
    return JsonResult(
      error: '[$tag] 文件读取失败: $e',
      source: tag,
    );
  }
}

/// 加载 JSON 并安全转换为 Map<String, dynamic>。
/// 失败时返回空 Map 并打印错误日志。
Future<Map<String, dynamic>> loadAssetJsonMap(
    String path, {String? source}) async {
  final result = await loadAssetJson(path, source: source);
  if (result.isFailure) {
    debugPrint('${result.error}');
    return <String, dynamic>{};
  }
  final data = result.data;
  if (data is Map<String, dynamic>) return data;
  debugPrint('[${result.source}] 类型错误: 期望 Map, 实际 ${data.runtimeType}');
  return <String, dynamic>{};
}

/// 加载 JSON 并安全转换为 List<dynamic>。
/// 失败时返回空列表。
Future<List<dynamic>> loadAssetJsonList(
    String path, {String? source}) async {
  final result = await loadAssetJson(path, source: source);
  if (result.isFailure) {
    debugPrint('${result.error}');
    return [];
  }
  final data = result.data;
  if (data is List) return data;
  debugPrint('[${result.source}] 类型错误: 期望 List, 实际 ${data.runtimeType}');
  return [];
}

/// 批量加载 assets JSON 文件，每项返回 JsonResult。
/// 不因单个文件失败而中断整体流程。
Future<List<JsonResult<dynamic>>> loadAssetJsonBatch(
    List<String> paths) async {
  final results = <Future<JsonResult<dynamic>>>[];
  for (final path in paths) {
    results.add(loadAssetJson(path));
  }
  return Future.wait(results);
}

/// 写入错误日志到本地文件（用于 release 模式下的异常追踪）。
/// [tag] 日志标签，[message] 错误信息，[stack] 可选堆栈。
Future<void> writeErrorLog(String tag, String message, {String? stack}) async {
  try {
    final doc = await getApplicationDocumentsDirectory();
    final logDir = Directory('${doc.path}/logs');
    final exists = await logDir.exists();
    if (!exists) await logDir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${logDir.path}/crash_$stamp.log');
    final buf = StringBuffer();
    buf.writeln('=== 蛊真人错误日志 ===');
    buf.writeln('时间: $stamp');
    buf.writeln('标签: $tag');
    buf.writeln('消息: $message');
    if (stack != null) buf.writeln('堆栈:\n$stack');
    buf.writeln('=====================');
    await file.writeAsString(buf.toString());
  } catch (_) {
    // 写日志本身失败不抛出
  }
}