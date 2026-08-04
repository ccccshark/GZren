#!/usr/bin/env python3
"""
满级存档生成器（蛊真人单机MUD V1.5.0）
存档结构：{ player: {...}, npcs: [...], save_time, version }
直接输出 JSON 到 /workspace/GZren/dist/save_slot1_max_level.json
用户把这个文件放到 APP 私有目录的 save/save_slot1.json 即可加载。
"""
import json
import os
from datetime import datetime, timezone

OUT_DIR = '/workspace/GZren/dist'
OUT_PATH = os.path.join(OUT_DIR, 'save_slot1_max_level.json')
os.makedirs(OUT_DIR, exist_ok=True)

# ============================================================
# 满级数据（九转巅峰 + 满属性 + 五域解锁 + 背包物资 + 满蛊）
# ============================================================

# 满级九转巅峰
MAX_LEVEL = '九转巅峰'
MAX_SLOT = 11  # levelSlot['九转巅峰']
MAX_LIFE = 999999.0
MAX_TY = 5000   # 真元上限
MAX_PHY = 1000  # 体魄
MAX_SP = 1000   # 魂力
MAX_LUCK = 100
MAX_KILLS = 0
WORLD_TIME = 120.0  # 游戏世界时间（小时）

# 玩家名与称号
P_NAME = '方源'
P_TITLE = '九转蛊尊'
P_ALIGN = '魔道'

# 出生地点：青茅山（保留主线可游玩性），若直接传送到商队附近也可
START_LOC = 'qingmao_01'

# ------------------------------------------------------------
# 背包物资（常用材料大量 + 食物/原石）
# ------------------------------------------------------------
def mats(name, count=999):
    return f'{name} x{count}'

inventory = [
    # 原石（货币）
    mats('原石', 99999),
    # ===== 食物（饱食 + 恢复） =====
    '山猪肉干 x100',
    '野果 x200',
    '鹿肉 x50',
    '青茅山酒酿 x50',
    '固本培元汤 x30',
    '益气丹 x30',
    # ===== 基础蛊材（全部 x999） =====
    mats('露水'), mats('青茅草根'), mats('野草露水'), mats('野花蜜'),
    mats('竹叶片'), mats('黄泥块'), mats('蜘蛛丝'), mats('蟾蜍皮'),
    mats('赤铁矿石'), mats('青纹豹骨'), mats('百年野山参'),
    mats('真金矿石'), mats('冰蚕丝'), mats('雷击木'), mats('月光石'),
    mats('幽冥壤'), mats('血妖藤'), mats('岁月石'), mats('寿桃'),
    mats('星辰砂'), mats('地煞土'), mats('天罡气'), mats('龙鳞'),
    # ===== 炼蛊辅助材料 =====
    mats('引气粉'), mats('凝真元液'), mats('拓窍散'),
]

# ------------------------------------------------------------
# 道痕（全大道满 1000，避免冲突）
# 冲突：气道↔血道、月道↔毒道、寿道↔岁月道、地道↔星道
# 为避免冲突伤害：每条冲突道各选一主，其余不置或少量
#   主：气道 1000 / 月道 1000 / 寿道 1000 / 地道 1000
#   次：血道 100 / 毒道 100 / 岁月道 100 / 星道 100 / 力道 500 / 食道 500 / 鬼道 500 / 兽道 500 / 运道 500
# ------------------------------------------------------------
dao_mark = {
    '气道': 1000.0,
    '力道': 500.0,
    '毒道': 100.0,
    '月道': 1000.0,
    '血道': 100.0,
    '兽道': 500.0,
    '鬼道': 500.0,
    '食道': 500.0,
    '地道': 1000.0,
    '星道': 100.0,
    '寿道': 1000.0,
    '岁月道': 100.0,
    '运道': 500.0,
}

# ------------------------------------------------------------
# 蛊虫（空窍中装满九转极品 + 背包放一些变异蛊）
# 蛊 gid 参考 gu_main.json / gu_nanjiang.json 中的九转蛊
# 若无对应模板，创建通用的九转蛊实例字段（gid=自定，name=XXX，rank=9）
# ------------------------------------------------------------
def gu_inst(inst_id, gid, name, rank=9, school='气道', cost_zhen=10, cost_life=0,
            dur_max=9999, dur=9999, feed=None, side='无明显副作用',
            combat=None, mutated=False):
    return {
        'inst_id': inst_id,
        'gid': gid,
        'name': name,
        'rank': rank,
        'school': school,
        'cost_zhen': cost_zhen,
        'cost_life': cost_life,
        'durability_max': dur_max,
        'durability': dur,
        'feed_material': feed or ['百年野山参', '真金矿石'],
        'side_effect': side,
        'combat': combat or {'type': 'active', 'power': rank * 500},
        'mutated': mutated,
    }

