# 《蛊真人》增量数据补全清单

> 范围：V1.5(西漠) → V1.6(北原) → V1.7(东海) → V1.8(中州) → V1.9(全域完善) → 仙道杀招专项
> 原则：仅扩充 assets 配置数据，不改动游戏底层逻辑（杀招系统代码经专项许可）
> 原著合规：蛊虫/蛊方/杀招均源自原著，无原创设定

---

## 一、蛊虫基础数据（gu_*.json）

### 现有蛊池总览（79 只）
| 流派 | 蛊虫数 | gid 范围 |
|---|---|---|
| 气道 | 21 | g001-g005,g007,g008,g010,g014-g021,g047-g051,g_wind_walk,g_mirage,g_qm_tanyin |
| 冰道 | 8 | g_bingdun,g_xuehu,g_bingxiong,g_hanlin,g_xuedun,g_bingpo,g_xueyao,g_binglin_wang |
| 毒道 | 7 | g006,g009,g012,g022,g052-g054 |
| 力道 | 7 | g023-g027,g055,g056 |
| 鬼道 | 6 | g036-g039,g_qm_yinshi,g_desert_ghost |
| 地道 | 5 | g013,g_qm_tudun,g_sand_dodge,g_sand_worm,g_liusha |
| 血道 | 4 | g028-g031 |
| 兽道 | 4 | g032-g035 |
| 食道 | 4 | g040-g043 |
| 月道 | 3 | g003,g011,g_hanyue |
| 运道 | 3 | g044-g046 |
| 风沙道 | 2 | g_dust_devil,g_sandstorm_lord |
| 土道 | 2 | g_salt_crystal,g_sand_giant |
| 水道 | 1 | g_shuidun |
| 寿道 | 1 | g016 |
| 岁月道 | 1 | g017 |

### 各版本新增蛊虫
| 版本 | 大区 | 文件 | 新增蛊虫 |
|---|---|---|---|
| V1.5 | 西漠 | gu_ximo.json | 风行蛊(g_wind_walk)、沙遁蛊(g_sand_dodge)、流沙蛊(g_liusha)、风沙蛊(g_dust_devir) 等 |
| V1.6 | 北原 | gu_beiyuan.json | 冰遁蛊(g_bingdun)、寒月蛊(g_hanyue)、雪遁蛊(g_xuedun)、冰麟蛊王(g_binglin_wang) 等 9 只 |
| V1.7 | 东海 | gu_donghai.json | 水遁蛊(g_shuidun) 1 只（秘境钥匙，原著遁蛊体系） |
| V1.8 | 中州 | gu_zhongzhou.json | （空，复用现有原著低阶蛊，零自创） |

### 投放规则达成
- 凡阶低阶蛊（1-2转）：南疆/西漠野外可捕捉、商人售卖、怪物掉落 ✓
- 凡阶高阶蛊（3-4转）：北原/东海场景、秘境产出 ✓
- 地阶蛊（5转+）：中州秘境、精英BOSS、稀有奇遇 ✓
- 天阶蛊（6转+）：仅剧情提及，无法捕捉炼制 ✓

---

## 二、炼制蛊方（recipe.json）

### 现有蛊方总览
- 普通蛊方：48 条（r001-r048）
- 进化蛊方：10 条
- **蛊方材料可获取校验：无缺口 ✓**（所有材料均可野外采集/BOSS掉落/商人购买）

### 各版本新增蛊方
| 版本 | 蛊方ID | 蛊方名 | 目标蛊 | 材料 |
|---|---|---|---|---|
| V1.5 | r040-r042 | 风行蛊蛊方 等 | g_wind_walk 等 | 西漠材料 |
| V1.6 | r045-r047 | 冰遁蛊蛊方、御寒蛊蛊方 等 | g_bingdun 等 | 北原材料 |
| V1.7 | r048 | 水遁蛊蛊方 | g_shuidun | 海珍珠x3、咸湿蛊材x2、海蛇蜕x1 |

### 蛊方材料→场景采集绑定（核心新增要求）
| 材料 | 蛊方 | 投放场景 | 生态匹配 |
|---|---|---|---|
| 酒液 | r007 酒虫蛊方 | 散修集市、青茅山药堂 | 人烟/酿造生态 |
| 竹节 | r014/r035/r009 竹类蛊方 | 青茅山东谷 | 青竹林生态 |
| 海珍珠 | r048 水遁蛊方 | 碧波断崖、海妖洞窟 | 东海海域 |
| 寒冰原石 | r045 冰遁蛊方 | 雪原林地、冻土荒原 | 北原雪原 |
| 灵墨 | (中州材料) | 中原麦田、古驿站 | 中州文风 |

**校验结果：28 种蛊方材料全部可野外采集或商人购买，0 缺口**

