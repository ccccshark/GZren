# 蛊真人单机文字MUD（安卓端）

> 纯单机、离线文字 MUD，无任何联网、无多人功能。基于《蛊真人》原著设定，安卓 APP，手机端触控操作。
> 技术栈：Flutter (Dart)。

## 一、特性

- 完全离线：AndroidManifest 不声明 `INTERNET` 权限，不读取外部存储。
- 单机单人：世界、NPC 逻辑全部本地运行，无服务端、无联机。
- 触屏 UI：上方文字输出区 + 中部快捷指令按钮 + 底部输入框 + 悬浮菜单。
- 战斗/渡劫独立弹窗，回合制，含 NPC AI。
- 5 个本地存档槽，JSON 存至 APP 私有目录。
- 核心机制 100% 继承原著：寿元枷锁、蛊槽、炼蛊、道痕冲突、天劫、NPC AI、全局时间流逝。
- 蛊真人主题应用图标：黑蛊虫 + 紫毒气 + 深紫黑背景，支持 Android 自适应图标。

## 二、目录结构

```
gzren/
├── lib/
│   ├── main.dart                  # APP 入口 + 启动菜单
│   ├── engine/                    # 引擎核心
│   │   ├── command.dart           # 指令解析 + GameContext
│   │   ├── combat.dart            # 回合战斗 + 天劫渡劫
│   │   ├── world_timer.dart       # 全局世界时间、寿元流逝
│   │   ├── npc_ai.dart            # NPC 自动行为
│   │   ├── save_system.dart       # 5 槽本地存档 + 死亡惩罚
│   │   ├── player_core.dart       # 境界/蛊槽/寿元/道痕/突破
│   │   └── gu_system.dart         # 蛊虫：捕捉/炼蛊/投喂/装备/催动
│   ├── ui/                        # 触屏 UI
│   │   ├── main_game_page.dart
│   │   ├── save_menu.dart
│   │   ├── combat_ui.dart
│   │   └── help_page.dart
│   └── data_model/                # 数据实体
│       ├── player_model.dart
│       ├── gu_model.dart
│       ├── scene_model.dart
│       ├── npc_model.dart
│       └── recipe_model.dart
├── assets/static/                 # 内置静态 JSON（只读）
│   ├── gu_list.json
│   ├── recipe.json
│   ├── map.json
│   ├── npc_template.json
│   ├── material.json
│   └── random_event.json
├── assets/icon/                   # 应用图标源文件（PNG）
│   ├── icon_full.png              #   完整图标（legacy + Play Store）
│   ├── icon_foreground.png        #   自适应图标前景（已含 18% 边距）
│   └── icon_background.png        #   自适应图标背景（深紫黑渐变）
├── android/app/src/main/AndroidManifest.xml  # 离线权限配置（覆盖用）
├── build_apk.sh                   # 一键打包脚本
├── .github/workflows/build.yml    # GitHub Actions 云端打包工作流
├── analysis_options.yaml
└── pubspec.yaml
```

## 三、环境要求

| 项 | 版本 |
| --- | --- |
| Flutter | >= 3.10.0 |
| Dart SDK | >= 3.0.0 |
| Android 最低支持 | Android 8.0 (API 26) |
| 目标 ABI | arm64-v8a（文字游戏无需其他 ABI） |

## 四、首次构建步骤

仓库内已包含 `lib/`、`assets/`、`pubspec.yaml`、`AndroidManifest.xml` 等。Android 工程脚手架（gradle、kotlin MainActivity、build.gradle 等）由 `flutter create` 自动生成；已存在的文件会被保留。

