<p align="center">
  <img src="BonneSante/docs/AppIcon.png" width="120" height="120" alt="Bonne-Santé App Icon">
</p>

<h1 align="center">Bonne-Santé</h1>

<p align="center">
  <strong>博纳健康</strong> — 女性专属 iOS 原生健康助手<br>
  在 <a href="https://github.com/kaka-jun/CalorieCop">CalorieCop</a> 饮食能力之上，融合体检档案、Apple Watch 与月经周期，形成统一、可行动的个人健康画像。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.0+-blue" alt="iOS 17.0+">
  <img src="https://img.shields.io/badge/SwiftUI-SwiftData-orange" alt="SwiftUI SwiftData">
  <img src="https://img.shields.io/badge/HealthKit-Vision-green" alt="HealthKit Vision">
</p>

---

## 核心能力

### 日常营养与减脂

- **自然语言录入**：用中文描述一餐（如「一碗米饭，两个鸡蛋」），AI 自动解析热量与宏量
- **拍照识食 + 文字补充**：可拍餐盘并补充克数、几分饱，联合估算更准确
- **拍营养表**：Qwen VL 识别包装营养表，批量录入
- **热量收支看板**：摄入 / 训练 / 消耗三环 + 莫兰迪配色能量仪表盘（磁贴顶对齐）
- **AI 营养顾问**：基于饮食历史与健康档案对话（DeepSeek）
- **目标体重追踪**：HealthKit 预填身高、年龄、性别与体重

### 健康档案

- **体检报告导入**：Apple Vision 本地 OCR + PDF，强制校对后入库
- **综合健康摘要**：化验指标、影像结论、风险卡片与主检建议
- **健康趋势**：化验指标与影像随访（如肺结节、肝病灶）Swift Charts 可视化
- **复查待办闭环**：设置复查提醒 → 首页紧凑展示 → 本地通知 → 完成滚动

### 周期与训练（阶段三）

- **月经周期引擎**：手动记录 + HealthKit 经期同步，阶段预测与 Tips
- **周期联动 UI**：PhaseBar、周期主题色与 Tab 强调色
- **智能训练计划**：按周期阶段生成周课表，支持 AI 换动作与心情模式排课
- **AI 教练对话**：场次内对话保留上下文，支持「导入今日训练计划」写入动作清单
- **完成度分离**：组勾选只计动作完成；消耗进度优先 Apple Watch 当日/当周活动
- **训练日晨间提醒**：我的 → 训练提醒，可开关、自定义时间，仅当天有排课时推送一条
- **营养与排课同步**：Mon–Sun 七日营养目标随本周训练安排切换
- **运动日历与成就**：HealthKit 锻炼完成度、连续 7 天运动 · 满月勋章

### 统一架构

所有 Tab 与 AI 顾问共享 **`UnifiedHealthContext`**：体检异常影响热量预算，Watch 运动更新 TDEE，复查计划流入待办——禁止各页面孤立维护健康状态。

---

## 技术栈

| 层 | 技术 |
|----|------|
| UI | SwiftUI、SF Symbols、莫兰迪 Theme |
| 持久化 | SwiftData（数据仅存本地） |
| 健康数据 | HealthKit（消耗、锻炼、经期、体重） |
| 本地 OCR | Apple Vision（体检报告，无需 API Key） |
| 文字 AI | **DeepSeek**（`deepseek-chat`）— 食物解析、顾问、报告结构化辅助 |
| 视觉 AI | **Qwen VL**（`qwen-vl-plus`）— 拍照识食 |
| 日历 / 通知 | EventKit、UserNotifications |

---

## 文档

| 文件 | 说明 |
|------|------|
| [PRD.txt](./PRD.txt) | 产品需求文档（v2.5） |
| [DEVELOPMENT_PLAN.md](./DEVELOPMENT_PLAN.md) | 开发计划与任务分解 |
| [MEMORY.md](./MEMORY.md) | 项目记忆（架构、进度、决策） |
| [PHASE2_ACCEPTANCE.md](./PHASE2_ACCEPTANCE.md) | 真机走查验收清单 |
| [SKILLS.md](./SKILLS.md) | Cursor Skills 功能清单 |
| [.cursor/rules/](./.cursor/rules/) | Cursor AI 开发规则 |

