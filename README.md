# Bonne-Santé

女性专属 iOS 健康助手：在 [CalorieCop](https://github.com/kaka-jun/CalorieCop) 基础上融合体检档案、Apple Watch 与月经周期。

## 文档

| 文件 | 说明 |
|------|------|
| [PRD.txt](./PRD.txt) | 产品需求文档（v2.4） |
| [DEVELOPMENT_PLAN.md](./DEVELOPMENT_PLAN.md) | 开发计划与任务分解 |
| [MEMORY.md](./MEMORY.md) | 项目记忆（架构、进度、决策） |
| [.cursor/rules/](./.cursor/rules/) | Cursor AI 开发规则 |

## 工程

iOS 源码位于 `CalorieCop/`（计划重命名为 BonneSante）。

- **技术栈**：SwiftUI、SwiftData、HealthKit、DeepSeek + Qwen VL
- **编译**：需 macOS + Xcode 15+（iOS 17.0+）
- **开发**：Windows Cursor 编码 → SSH 远程 Mac 编译

## 当前进度

- ✅ PRD 定稿、CalorieCop Clone、DeepSeek 迁移（步骤 0）
- ⏳ 阶段一：5 Tab、Theme、UnifiedHealthContext

## 快速开始（Mac）

```bash
cd CalorieCop
open CalorieCop.xcodeproj
# 配置 Secrets.swift 或应用内填入 DeepSeek / Qwen API Key
# Cmd + R 运行
```
