# Bonne-Santé 项目记忆

> 本文件供 Cursor 与开发者快速恢复上下文。详细需求见 `PRD.txt`，任务排期见 `DEVELOPMENT_PLAN.md`。

**最后更新**：2026-06-27（三环图标、晨间提醒、能量看板、饮食联合识图、编译警告清理）

---

## 近期交付（2026-06-27）

- [x] **App 图标**：三环能量（B 方案）写入 Asset Catalog；心形版备份 `docs/AppIcon-heart-variant.png`
- [x] **DailyEnergyBoard**：摄入/训练/消耗三环；三格磁贴顶对齐 + 统一副标题行高
- [x] **训练完成度**：组勾选仅计动作场次；Watch 活动计消耗（无 Watch 不回填计划 kcal）
- [x] **饮食录入**：拍照 + 文字（克数/几分饱）；拍营养表模式（Qwen VL）
- [x] **AI 教练**：ChatMessage 分 channel；对话导入今日训练计划（`WorkoutCoachPlanService`）
- [x] **晨间提醒**：`WorkoutMorningReminderService` — 设置开关/时间，仅当天一条，清理旧整周预排通知
- [x] SwiftData schema **v19**（UserSettings 提醒字段 + ChatMessage channel）
- [x] 编译警告清理（Calendar iOS 17 API、var→let、无效 await）

## 首页仪表盘设计要求（用户确认 · 2026-06-21）

> **原则**：每日会刷新的数据优先；低频健康提醒置后且篇幅紧凑。

### 信息层级（上 → 下，禁止颠倒）

1. **周期条** `PhaseBar`
2. **今日能量** `DailyEnergyBoard` — 主视觉（约 40% 权重）
3. **今日营养** `NutritionMacroBars` — 宏量条形图
4. **快捷操作** — `MorandiQuickActionButtonStyle`（主操作实心 / 次操作描边，对称）
5. **今日饮食** — 最多展示 3 条 +「还有 N 条」
6. **周期 tip** — 仅当 `cyclePhase == .unknown` 时显示一行小提示
7. **复查待办** `CompactCheckupReminders` — **页面最底部**

### 健康动态 / 复查待办（重要）

- **禁止**在首页展示大块 `RiskCard` 或健康摘要全文（总胆固醇等异常项去「健康 → 健康摘要」）
- 底部只展示**已生成的 `CheckupPlan` 复查待办**（用户在摘要里点「设置复查提醒」后才有）
- 最多 2 条紧凑行 +「全部 N 项」链到 `CheckupPlansView`
- 无 `CheckupPlan` 时不显示该区块（空即隐藏，非 Empty State 占位）

### 能量可视化（布局参考 Apple 健康，配色用莫兰迪）

- 左侧：三层同心圆环（活动 / 已摄入 / 基础）
- 右侧：大号「还可摄入」数字
- 下方：三格磁贴，**活动、基础、已摄入必须为大号可读数字**，禁止挤在圆环下的小字里
- 页脚：总消耗 + 已摄入
- 有 Watch 数据时显示 `Apple Watch` 胶囊标签

### 配色（日间必须莫兰迪）

- **禁止**日间使用高饱和系统色（亮绿 `#8BC34A`、亮橙 `#FF9500`、亮蓝 `#32ADE6` 等）
- 统一走 `Theme.swift` 语义 Token：
  - `energyActive` 灰绿 `#9BB89A`
  - `energyBasal` 雾蓝 `#8FB4E8`
  - `energyConsumed` 暖杏 `#E0C0A8`
  - `macroProtein` 雾蓝 · `macroCarbs` 燕麦 `#D4C4A8` · `macroFat` 粉紫 `#E5A5CF`
- 文字用 `adaptiveTextPrimary/Secondary`；深色模式可略提亮同类色

### HealthKit 与周期（用户关切）

