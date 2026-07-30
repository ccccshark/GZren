// save_codec.dart
// 存档码导入导出编解码模块（纯逻辑，无 UI）。
//
// 作为本地存档之外的补充备份手段，方便玩家跨手机迁移/分享存档。
// 原有本地存档系统保留不变；本模块仅读取/写入存档槽的原始 JSON 对象。
//
// 编码方案（仅 Base64，开源项目不做高强度加密）：
//   存档码 = Base64( gzip( JSON(存档对象 + 版本标记) ) ) + "." + CRC32(上述 Base64)
//
// 校验链：CRC32 防手动篡改 → Base64 合法性 → gzip 解压 → JSON 结构 → 版本兼容。
// 异常处理：空输入/乱码/篡改/字段缺失全部抛出 SaveCodeException（含中文提示），不崩溃。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 当前存档码版本标记。未来字段变更可递增；导入时据此判断兼容性。
const int kSaveCodeVersion = 1;

/// 当前仍可兼容导入的最低版本（含）。低于此版本提示“存档版本过旧无法导入”。
const int kMinCompatibleVersion = 1;

/// 存档码编解码异常（带友好中文提示）。
class SaveCodeException implements Exception {
  final String message;
  SaveCodeException(this.message);
  @override
  String toString() => message;
}

/// 存档码解析结果：原始存档对象 + 版本标记。
class DecodedSave {
  final Map<String, dynamic> data;
  final int version;
  DecodedSave(this.data, this.version);
}

// ===================== CRC32（自包含实现，不依赖外部包） =====================

int _crc32(Uint8List bytes) {
  // 标准 CRC-32 (IEEE 802.3)，多项式 0xEDB88320（反向）
  int crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xEDB88320 & mask);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

String _crcHex(int crc) => crc.toRadixString(16).padLeft(8, '0').toUpperCase();

// ===================== 编码 =====================

/// 将存档对象编码为存档码字符串。
/// [saveData] 为存档槽的原始 JSON 对象（含 player/npcs/save_time/version）。
String encodeSaveCode(Map<String, dynamic> saveData) {
  // 1. 附加存档码版本标记
  final payload = <String, dynamic>{
    ...saveData,
    'save_code_version': kSaveCodeVersion,
  };
  // 2. 序列化为紧凑 JSON
  final jsonStr = jsonEncode(payload);
  final jsonBytes = utf8.encode(jsonStr);
  // 3. gzip 压缩（ZLibCodec.gzip）
  final gzipBytes = gzip.encode(jsonBytes);
  // 4. Base64 编码
  final b64 = base64.encode(gzipBytes);
  // 5. 计算 CRC32 并附加（用于检测手动篡改）
  final crc = _crc32(Uint8List.fromList(utf8.encode(b64)));
  return '$b64.${_crcHex(crc)}';
}

// ===================== 解码 =====================

/// 解析存档码字符串。失败抛 [SaveCodeException]（含中文提示）。
DecodedSave decodeSaveCode(String code) {
  // 空输入
  final trimmed = code.trim();
  if (trimmed.isEmpty) {
    throw SaveCodeException('存档码为空，请粘贴有效的存档码。');
  }
  // 分离 Base64 主体与 CRC 校验码
  final dot = trimmed.lastIndexOf('.');
  if (dot <= 0 || dot >= trimmed.length - 1) {
    throw SaveCodeException('存档码格式错误：缺少校验码段。');
  }
  final b64 = trimmed.substring(0, dot);
  final crcHex = trimmed.substring(dot + 1).toUpperCase();

  // CRC 校验：检测手动篡改
  int expectedCrc;
  try {
    expectedCrc = int.parse(crcHex, radix: 16);
  } catch (_) {
    throw SaveCodeException('存档码损坏：校验码段格式错误。');
  }
  final actualCrc = _crc32(Uint8List.fromList(utf8.encode(b64)));
  if (actualCrc != expectedCrc) {
    throw SaveCodeException('存档码校验失败：内容已被修改或传输损坏。');
  }

  // Base64 合法性
  Uint8List gzipBytes;
  try {
    gzipBytes = base64.decode(b64);
  } catch (_) {
    throw SaveCodeException('存档码损坏：Base64 解码失败。');
  }

  // gzip 解压
  Uint8List jsonBytes;
  try {
    jsonBytes = Uint8List.fromList(gzip.decode(gzipBytes));
  } catch (_) {
    throw SaveCodeException('存档码损坏：解压失败。');
  }

  // JSON 结构校验
  Map<String, dynamic> payload;
  try {
    final obj = jsonDecode(utf8.decode(jsonBytes));
    if (obj is! Map<String, dynamic>) {
      throw SaveCodeException('存档码损坏：结构不是对象。');
    }
    payload = obj;
  } on SaveCodeException {
    rethrow;
  } catch (_) {
    throw SaveCodeException('存档码损坏：JSON 解析失败。');
  }

  // 版本兼容性
  final ver = (payload['save_code_version'] ?? 1) as int;
  if (ver < kMinCompatibleVersion) {
    throw SaveCodeException('存档版本过旧（v$ver）无法导入，当前最低支持 v$kMinCompatibleVersion。');
  }

  // 必备字段缺失校验（新旧版本差异）
  if (!payload.containsKey('player') || payload['player'] is! Map) {
    throw SaveCodeException('存档码损坏：缺少 player 字段。');
  }
  if (!payload.containsKey('npcs') || payload['npcs'] is! List) {
    throw SaveCodeException('存档码损坏：缺少 npcs 字段。');
  }

  // 去除版本标记后返回原始存档对象
  final saveData = Map<String, dynamic>.from(payload);
  saveData.remove('save_code_version');
  return DecodedSave(saveData, ver);
}