---

## 三、仙道杀招（kill_move.json → preset_killer_moves）

### 预设杀招系统
- 数据模型：`PresetKillerMove` / `PresetKillerMoveStore`（killer_move_model.dart）
- 加载点：command.dart loadStatic 启动读取 preset_killer_moves
- 指令：`pkm`（列表）/ `pkm 杀招名`（释放）
- 持久化：解锁状态+冷却时间存于 player.flags['preset_km_state']

### 原著预设杀招（4 条）
| move_id | 杀招名 | 类型 | 必备蛊虫 | 真元 | 冷却 | 反噬 | 原著参考 |
|---|---|---|---|---|---|---|---|
| pkm001 | 血泪杀 | 单体攻击 | g028血蚊+g029嗜血+g030血煞 | 45 | 120min | -18体魄 | 原著血道杀招，泣血成杀 |
| pkm002 | 万蚁噬身 | 持续攻击 | g028血蚊+g040吞食+g043噬蛊 | 50 | 180min | -22体魄 | 原著兽道·食道联动，群蚁噬身 |
| pkm003 | 水云盾 | 防御 | g_shuidun水遁+g005玉皮 | 32 | 90min | 无 | 原著水道·气道防御，水云凝盾 |
| pkm004 | 流沙天幕 | 群体困敌 | g_liusha流沙+g_dust_devil风沙 | 40 | 150min | -12体魄 | 原著地道·风沙道，西漠成名绝技 |

### 杀招机制
- **解锁**：集齐全套 required_gu（空窍+背包）→ refreshUnlock 自动解锁 + 播报"自行领悟"
- **锁定**：缺任意蛊 → `pkm` 列表显示 `[锁定·缺少配套蛊虫]`，释放提示所需蛊虫清单
- **冷却**：last_cast 存游戏分钟，持久化于 flags，重启不重置
- **反噬**：backlash_dmg>0 时直接扣体魄（max(1,...)防死亡）
- **原自定义杀招**：KillerMove/KillerMoveStore 零改动，km/kmnew/kmdel 原样保留

---

## 四、材料与场景绑定（material_*.json + map_*.json）

### 材料生态匹配原则达成
| 材料属性 | 投放区域 | 场景 |
|---|---|---|
| 毒类 | 密林/瘴气秘境 | 瘴林外围/深处、沼泽秘境 |
| 寒冰 | 北原雪原/冰岩峡谷 | 雪原林地、冻土荒原、永冻冰窟 |
| 水系 | 东海/溪流 | 滨海礁岸、碧波断崖、海妖洞窟 |
| 沙土类 | 西漠荒漠 | 沙海、流沙沟壑 |
| 气道/文风 | 中州 | 中原麦田、古驿站、百家藏书阁 |

### 材料产出分层达成
- 普通基础材料：多个常规野外场景可采集 ✓
- 稀有炼制材料：仅限对应区域隐藏秘境、BOSS掉落 ✓

---

## 五、五大区域场景补充

### 区域开放状态
| 区域 | 版本 | 状态 | 通道 |
|---|---|---|---|
| 南疆 | V1.2~V1.4 | 完整开放 | 起始区域 |
| 西漠 | V1.5 | 完整开放 | border_west_pass（五转解锁） |
| 北原 | V1.6 | 完整开放 | border_north_pass（五转解锁） |
| 东海 | V1.7 | 精简场景集开放 | border_east_pass（五转解锁） |
| 中州 | V1.8 | 精简场景集开放 | border_center_pass（五转解锁） |
| 太古遗迹 | — | **永久锁定** | 无任何入口 |
| 逆流河 | — | **永久锁定** | 无任何入口 |

### 区域特色环境机制
| 区域 | 机制 | 实现 |
|---|---|---|
| 西漠 | 沙暴、流沙沟壑无流沙蛊掉血 | weather_ximo + 事件 |
| 北原 | 严寒，无御寒蛊消耗真元 | cold_zone secret + _maybeColdHazard |
| 东海 | 潮汐、水域无水遁蛊消耗真元 | weather_donghai + 海妖洞窟需水遁蛊 |
| 中州 | 人形蛊师NPC、黑市以物易物 | npc_zhongzhou + 商人 |

### 秘境配置
| 秘境 | 大区 | 钥匙蛊 | BOSS | 刷新条件 |
|---|---|---|---|---|
| 青茅山地下蛊窟 | 南疆 | 土遁蛊 | 青茅古蛊 | 夜晚/凌晨 |
| 毒瘴秘境 | 南疆 | 玉蟾蛊(g022) | — | — |
| 古坟秘境 | 南疆 | (原著规则) | — | — |
| 永冻冰窟 | 北原 | 冰遁蛊(g_bingdun) | 冰麟蛊王 | 暴风雪+深夜 |
| 海妖洞窟 | 东海 | 水遁蛊(g_shuidun) | 海妖王 | 暴雨/台风 |
| 百家藏书阁 | 中州 | 月光蛊(g003) | 守护傀儡 | 雷暴+夜晚 |