> **不想本地装 Flutter？** 直接看下方 [方案 B：GitHub 云端打包（零配置）](#方案-bgithub-云端打包零配置推荐)，push 到 GitHub 自动出 APK，点几下下载即可。

### 方案 A：本地打包（推荐，可离线调试）

#### 0. 安装 Flutter SDK + JDK 17
- Flutter：<https://docs.flutter.dev/get-started/install>
- JDK 17（推荐 Temurin）：<https://adoptium.net/>

确认环境：
```bash
flutter doctor
java -version   # 需 17+
```

#### 1. 一键打包（最简方式）
仓库已内置 [build_apk.sh](build_apk.sh)，它会自动完成：补全 Android 脚手架 → 校验离线 AndroidManifest → 拉依赖 → 跑测试 → 打包 release APK。
```bash
cd gzren
bash build_apk.sh
```
脚本结束后会输出 APK 路径与大小，例如：
```
[OK]  APK 已生成
[OK]  路径：/path/to/gzren/build/app/outputs/flutter-apk/app-release.apk
[OK]  大小：12M
[OK]  安装：adb install -r build/app/outputs/flutter-apk/app-release.apk
```

#### 2. 手动逐步打包（便于排查问题）
```bash
cd gzren

# (1) 补全 Android 工程脚手架（不覆盖已存在的 lib/assets/pubspec/AndroidManifest）
flutter create --org com.guzhenren --project-name gzren --platforms=android .

# (2) 校验 AndroidManifest 仍是离线版本（无 INTERNET 权限）
grep -c "android.permission.INTERNET" android/app/src/main/AndroidManifest.xml
# 输出应为 0；若为 1 说明被覆盖，执行：git checkout android/app/src/main/AndroidManifest.xml

# (3) 接受 Android SDK 许可证（首次）
yes | flutter doctor --android-licenses

# (4) 拉依赖
flutter pub get

# (5) 跑测试（可选，失败不阻断打包）
flutter test

# (6) 打包
flutter build apk --release
```

#### 3. 运行调试（连接真机或模拟器）
```bash
flutter devices          # 查看可用设备
flutter run              # 调试运行
```

### 方案 B：GitHub 云端打包（零配置，推荐）

仓库已内置 [.github/workflows/build.yml](.github/workflows/build.yml)。流程：

1. 把本仓库 push 到你的 GitHub（公开或私有仓库均可）。
2. 进入仓库 **Actions** 标签页 → 选择 **Build Android APK** workflow → 点 **Run workflow**（也可由 push 自动触发）。
3. 等约 10~15 分钟构建完成。
4. 在该次 run 的页面底部 **Artifacts** 区下载 `guzhenren-mud-android-apk`，解压即得 `app-release.apk`。
5. （可选）打 `v1.0.0` 形式的 tag 可自动发布到 GitHub Releases，二维码可直接扫码下载。

云端打包不需要本地装 Flutter / Android SDK，也不需要 Java，全程在 GitHub 服务器完成。**这是普通用户最简单的获取 APK 方式。**

## 五、打包产物

不论方案 A 或 B，最终产物均为：
```
build/app/outputs/flutter-apk/app-release.apk
```

如需拆分 ABI（更小体积）：
```bash
flutter build apk --release --target-platform android-arm64
```

将 `app-release.apk` 安装到安卓手机即可纯离线运行。安装命令：
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```
或直接把 apk 文件传到手机点击安装（需开启「未知来源应用」权限）。

## 六、指令速查（游戏中输入 help 亦可）

| 分类 | 指令 |
| --- | --- |
| 移动场景 | `look` `go north/south/east/west` `map` |
| 角色状态 | `status` `inventory` `kuang` `breakthrough` |
| 蛊虫操作 | `capture [目标]` `refine [蛊方]` `feed [蛊] [材料]` `equip [蛊]` `unequip [蛊]` `use [蛊]` |
| NPC 交互 | `talk [npc]` `trade [npc]` `attack [npc]` `flee` |
| 生存行为 | `rest` `gather` |
| 系统 | `save [1~5]` `load [1~5]` `help` `quit` |
| 交易（输入框） | `buy [物品名] [数量]` `sell [物品名] [数量]` |

主界面提供快捷按钮：查看场景/状态/背包/空窍/采集/静坐/向北/向南/向东/向西。

## 七、核心规则（严格遵守原著）

- **蛊槽**：一转 3 → 九转 11；空窍蛊扩容，重伤概率永久损坏。
- **寿元**：一转 80 年 → 九转近乎无尽；光阴蛊/重伤加速消耗，归零即陨落。
- **炼蛊**：需蛊方 + 材料，失败有反噬，极小概率变异蛊（限 1~7 转，禁止九转自创）。
- **战斗**：玩家 VS NPC/异兽，回合制，NPC 具 AI，击杀可搜尸掠夺。
- **道痕冲突**产生持续道伤；突破/杀戮/禁忌蛊累积劫数，满则触发**天劫**。
- **死亡惩罚**：丢失蛊虫物资，概率空窍受损；存档不保留死亡状态。

## 八、强制禁止项（已严格遵守）

- 无网络请求、无 INTERNET 权限、无服务器、无联机。
- 无玩家间交易/组队/宗门/聊天。
- 无广告、充值、商城。
- 无副作用超模蛊虫；禁止玩家自由创造九转蛊。
- 仅使用 APP 私有目录存档，不读取外部存储。

## 九、测试

测试覆盖纯逻辑（数据模型 / 蛊虫系统 / 境界 / 世界时间 / 战斗 / 存档）与 Widget（帮助页 / 主菜单 / 主界面）。

### 运行全部测试
```bash
flutter test
```

### 运行单个测试文件
```bash
flutter test test/gu_system_test.dart
flutter test test/save_system_test.dart
flutter test test/widget_test.dart
```

### 测试清单

| 文件 | 覆盖范围 |
| --- | --- |
| `test/data_model_test.dart` | Player / Gu / Npc / Room / Recipe / MatParser 的 fromJson/toJson 往返与默认值 |
| `test/gu_system_test.dart` | 蛊实例生成（含变异）/ 材料增删改查 / 捕捉 / 炼蛊成功率边界 / 投喂 / 装备取出 / 催动（含春蝉蛊禁忌） |
| `test/player_core_test.dart` | 境界识别 / 寿元基准 / 蛊槽表 / 突破（含跨转蛊槽+1）/ 道痕冲突四对 |
| `test/world_timer_test.dart` | 时间推进 / 寿元流逝 / 伤势加速 / 天劫阈值触发 / 死亡停止 |
| `test/combat_test.dart` | 开战 / 攻击扣血扣真元 / 防御 / 逃亡 / 击杀搜尸 / 替身蛊保命 / 天劫渡劫成功失败 |
| `test/save_system_test.dart` | 5 槽独立存读 / 覆盖存档 / 损坏 JSON 容错 / NPC 状态往返 / 死亡惩罚（含蛊槽损失概率）|
| `test/widget_test.dart` | HelpPage 渲染 / MainMenuPage 4 按钮 + 角色创建对话框 / MainGamePage 快捷按钮 + 输入框 + 移动 |

> save_system 与 widget 测试通过 `path_provider_platform_interface` 的 fake platform 把存档目录重定向到系统临时目录，不依赖真实 Android 环境。
> widget 测试通过 mock `flutter/assets` 消息通道，让 `rootBundle` 直接读取磁盘 `assets/static/` 真实 JSON。

## 十、应用图标

项目内置蛊真人主题图标，源文件位于 `assets/icon/`：

| 文件 | 用途 | 规格 |
| --- | --- | --- |
| `icon_full.png` | legacy 启动器图标 + Play Store 展示图 | 1024×1024 RGBA |
| `icon_foreground.png` | Android 自适应图标前景（已含 18% 安全区边距） | 1024×1024 RGBA |
| `icon_background.png` | Android 自适应图标背景（深紫黑渐变） | 1024×1024 RGBA |

打包时由 `flutter_launcher_icons` 自动生成 `android/app/src/main/res/mipmap-*/ic_launcher.png` 和 `mipmap-anydpi-v26/ic_launcher.xml` 等各分辨率产物。

### 重新生成图标（修改图标后）
```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

### 自定义图标
1. 替换 `assets/icon/` 下的三张 PNG（建议保持 1024×1024 RGBA，前景图需在中间 66% 区域内绘制主体）。
2. 重新执行 `flutter pub run flutter_launcher_icons` 或直接 `bash build_apk.sh`。
3. 自适应图标设计规范参考：<https://developer.android.com/develop/ui/views/launchers/adaptive-icons>
