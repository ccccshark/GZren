#!/usr/bin/env bash
# build_apk.sh
# 蛊真人单机MUD（安卓端）一键打包脚本
# 用法：在本仓库根目录执行 bash build_apk.sh
#
# 本脚本会：
#   1. 检查 Flutter / Java 环境
#   2. 用 flutter create 补全缺失的 Android 工程脚手架（不覆盖已存在的 lib/assets/pubspec/AndroidManifest）
#   3. 确保本仓库的离线 AndroidManifest.xml 仍生效
#   4. flutter pub get 拉依赖
#   5. flutter test 跑全部测试（失败不阻断打包，仅警告）
#   6. flutter build apk --release 打包 release APK
#   7. 输出最终 APK 路径
#
# 退出码：0 成功；非 0 失败。
set -euo pipefail

# ---------- 颜色 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*" >&2; }

# ---------- 进入脚本所在目录 ----------
cd "$(dirname "$(readlink -f "$0")")"
PROJECT_DIR="$(pwd)"
log "工程目录：$PROJECT_DIR"

# ---------- 1. 环境检查 ----------
log "检查环境..."
command -v flutter >/dev/null 2>&1 || { err "未找到 flutter，请先安装 Flutter SDK：https://docs.flutter.dev/get-started/install"; exit 1; }
command -v java    >/dev/null 2>&1 || { err "未找到 java，请先安装 JDK 17+"; exit 1; }

FLUTTER_VER=$(flutter --version 2>&1 | head -1)
JAVA_VER=$(java -version 2>&1 | head -1)
ok "Flutter: $FLUTTER_VER"
ok "Java:    $JAVA_VER"

# 接受 Android 许可证（首次需要；如果失败仅警告）
log "接受 Android SDK 许可证（如已接受会跳过）..."
yes | flutter doctor --android-licenses >/dev/null 2>&1 || warn "自动接受许可证失败，如打包时报许可错误请手动执行：flutter doctor --android-licenses"

# ---------- 2. 补全 Android 脚手架 ----------
log "补全 Android 工程脚手架（不覆盖已存在文件）..."
# --platforms=android 只生成 android/；--org 指定包名；. 表示当前目录
flutter create \
  --org com.guzhenren \
  --project-name gzren \
  --platforms=android \
  --description "蛊真人单机文字MUD（安卓端）—— 纯离线单机，无任何联网功能。" \
  . >/dev/null
ok "脚手架就绪"

# ---------- 3. 确保离线 AndroidManifest 生效 ----------
# flutter create 不会覆盖已存在的 AndroidManifest.xml，但保险起见再校验一次
MANIFEST="android/app/src/main/AndroidManifest.xml"
if ! grep -q "蛊真人单机MUD" "$MANIFEST" 2>/dev/null; then
  err "$MANIFEST 不是本仓库版本，请检查 git 状态"
  exit 1
fi
if grep -q "android.permission.INTERNET" "$MANIFEST"; then
  err "$MANIFEST 包含 INTERNET 权限，违反离线约束"
  exit 1
fi
ok "AndroidManifest.xml 校验通过（无 INTERNET 权限）"

# ---------- 4. 拉依赖 ----------
log "拉取 Dart 依赖..."
flutter pub get >/dev/null
ok "依赖就绪"

# ---------- 4.5 生成应用图标（蛊真人主题） ----------
log "生成应用图标..."
if flutter pub run flutter_launcher_icons 2>&1 | tail -5; then
  ok "应用图标已生成至 android/app/src/main/res/"
else
  warn "图标生成失败，将使用默认 Flutter 图标继续打包"
fi

# ---------- 5. 跑测试（失败不阻断） ----------
log "运行测试套件（失败不阻断打包）..."
if flutter test 2>&1 | tee /tmp/guzhenren_test.log | tail -20; then
  ok "全部测试通过"
else
  warn "部分测试未通过，详细日志见 /tmp/guzhenren_test.log"
  warn "如不影响打包可忽略；建议修复后再发布"
fi

# ---------- 6. 打包 release APK ----------
log "开始打包 release APK..."
flutter build apk --release
ok "打包完成"

# ---------- 7. 输出产物路径 ----------
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
  APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
  echo ""
  ok "════════════════════════════════════════════════════"
  ok "  APK 已生成"
  ok "  路径：$PROJECT_DIR/$APK_PATH"
  ok "  大小：$APK_SIZE"
  ok "  安装：adb install -r $APK_PATH"
  ok "════════════════════════════════════════════════════"
  exit 0
else
  err "未找到产物 $APK_PATH，请检查上面的构建日志"
  exit 1
fi
