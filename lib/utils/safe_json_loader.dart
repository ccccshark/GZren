// safe_json_loader.dart
// JSON 安全解析工具：异步加载 + try-catch 兜底 + 文件批量加载。
// 【V3.3】移除 compute/Isolate：JSON 总量仅 364KB，Isolate 创建开销远大于解析开销，
// 且 Release 模式下 compute() 可能挂起导致黑屏。直接主线程 jsonDecode 即可。
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

  T? or(T? fallback) => data ?? fallback;
}

/// 安全解析 JSON 字符串，try-catch 包裹，失败返回 error。
/// 【V3.3】直接主线程 jsonDecode，不使用 compute/Isolate。
Future<JsonResult<dynamic>> decodeInIsolate(
    String jsonString, String source) async {
  try {
    final result = jsonDecode(jsonString);
    return JsonResult(data: result, source: source);
  } catch (e) {
    return JsonResult(
      error: '[$source] JSON 解析失败: $e',
      source: source,
    );
  }
}

/// 从 assets 中加载 JSON 文件并安全解析。
Future<JsonResult<dynamic>> loadAssetJson(String path, {String? source}) async {
  final tag = source ?? path.split('/').last;
  try {
    final jsonString = await rootBundle.loadString(path);
    return decodeInIsolate(jsonString, tag);
  } catch (e) {
    return JsonResult(
      error: '[$tag] 文件读取失败: $e',
      source: tag,
    );
  }
}

/// 从文件系统加载 JSON 文件（异步方式）。
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