# 空窍蛊（11 只，按 slotMax=11 塞满：九转巅峰蛊槽 11）
gu_in_slot = [
    gu_inst('slot_01', 'gu_spring_autumn', '春秋蝉', rank=9, school='气道', cost_zhen=5,
            side='逆转时光，消耗寿元', combat={'type': 'passive', 'power': 0}),
    gu_inst('slot_02', 'gu_wisdom', '智慧蛊', rank=9, school='气道', cost_zhen=10,
            side='需要大量真元滋养'),
    gu_inst('slot_03', 'gu_sword', '剑影蛊', rank=9, school='气道', cost_zhen=8),
    gu_inst('slot_04', 'gu_moon_9', '九转月光蛊', rank=9, school='月道', cost_zhen=8),
    gu_inst('slot_05', 'gu_earth_9', '九转后土蛊', rank=9, school='地道', cost_zhen=10),
    gu_inst('slot_06', 'gu_life_9', '九转寿蛊', rank=9, school='寿道', cost_zhen=0, cost_life=100,
            side='消耗寿元才能催动，但可延寿。', combat={'type': 'passive', 'power': 0}),
    gu_inst('slot_07', 'gu_beast_9', '九转兽王蛊', rank=9, school='兽道', cost_zhen=9),
    gu_inst('slot_08', 'gu_ghost_9', '九转幽魂蛊', rank=9, school='鬼道', cost_zhen=9),
    gu_inst('slot_09', 'gu_food_9', '九转食道蛊', rank=9, school='食道', cost_zhen=5,
            combat={'type': 'passive', 'power': 0}),
    gu_inst('slot_10', 'gu_fortune_9', '九转鸿运齐天蛊', rank=9, school='运道', cost_zhen=20,
            combat={'type': 'passive', 'power': 0}),
    gu_inst('slot_11', 'gu_poison_9', '九转万毒蛊', rank=9, school='毒道', cost_zhen=10),
]

# 背包蛊（额外放几只变异/珍稀蛊，数量随意）
gu_bag = [
    gu_inst('bag_01', 'gu_mutant_soul', '变异·魂飞蛊', rank=9, school='鬼道', cost_zhen=15,
            mutated=True, side='暗伤敌魂'),
    gu_inst('bag_02', 'gu_mutant_dragon', '变异·龙息蛊', rank=9, school='气道', cost_zhen=20,
            mutated=True),
    gu_inst('bag_03', 'gu_mutant_blood', '变异·血煞蛊', rank=9, school='血道', cost_zhen=12,
            mutated=True, side='血祭己身威力更强'),
    gu_inst('bag_04', 'gu_mutant_star', '变异·星陨蛊', rank=9, school='星道', cost_zhen=18,
            mutated=True),
]