- 当前读取：活动消耗、基础代谢、体重、**身高**、**出生日期→年龄**、**生理性别**、经期（`HealthKitService`）
- **身体档案预填**：`fetchBodyProfile()` → `BodyProfileSnapshot`，供 `GoalSettingView` / `OnboardingView` 自动填入；无数据再手填
- **月经**：阶段一/二在「我的 → 生理周期」手动维护；HealthKit 经期自动同步已接入（阶段三首包）
- **锻炼类型**：阶段三 `WorkoutPlanEngine`
- 验证入口：「我的 → Apple 健康同步」面板 + 首页能量看板磁贴数值 + **从 Apple 健康同步经期**
- **阶段三已接入**：HealthKit `menstrualFlow` 读取；手动与健康数据合并计算阶段

### 关键组件文件

`DailyEnergyBoard.swift` · `NutritionMacroBars.swift` · `CompactCheckupReminders.swift` · `HomeDashboardView.swift` · `Theme.swift`

---

## 阶段三：周期引擎（已启动 · 2026-06-21）

### 已交付（周期模块首包）

- [x] `CycleEngine`：手动 + HealthKit 合并、阶段计算、下次经期预测
- [x] Tips 知识库：三期各 3 条饮食 + 3 条训练，按 cycleDay 轮换
- [x] `HealthKitService.fetchMenstrualCycleSnapshot()` — 读取 `menstrualFlow`
- [x] `CycleProfile.dataSource` / `lastSyncedAt` / 经期天数设置
- [x] `@Environment(\.cyclePhase)` 全局注入（`ContentView`）
- [x] `PhaseBar` 主题色边框 + 预计来潮倒计时
- [x] `CycleTipsCard` — 首页（紧凑）+ 营养 Tab
- [x] 设置页「从 Apple 健康同步经期」

### 待办（阶段三后续）

- [x] `WorkoutPlanEngine` — 按周期生成周训练计划（含 AI 候选换动作、减脂消耗优先）
- [x] 运动日历热力图 + HealthKit workout 完成度
- [x] 门诊截图 OCR + EventKit
- [x] 心情模式（天气排课 · 舞蹈/游泳 · moodReminder 详情提醒）
- [x] 连续 7 天运动 · 满月勋章（`ExerciseStreakEngine` + 我的页）
- [x] 周期 UI 主题全局背景 + Tab 强调色联动（2026-06-22）
- [ ] 微动效 / 分享健康摘要图（P1 暂缓）

### 周期数据优先级

1. HealthKit 末次月经（若比手动更新）  
2. 手动 `CycleProfile`  
3. 合并推断周期长度（需 ≥2 次经期记录）

---

## 产品身份

- **名称**：Bonne-Santé（博纳健康）
- **定位**：女性专属 iOS 原生健康助手
- **一句话**：CalorieCop 饮食能力 + 体检档案 + Apple Watch + 月经周期 → 统一健康画像
- **目标用户**：25–45 岁、有体检需求、戴 Apple Watch 的女性

---

## 技术栈

| 层 | 技术 |
|----|------|
| UI | SwiftUI、SF Symbols、莫兰迪 Theme |
| 持久化 | SwiftData（本地 only） |
| 健康数据 | HealthKit（消耗、锻炼、经期、体重） |
| 本地 OCR | Apple Vision（体检报告） |
| 文字 AI | **DeepSeek**（`deepseek-chat`，`api.deepseek.com`） |
| 视觉 AI | **Qwen VL**（`qwen-vl-plus`，拍照识食；**默认大陆站** `dashscope.aliyuncs.com`） |
| 日历/通知 | EventKit、UserNotifications（阶段二/三） |

---

## 仓库结构

```
Bonne-Santé/
├── PRD.txt
├── DEVELOPMENT_PLAN.md
├── MEMORY.md
├── SKILLS.md
├── README.md
├── .cursor/rules/
└── BonneSante/                 # iOS 工程
    ├── BonneSante.xcodeproj
    └── BonneSante/
        ├── App/BonneSanteApp.swift
        ├── Models/
        ├── Services/
        └── Views/
```

---

## 架构核心决策