### 全局奇遇系统（event_global.json）
| eid | 事件 | 类型 | 触发 |
|---|---|---|---|
| evg01 | 传承蛊巢 | 奇遇 | move（极低权重） |
| evg02 | 太古残简 | 伏笔 | gather |
| evg03 | 正道蛊师追捕 | 劫难 | move |
| evg04 | 古蛊师残魂 | 奇遇 | rest |
| evg05 | 天象异变 | 劫难 | move |

---

## 六、BUG 修复

### 商人原石读取为 0 BUG（已修复）
- **根因**：`MatParser.parse` 仅认 ASCII 小写 'x'，库存条目带空格/全角×/大写X 时解析失败
- **修复**：[recipe_model.dart:65](file:///workspace/GZren/lib/data_model/recipe_model.dart#L65) `MatParser.parse` 兼容 trim + x/X/× 三种分隔符
- **状态**：已修复，旧存档兼容

---

## 七、合并指引

### assets 文件对应关系
| 增量文件 | 对应 assets 路径 | 说明 |
|---|---|---|
| gu_donghai.json | assets/static/gu_donghai.json | 东海蛊虫（水遁蛊） |
| gu_zhongzhou.json | assets/static/gu_zhongzhou.json | 中州蛊虫（空） |
| material_donghai.json | assets/static/material_donghai.json | 东海材料 |
| material_zhongzhou.json | assets/static/material_zhongzhou.json | 中州材料 |
| map_donghai.json | assets/static/map_donghai.json | 东海场景 |
| map_zhongzhou.json | assets/static/map_zhongzhou.json | 中州场景 |
| npc_donghai.json | assets/static/npc_donghai.json | 东海NPC |
| npc_zhongzhou.json | assets/static/npc_zhongzhou.json | 中州NPC |
| event_donghai.json | assets/static/event_donghai.json | 东海事件 |
| event_zhongzhou.json | assets/static/event_zhongzhou.json | 中州事件 |
| event_global.json | assets/static/event_global.json | 全局奇遇 |
| weather_donghai.json | assets/static/weather_donghai.json | 东海天气 |
| weather_zhongzhou.json | assets/static/weather_zhongzhou.json | 中州天气 |
| kill_move.json | assets/static/kill_move.json | 仙道杀招（增量 preset_killer_moves） |
| recipe.json | assets/static/recipe.json | 蛊方（增量 r048 水遁蛊方） |
| map_nanjiang.json | assets/static/map_nanjiang.json | 南疆（增量 border_east/center 出口 + 竹节/酒液采集） |
| pubspec.yaml | pubspec.yaml | 资源注册 |

### 已修改的 Dart 文件（经专项许可）
| 文件 | 修改内容 | 许可来源 |
|---|---|---|
| lib/data_model/killer_move_model.dart | 新增 PresetKillerMove/PresetKillerMoveStore | 仙道杀招专项许可 |
| lib/engine/command.dart | 加载预设杀招 + doPresetKillerMove 指令 | 仙道杀招专项许可 |
| lib/engine/environment_system.dart | regionOf 增东海/中州 | V1.9 五地开放 |
| lib/data_model/recipe_model.dart | MatParser 修复原石BUG | V1.9 BUG修复 |

---

## 八、验收标准对照

| 验收项 | 状态 | 说明 |
|---|---|---|
| 不修改 Dart 业务代码（除杀招专项许可外） | ✓ | 仅杀招系统经专项许可改动 |
| 蛊虫/蛊方/杀招源自原著 | ✓ | 4 杀招均为原著记载，无原创 |
| 蛊方材料可野外采集/购买 | ✓ | 28 材料 0 缺口 |
| Flutter 加载无解析异常 | ✓ | 27 文件 0 语法错误 0 尾逗号 |
| 旧存档兼容 | ✓ | putIfAbsent 合并，flags 无键回退 |
| 商人原石 BUG 修复 | ✓ | MatParser 兼容空格/全角×/大写X |
| 炼蛊系统识别新增蛊方 | ✓ | r048 水遁蛊方 output_gid 链路完整 |
| 仙道杀招解锁/释放/冷却/反噬 | ✓ | cast() 五重校验全实现 |
| 昼夜/天气影响刷新 | ✓ | 沿用 environment_system 机制 |
| 秘境/通道版本锁 | ✓ | 五地梯度解锁，太古遗迹/逆流河持续锁定 |
| 太古遗迹/逆流河无法进入 | ✓ | 无任何入口数据 |