# ------------------------------------------------------------
# flags（全系统解锁/满状态）
# ------------------------------------------------------------
flags = {
    # 五域境界解锁（西漠/北原/东海/中州均为已解锁）
    'xisha_unlocked': 1,
    'beiyuan_unlocked': 1,
    'donghai_unlocked': 1,
    'zhongzhou_unlocked': 1,
    # 声望：五域势力声望拉满（便于交易通行）
    'rep_nanjiang_zongzu': 1000,   # 南疆宗族（正）
    'rep_nanjiang_xiemo': 1000,    # 南疆魔道
    'rep_xisha_shalou': 1000,      # 西漠沙楼
    'rep_xisha_shadao': 1000,      # 西漠沙盗
    'rep_beiyuan_changbai': 1000,  # 北原长白
    'rep_beiyuan_huangsha': 1000,  # 北原黄沙
    'rep_donghai_hujia': 1000,     # 东海狐家
    'rep_donghai_haizu': 1000,     # 东海海族
    'rep_zhongzhou_imperial': 1000,# 中州皇室
    'rep_zhongzhou_wanjuan': 1000, # 中州万卷阁
    # 食物饱食：满饱食，刚吃完
    'food_v2': {
        'last_eat_hour': WORLD_TIME - 0.5,
        'satiety': 36.0,   # 饱食 36 小时
        'last_hunger_tick': WORLD_TIME - 0.5,
    },
    # 储物蛊容量标记
    'storage_gu_bags': [
        {'gid': 'stor_piaomiao', 'name': '缥缈储物袋', 'cap': 2000, 'used': 0},
    ],
    # 快捷栏（默认填满几只用起来顺手的）
    'quick_bar': ['slot_01', 'slot_02', 'slot_04'],
    # 新手引导已全部完成
    'tutorial_done': [
        't_move', 't_collect', 't_catch_gu', 't_refine', 't_combat',
        't_sell', 't_rest', 't_save', 't_map', 't_region',
    ],
    # 自动存档开启
    'auto_save_enabled': 1,
    # 空窍容量扩展（第二阶段 SlotCapacity）
    'slot_capacity_max': 50000,
    # 杀招预设（几个常用杀招）
    'preset_km': [
        {'name': '万剑归宗', 'gu_list': ['slot_02', 'slot_03'], 'desc': '气道强攻'},
        {'name': '月光普照', 'gu_list': ['slot_04'], 'desc': '月道群伤'},
    ],
    # 任务：主线进度清空（保留自行游玩）
    'quest_progress': {},
    # 势力声望
    'faction_rep': {
        'nanjiang_zongzu': 1000,
        'nanjiang_xiemo': 1000,
        'xisha_shalou': 1000,
        'xisha_shadao': 1000,
        'beiyuan_changbai': 1000,
        'beiyuan_huangsha': 1000,
        'donghai_hujia': 1000,
        'donghai_haizu': 1000,
        'zhongzhou_imperial': 1000,
        'zhongzhou_wanjuan': 1000,
    },
}

# ------------------------------------------------------------
# 组合 Player
# ------------------------------------------------------------
player = {
    'name': P_NAME,
    'title': P_TITLE,
    'align': P_ALIGN,
    'level': MAX_LEVEL,
    'slot_max': MAX_SLOT,
    'slot_bonus': 5,
    'trueyuan': MAX_TY,
    'trueyuan_max': MAX_TY,
    'life_left': MAX_LIFE,
    'life_max': MAX_LIFE,
    'physique': MAX_PHY,
    'soul_power': MAX_SP,
    'dao_mark': dao_mark,
    'injure': [],
    'luck': MAX_LUCK,
    'location': START_LOC,
    'inventory': inventory,
    'gu_in_slot': gu_in_slot,
    'gu_bag': gu_bag,
    'flags': flags,
    'world_time': WORLD_TIME,
    'refine_proficiency': 999999.0,
    'tribulation': 0.0,
    'kills': MAX_KILLS,
    'alive': True,
}

# ------------------------------------------------------------
# NPC 状态（空，游戏运行时从模板重新生成/更新即可；也可放几个关键 NPC）
# ------------------------------------------------------------
npcs = []

# ------------------------------------------------------------
# 组装存档
# ------------------------------------------------------------
save_obj = {
    'player': player,
    'npcs': npcs,
    'save_time': datetime.now(timezone.utc).isoformat(),
    'version': 2,
    'save_type': 'manual',
}

with open(OUT_PATH, 'w', encoding='utf-8') as f:
    json.dump(save_obj, f, ensure_ascii=False, indent=2)

size_kb = os.path.getsize(OUT_PATH) / 1024
print(f'✅ 满级存档已生成: {OUT_PATH}')
print(f'   文件大小: {size_kb:.1f} KB')
print(f'   玩家: {P_NAME} [{P_TITLE}] ({MAX_LEVEL})')
print(f'   境界: {MAX_LEVEL} | 蛊槽: {MAX_SLOT}+5 | 真元: {MAX_TY}/{MAX_TY} | 体魄: {MAX_PHY}')
print(f'   空窍蛊: {len(gu_in_slot)} 只 | 背包蛊: {len(gu_bag)} 只 | 物资: {len(inventory)} 项')
print(f'   五域解锁: 西漠/北原/东海/中州 ✅ 南疆起始点')
print()
print('👉 使用方法：将文件重命名为 save_slot1.json，放到 APP 私有目录 save/ 下（如 /sdcard/Android/data/com.gzren/files/save/）')
print('   或通过游戏「存档管理→导入存档码」导入 JSON 内容。')