### 1. UnifiedHealthContext（最高原则）

所有 Tab 和 AI 顾问必须从 `UnifiedHealthContext` 读取数据，禁止各页面孤立算 TDEE 或健康状态。

### 2. AI 分工（已确认，无 MiniMax）

- **DeepSeek** = 唯一文字 AI
- **Qwen VL** = 拍照识食 only

### 3. 三阶段 MVP

| 阶段 | 状态 | 焦点 |
|------|------|------|
| 一 | ✅ 已完成 | 5 Tab、UnifiedContext、Onboarding、Mac 验收 |
| 二 | **~90%** | 体检导入、摘要、趋势、复查；待 PRD 真机走查 |
| 三 | **~85%** | 周期、训练、日历、门诊、心情模式、满月勋章；待微动效/分享 |

---

## 当前进度快照

### ✅ 阶段一（已全部完成）

- [x] DeepSeek 迁移、5 Tab、Theme、UnifiedHealthContext
- [x] Mac 编译验证（iOS 17.0 Deployment Target）
- [x] 阶段一回归验收全部通过
- [x] 工程重命名：Target **BonneSante**，Bundle ID **`com.bonnesante.app`**

### ⏳ 阶段二（进行中，2026-06-20）

- [x] Report / HealthMetric / RiskFlag / CheckupPlan / TodoItem 模型
- [x] Vision OCR + PDF 导入 + 强制校对页
- [x] HealthProfileEngine + RiskAnalyzer（10 条规则）
- [x] 健康 Tab（时间线 + 综合摘要 + 风险卡片）
- [x] 待办 Tab MVP + 本地通知
- [x] 首页能量看板 + 营养条形图 + 底部紧凑复查待办（用户确认层级 2026-06-21）
- [x] 首页「导入报告」+ AI 顾问健康上下文
- [x] 入库后摘要页 + 主检建议展示
- [x] **健康趋势**（化验指标 + 检查结论 Swift Charts）
- [x] **DeepSeek 粘贴 JSON / 影像随访片段**（`[{findings…}],"recommendations":[…]`）
- [x] **morphology + organSite 标签体系**（`ClinicalFindingTaxonomy`，动态归类）
- [x] **CT/MRI 长期随访管道**（肺磨玻璃结节、肝血管瘤/FNH）
- [ ] 阶段二 PRD 真机验收（`PHASE2_ACCEPTANCE.md` 场景 1–7）
- [x] 复查计划 UI（CheckupPlansView + CompactCheckupReminders）
- [x] GoalsView 统一 UnifiedHealthContext
- [x] Keychain API Key 迁移

### ✅ 2026-06-22 增量（AI 配置 + 目标设置）

- [x] **Qwen 连接测试**：`QwenAPIClient` + 设置页「测试 Qwen 连接」（按所选地区 endpoint 验证）
- [x] **Qwen 默认大陆站**：`APIRegion` 默认 `.china`；Picker 大陆站排前
- [x] **Qwen 401 根因确认**：大陆 Key（`sk-ws-`）不可用于国际 endpoint；须地区与 Key 匹配
- [x] **目标设置 HealthKit 预填**：身高 / 年龄 / 性别 / 当前体重；已有 `UserGoal` 不覆盖
- [x] **Onboarding 减脂目标步**：授权后同步健康数据；增加性别选择；显示同步来源提示
- [ ] 阶段二 PRD 真机验收
- [ ] 复查计划设置 UI（CheckupPlan 完整 UI）

---

## 2026-06-20 工作记录（影像随访专项）

### 目标

用户以**自己粘贴**的 DeepSeek 结构化数据（非 Fixture）驱动：肺结节 + 肝血管瘤/FNH 跨次随访 → 综合摘要、风险提醒、健康趋势。

### 用户真实输入格式

```
[{finding1},…,{finding4}],"recommendations":["…",…]
```

四条 findings 示例：`visitDate` 分别为 2025-03-31（肺）、2026-06-04（肺）、2025-01-17（肝）、2024-10-19（肝）。

