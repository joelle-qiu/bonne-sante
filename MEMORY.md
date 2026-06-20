# Bonne-Santé 项目记忆

> 本文件供 Cursor 与开发者快速恢复上下文。详细需求见 `PRD.txt`，任务排期见 `DEVELOPMENT_PLAN.md`。

**最后更新**：2026-06-19

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
| 视觉 AI | **Qwen VL**（`qwen-vl-plus`，拍照识食，保留 CalorieCop 原实现） |
| 日历/通知 | EventKit、UserNotifications（阶段二/三） |

---

## 仓库结构

```
Bonne-Santé/
├── PRD.txt                 # 产品需求文档 v2.4
├── DEVELOPMENT_PLAN.md     # 开发计划
├── MEMORY.md               # 本文件
├── README.md
├── .cursor/rules/          # Cursor 规则
└── CalorieCop/             # iOS 工程（待重命名为 BonneSante）
    └── CalorieCop/
        ├── App/
        ├── Models/
        ├── Services/
        │   ├── AIService/DeepSeekService.swift
        │   └── APIKeyManager.swift
        └── Views/
```

---

## 架构核心决策

### 1. UnifiedHealthContext（最高原则）

所有 Tab 和 AI 顾问必须从 `UnifiedHealthContext` 读取数据，禁止各页面孤立算 TDEE 或健康状态。

```
输入：FoodEntry、UserGoal、HealthKit、Report、TodoItem、CycleProfile
输出：dailyCalorieBudget、healthSummary、activeRiskFlags、cyclePhase、workoutProgress
```

### 2. AI 分工（已确认，无 MiniMax）

- **DeepSeek** = 唯一文字 AI（食物录入 + AI 顾问 + 可选报告辅助）
- **Qwen VL** = 拍照识食 only
- **不使用 MiniMax**

### 3. 三阶段 MVP

| 阶段 | 状态 | 焦点 |
|------|------|------|
| 一 | 进行中 (~85%) | 5 Tab、Theme、UnifiedContext、Onboarding、Keychain |
| 二 | 未开始 | 体检导入、风险、待办 |
| 三 | 未开始 | 周期联动、运动日历、门诊日历 |

---

## 当前进度快照

### ✅ 已完成

- [x] PRD v2.4
- [x] CalorieCop Clone
- [x] 步骤 0：DeepSeek 迁移
  - `DeepSeekService.swift` 为唯一文字 AI
  - `APIKeyManager` → DeepSeek 端点 + 旧 Key 迁移
  - `APIKeySetupView`、`FoodInputView`、`AIAdvisorView` 已改
- [x] 开发计划（`DEVELOPMENT_PLAN.md`）
- [x] 项目记忆（`MEMORY.md`）
- [x] Cursor 规则（`.cursor/rules/*.mdc`）
- [x] README.md

### ⏳ 待做（阶段一）

- [ ] Mac 编译验证（等 Mac mini 到货）
- [ ] 阶段一回归测试

### ✅ 阶段一代码（无 Mac 已完成）

- [x] `Theme.swift` + `CircularProgress` + `PhaseBar` + `EmptyStateView`
- [x] 5 Tab 导航（首页/健康/减脂/待办/我的）
- [x] `HomeDashboardView`（热量环 + 周期条 + tips + 快捷操作）
- [x] `UnifiedHealthContext` + `IntegratedTDEEEngine` + `CycleEngine`
- [x] `CycleProfile` + 我的页周期设置
- [x] `UserGoal` 体脂字段
- [x] 显示名 Bonne-Santé（`CFBundleDisplayName`）
- [x] `KeychainService` + `AISettingsView`（状态灯 + DeepSeek 连接测试）
- [x] `OnboardingView` 4 步 + `AppRootView` 首次启动引导
- [x] AI 顾问注入 `UnifiedHealthContext.advisorContextSummary()`
- [x] 减脂 Tab 增加 AI 营养顾问入口

---

## CalorieCop 保留清单（禁止删除）

自然语言食物录入、拍照识食（Qwen）、食物偏好、饮食日记、热量收支、目标体重、AI 顾问、历史记录、API Key 配置、HealthKit 同步、SwiftData。

---

## 设计 Token 速查

| Token | 值 |
|-------|-----|
| 主色 | `#ADC8F5` |
| 背景 | `#F9FBFF` |
| 强调（周期） | `#E5A5CF` |
| 警示 | `#E8A0A0` |
| 卡片圆角 | 16pt |
| 间距网格 | 4 的倍数，水平边距 20pt |

---

## 开发环境

- **编码**：Windows + Cursor
- **编译**：SSH 远程 Mac mini + Xcode 15+
- **最低系统**：iOS 17.0+
- **API Key 申请**：DeepSeek → platform.deepseek.com；Qwen → 阿里云 DashScope

---

## 代码规范摘要

- 新增代码作者：`jiali.qiu`
- Bug 修复作者：`zhi.qu`
- 每个新 View 需 Preview + 模拟数据
- 风险输出必须含「仅供参考，请遵医嘱」
- 体检 OCR 未经用户校对不得 `isVerified = true`

---

## 关键文件索引

| 用途 | 路径 |
|------|------|
| 文字 AI | `Services/AIService/DeepSeekService.swift` |
| Key 管理 | `Services/APIKeyManager.swift` + `Services/KeychainService.swift` |
| 食物 Prompt | `Services/AIService/FoodParsingPrompt.swift` |
| 首页 | `Views/Home/HomeDashboardView.swift` |
| 统一上下文 | `Services/UnifiedHealthContext.swift` |
| TDEE 引擎 | `Services/IntegratedTDEEEngine.swift` |
| 主题 | `Resources/Theme.swift` |
| 饮食录入 | `Views/FoodInput/FoodInputView.swift` |
| AI 顾问 | `Views/History/AIAdvisorView.swift` |
| API 设置 | `Views/Settings/AISettingsView.swift` |
| Onboarding | `Views/Onboarding/OnboardingView.swift` |
| 根视图 | `App/AppRootView.swift` |

---

## 变更日志

| 日期 | 变更 |
|------|------|
| 2026-06-19 | 初版；DeepSeek 迁移完成；三阶段计划确立 |
| 2026-06-19 | 阶段一收尾：Keychain、AISettingsView、Onboarding、AI 顾问 Context 注入 |