---

## 工程信息

iOS 源码位于 `BonneSante/`。

| 项 | 值 |
|----|-----|
| Target | BonneSante |
| Bundle ID | `com.bonnesante.app` |
| 显示名 | Bonne-Santé |
| 最低系统 | iOS 17.0+ |
| 编译环境 | macOS + Xcode 15+ |

### 目录结构

```
bonne-sante/
├── PRD.txt · MEMORY.md · DEVELOPMENT_PLAN.md
├── Fixtures/                    # 影像随访等测试数据
└── BonneSante/
    ├── BonneSante.xcodeproj
    └── BonneSante/
        ├── App/                 # 入口与 Tab 路由
        ├── Models/              # SwiftData 模型
        ├── Services/            # 引擎、AI、HealthKit、OCR
        ├── Views/               # 首页 / 营养 / 健康 / 训练 / 我的
        └── Resources/           # Theme、Assets
```

---

## 快速开始

```bash
git clone git@github.com:joelle-qiu/bonne-sante.git
cd bonne-sante/BonneSante
open BonneSante.xcodeproj
```

1. 在 Xcode 中选择 **Signing & Capabilities**，配置开发团队
2. 首次运行可在 **我的 → AI 设置** 填入 DeepSeek / Qwen API Key（或使用 `Secrets.swift`）
3. 选择 iPhone 模拟器或真机 → **Cmd + R** 运行

命令行编译：

```bash
xcodebuild -scheme BonneSante \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build
```

### API Key 说明

| 能力 | 服务商 | 是否必需 |
|------|--------|----------|
| 文字录入、AI 顾问、报告辅助 | [DeepSeek](https://platform.deepseek.com) | 推荐 |
| 拍照识食 | [Qwen DashScope](https://dashscope.console.aliyun.com) | 可选 |
| 体检 OCR | Apple Vision（设备端） | 无需 Key |

API Key 存储于本地 Keychain，不上传至任何服务器。

---

## 开发进度

| 阶段 | 状态 | 要点 |
|------|------|------|
| **阶段一** | ✅ 完成 | 5 Tab、UnifiedHealthContext、Onboarding、Mac 编译验收 |
| **阶段二** | ~90% | 体检导入、健康摘要、趋势、复查待办、AI 配置 |
| **阶段三** | ~90% | 周期引擎、训练计划、AI 教练、营养同步、Watch 消耗优先、晨间提醒 |

> App 图标：当前使用三环能量方案（`docs/AppIcon.png`）；心形备选见 `docs/AppIcon-heart-variant.png`。

真机验收进度见 [PHASE2_ACCEPTANCE.md](./PHASE2_ACCEPTANCE.md)（当前约 **73%** 项已勾选）。

---

## 隐私与安全

- 饮食、体检、待办数据 **仅存本地** SwiftData
- HealthKit 数据不离开设备
- 体检报告未经用户校对不会写入健康引擎（`isVerified = false`）
- 健康与营养建议均标注「仅供参考，请遵医嘱」，不做医学诊断

---

## 致谢

本项目基于 [CalorieCop](https://github.com/kaka-jun/CalorieCop) 改造扩展，保留其自然语言/拍照识食、饮食日记与 AI 顾问等核心能力，并在此基础上构建女性健康管理闭环。

---

<p align="center">
  <br>
  <em>
    <strong>Bonne-Santé，读懂你的体检单，跟上你的生理周期，把每一餐、每一次运动、每一份复查提醒，编织成只属于你的健康故事。</strong><br>
    不是又一个冰冷的数字 App——而是你贴身的、会思考、会提醒、会随周期调整的健康伙伴。
  </em>
  <br><br>
  <strong>懂周期，更懂健康。从今天起，把健康交给自己。</strong>
</p>