### 今日已完成（代码）

| 模块 | 文件 / 能力 | 说明 |
|------|-------------|------|
| 粘贴解析 | `ReportPasteParser` | 优先识别影像随访片段；提取 findings 数组 + recommendations |
| 随访增强 | `ImagingFollowUpEnricher` | 肺 GGO 尺寸/Hu/相仿；肝 cm/FNH；【趋势锚点】；severity ≥ 3 |
| AI 提示词 | `ReportDeepSeekPastePrompt` | 每条 finding 必填 morphology、organSite |
| 标签体系 | `ClinicalFindingTaxonomy` | 封闭枚举；摘要科室映射；入库 morphologyTag/organSiteTag |
| 两字标题 | `ReportMetricNormalizer`、`HealthRecordAligner` | 「肺部」「肝脏」等不再误杀 |
| 跨日期去重 | `HealthRecordAligner.findingCanonicalKey` | key 含 visitDate，4 条不被合并成 2 条 |
| 校对过滤 | `ReportVerifyView.prepareFindings` | enrichAll + hasClinicalFindingContent |
| 趋势 key | `FindingNameCanonicalizer.normalizedTrendKey` | lung→`imaging.lung_nodule`，liver→`imaging.liver_lesion` |
| 趋势引擎 | `HealthFindingTrendEngine` + `FindingTrendCatalog` | 慢性病灶序列；排除超声阴性；<0.5 mm 显示「持平」非「改善」 |
| 摘要去重 | `HealthProfileEngine` | compactLine / 同名同科室合并；dedupeKey 与趋势对齐 |
| 入库 | `HealthArchiveService` | 按 visitDate 拆报告；primarySizeMillimeters |
| Fixture | `Fixtures/manual-imaging-followups.json` | 仅格式参考；**用户以粘贴为准** |

### 今日验收结果（真机/模拟器截图）

| 能力 | 状态 | 备注 |
|------|------|------|
| 综合摘要（胸外科/肝胆外科/定期随访） | ✅ | 肺结节、肝 FNH 均出现 |
| 风险提醒（肺结节优先 + 趋势锚点） | ✅ | 5.3 mm、-648 Hu |
| 肝血管瘤趋势 44→60 mm | ✅ | 两次 MRI 对比正常 |
| 子宫肌瘤趋势 | ✅ | 12→17 mm 标杆 |
| 肺结节双点趋势 | ✅ | 2025-03-31 ↔ 2026-06-04，5 mm 相仿，「仍需关注 + 持平」 |

### 已知限制 / 待办

1. 报告详情页 `assessmentNote` 偶发分号重复拼接（摘要 merge 可再 polish）。
2. 常规体检超声不得与 MRI 病灶混序列（已修 `hasLesionEvidence`）。
3. 医疗文案须带「仅供参考，请遵医嘱」。

### 明日计划（2026-06-21）

| 优先级 | 任务 | 预期产出 |
|--------|------|----------|
| P0 | 阶段二 PRD 真机走查 | 按 PRD 验收清单勾选；记录缺口 |
| P1 | 复查计划 UI（CheckupPlan） | 风险卡片可设 3/6/12 月复查 → 待办 + 通知 |
| P2 | 报告详情摘要去重 | 去掉 `；` 重复句；左栏更短更清晰 |
| P2 | 健康趋势 ↔ 报告详情跳转 | 「查看健康趋势」深链到对应 panel |
| P3 | Keychain 迁移 API Key | 自 UserDefaults 迁到 Keychain（规则目标） |
| 可选 | git commit 今日影像随访改动 | 便于版本回溯 |

### 关键文件索引

`ReportPasteParser.swift` · `ImagingFollowUpEnricher.swift` · `ReportPasteImporter.swift` · `HealthRecordAligner.swift` · `HealthArchiveService.swift` · `HealthFindingTrendEngine.swift` · `FindingNameCanonicalizer.swift` · `FindingTrendCatalog.swift` · `HealthProfileEngine.swift` · `ClinicalFindingTaxonomy.swift` · `HealthMetricTrendView.swift`

