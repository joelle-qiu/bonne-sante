# Bonne-Santé

女性专属 iOS 健康助手：在 [CalorieCop](https://github.com/kaka-jun/CalorieCop) 基础上融合体检档案、Apple Watch 与月经周期。

## 文档

| 文件 | 说明 |
|------|------|
| [PRD.txt](./PRD.txt) | 产品需求文档（v2.5） |
| [DEVELOPMENT_PLAN.md](./DEVELOPMENT_PLAN.md) | 开发计划与任务分解 |
| [MEMORY.md](./MEMORY.md) | 项目记忆（架构、进度、决策） |
| [SKILLS.md](./SKILLS.md) | Cursor Skills 功能清单 |
| [.cursor/rules/](./.cursor/rules/) | Cursor AI 开发规则 |

## 工程

iOS 源码位于 `BonneSante/`。

- **Target**：BonneSante
- **Bundle ID**：`com.bonnesante.app`
- **显示名**：Bonne-Santé
- **技术栈**：SwiftUI、SwiftData、HealthKit、DeepSeek + Qwen VL
- **编译**：macOS + Xcode 15+（iOS 17.0+）

## 当前进度

- ✅ **阶段一完成**：5 Tab、UnifiedHealthContext、Onboarding、Mac 编译与验收通过
- ⏳ **阶段二进行中**：体检报告导入、健康档案、待办 MVP

## 快速开始（Mac）

```bash
cd BonneSante
open BonneSante.xcodeproj
# 配置 Secrets.swift 或应用内填入 DeepSeek / Qwen API Key
# 选择 iPhone 模拟器 → Cmd + R 运行
```

命令行编译：

```bash
xcodebuild -scheme BonneSante \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build
```