---

## 2026-06-22 工作记录（AI 配置 + 目标设置 HealthKit）

### 背景

用户拍照识食报 Qwen 401；设置目标页需手填身高/年龄/性别，与 Apple 健康数据重复。

### 今日已完成

| 模块 | 文件 / 能力 | 说明 |
|------|-------------|------|
| Qwen 验证 | `QwenAPIClient.swift` | 最小 `qwen-vl-plus` 请求；401/403 → Key 无效 |
| API 管理 | `APIKeyManager.validateQwenKey` | 测试时使用 Picker 所选地区 endpoint |
| 设置 UI | `AISettingsView` | Qwen「测试连接」；切换地区清空测试结果 |
| 地区默认 | `APIRegion` / `AISettingsView` | 默认**中国大陆**；国际 Key 与大陆 Key 不可混用 |
| 身体档案 | `BodyProfileSnapshot` + `fetchBodyProfile()` | 读身高、DOB→年龄、生理性别、体重 |
| 目标设置 | `GoalSettingView` | 无已存目标时预填；显示当前体重；同步来源 footer |
| 引导 | `OnboardingView` | 授权后 + 进入目标步时同步；性别不再写死 female |

### 验收 / 排查结论

| 项 | 结果 |
|----|------|
| 大陆 `sk-ws-` Key + 大陆 endpoint | ✅ HTTP 200 |
| 同 Key + 国际 endpoint | ❌ 401 `invalid_api_key` |
| Xcode 编译 | ✅ BUILD SUCCEEDED |

### 已知限制 / 待办

1. `GoalsView` 仍用独立 `HealthKitService` 实例；`GoalSettingView` 已改读 `UnifiedHealthContext`（后续可统一）
2. HealthKit 未授权或无档案时，目标页仍显示默认值，需用户手填
3. 性别仅映射 male/female；HealthKit `other`/`notSet` 时留手动选择
4. 今日改动**尚未 git commit**（工作区大量 BonneSante 未跟踪文件）

### 下次计划

| 优先级 | 任务 |
|--------|------|
| P0 | 真机验证：Qwen 大陆站拍照识食 + 目标设置 HealthKit 预填 |
| P1 | 阶段二 PRD 走查（`PHASE2_ACCEPTANCE.md`） |
| P2 | `GoalsView` 统一走 `healthContext`，去掉重复 HealthKit 实例 |
| P3 | git 整理：BonneSante 工程首次提交 |

### 关键文件索引（本日）

`QwenAPIClient.swift` · `APIKeyManager.swift` · `AISettingsView.swift` · `HealthKitService.swift` · `GoalSettingView.swift` · `OnboardingView.swift`

---

## CalorieCop 保留清单（禁止删除）

自然语言食物录入、拍照识食（Qwen）、食物偏好、饮食日记、热量收支、目标体重、AI 顾问、历史记录、API Key 配置、HealthKit 同步、SwiftData。

---

## 变更日志

| 日期 | 变更 |
|------|------|
| 2026-06-19 | 初版；DeepSeek 迁移；阶段一代码收尾 |
| 2026-06-20 | Mac 编译与验收通过；工程重命名为 BonneSante |
| 2026-06-20 | 阶段二核心：体检 OCR、风险引擎、健康/待办 Tab |
| 2026-06-21 | **阶段三启动**：CycleEngine 知识库、HealthKit 经期、cyclePhase 环境、CycleTipsCard |
| 2026-06-21 | **首页仪表盘重做**：每日能量/营养优先；复查待办置底；莫兰迪语义色 Token；HealthKit 同步面板 |
| 2026-06-22 | **心情模式收尾**（全周排课、moodReminder、14.5/14.7b 真机通过） |
| 2026-06-22 | **满月勋章**（ExerciseStreakEngine · 我的页） |
| 2026-06-22 | SwiftData Schema **v17** |
