# Cursor Skills 专业功能清单

> 安装位置：`~/.cursor/skills/`（23）、`~/.cursor/skills-cursor/`（18）、Figma 插件（9）  
> 共 **50 个** Skills。Agent 会根据描述自动匹配；也可直接说「用 xxx skill 做…」。

---

## 一、UI/UX 设计（9 个）

| Skill | 专业功能 | 典型触发场景 |
|-------|----------|--------------|
| **design-decision-chain** | 页面级设计思维决策链：从用户目标 → 信息架构 → 视觉方案 → 交付 | 新页面设计、改版、设计评审 |
| **design-reference** | 设计参考库：设计系统查询、竞品分析、灵感浏览、模式检索 | 「找类似的健康 App 布局」「Material Design 按钮规范」 |
| **design-review** | 设计实现审查：对照 Spec 做保真度审计，输出评分与修复建议 | 「检查这个页面是否还原设计稿」 |
| **design-to-code** | 设计稿 → 代码：颜色、间距、字体、动效的系统化落地 | 有设计 Spec 需要高保真实现 |
| **frontend-design** | 前端视觉设计：避免「AI 模板感」，定制排版与美学方向 | 做 landing page、Dashboard UI |
| **cinematic-design** | 电影化网页设计：借鉴导演/电影视觉语言做高端展示页 | 品牌官网、产品 showcase |
| **theme-factory** | 主题工厂：10 套预设主题（颜色/字体），可一键套用或生成新主题 | 幻灯片、报告、HTML 页面统一风格 |
| **brand-guidelines** | Anthropic 官方品牌色与字体规范 | 需要统一品牌视觉的文档/页面 |
| **read-books** | 从书籍中提取设计/UX 知识，构建结构化知识库 | 「读《Don't Make Me Think》提炼要点」 |

---

## 二、文档与办公（5 个）

| Skill | 专业功能 | 典型触发场景 |
|-------|----------|--------------|
| **docx** | Word 文档：创建/编辑/解析 .docx，目录、批注、修订、模板 | 报告、备忘录、合同模板 |
| **pdf** | PDF 全能：合并/拆分/旋转/OCR/填表/加密/水印 | 体检报告 PDF 处理、文档归档 |
| **pptx** | PowerPoint：创建/编辑/解析幻灯片、模板、演讲者备注 | pitch deck、产品演示 |
| **xlsx** | 电子表格：读写 .xlsx/.csv，公式、图表、数据清洗 | 营养数据表、健康指标统计 |
| **doc-coauthoring** | 协作文档写作：三阶段流程（收集上下文 → 迭代 → 读者测试） | 技术方案、PRD、决策文档 |

---

## 三、开发与工程（10 个）

| Skill | 专业功能 | 典型触发场景 |
|-------|----------|--------------|
| **webapp-testing** | Playwright 自动化测试：本地 Web 应用功能验证、截图、日志 | 前端回归测试、UI 调试 |
| **web-artifacts-builder** | 复杂 Web Artifact：React + Tailwind + shadcn/ui 多组件应用 | 交互式原型、数据看板 |
| **mcp-builder** | MCP 服务器开发：Python FastMCP / Node MCP SDK 最佳实践 | 接入外部 API、构建 AI 工具链 |
| **claude-api** | Claude API 完整参考：模型 ID、定价、流式、Tool Use、Agent、缓存 | 集成 LLM、Agent 架构、Token 优化 |
| **sdk** | Cursor SDK 开发：TypeScript / Python SDK 集成指南 | 自动化脚本、CI 流水线 |
| **review-bugbot** | Bugbot 代码审查：自动发现 Bug 与逻辑问题 | 「审查这次改动有没有 Bug」 |
| **review-security** | 安全审查：漏洞、敏感信息、权限问题 | 「做安全审查」「检查 API Key 泄露」 |
| **review** | 统一入口：选择 Bugbot 或 Security Review | `/review` |
| **split-to-prs** | 大改动拆分为多个小 PR，便于 Code Review | 功能分支太大需要拆分 |
| **babysit** | PR 保姆：处理 Review 评论、解决冲突、修 CI 直到可合并 | 「帮我把这个 PR 修到能合并」 |

---

## 四、Cursor 平台工具（13 个）

| Skill | 专业功能 | 典型触发场景 |
|-------|----------|--------------|
| **create-skill** | 创建 Agent Skill：编写 SKILL.md 结构与规范 | 自定义项目专属 Skill |
| **skill-creator** | Skill 全生命周期：创建、优化、Eval 测试、触发准确率调优 | 改进现有 Skill 效果 |
| **create-rule** | 创建 Cursor Rules：`.cursor/rules/`、AGENTS.md | 项目编码规范、架构约束 |
| **create-hook** | Cursor Hooks：agent 事件自动化脚本 | 提交前检查、自动格式化 |
| **automate** | Cursor Automations：创建自动化工作流 | 定时任务、事件触发 |
| **migrate-to-skills** | 规则迁移：`.mdc` 规则 / Slash 命令 → Skill 格式 | 旧规则体系升级 |
| **create-subagent** | 自定义子 Agent：专项审查、调试、领域助手 | 专用 Code Reviewer |
| **loop** | 循环执行：定时重复运行 prompt/skill（如 `/loop 5m`） | 监控 CI、周期性检查 |
| **update-cursor-settings** | 修改 Cursor/VSCode `settings.json` | 字体、主题、格式化配置 |
| **update-cli-config** | 修改 Cursor CLI `cli-config.json` | CLI 权限、沙箱、审批模式 |
| **statusline** | CLI 状态栏定制：在 prompt 上方显示会话上下文 | 自定义 CLI 界面 |
| **shell** | 直接执行 Shell 命令（`/shell` 专用） | 跳过 AI 解释，直接跑命令 |
| **canvas** | 交互式 Canvas：React 实时面板，适合图表、审计报告 | 架构分析、数据可视化 |

---

## 五、创意与视觉（3 个）

| Skill | 专业功能 | 典型触发场景 |
|-------|----------|--------------|
| **algorithmic-art** | p5.js 生成艺术：随机种子、粒子系统、流场 | 动态视觉、创意编程 |
| **canvas-design** | 静态视觉设计：海报、插画，输出 PNG/PDF | 宣传图、App 启动页概念 |
| **slack-gif-creator** | Slack 优化 GIF：尺寸约束、动画概念 | 团队 Slack 趣味 GIF |

---

## 六、沟通与内容（1 个）

| Skill | 专业功能 | 典型触发场景 |
|-------|----------|--------------|
| **internal-comms** | 内部沟通写作：状态报告、3P 更新、事故报告、FAQ、Newsletter | 团队周报、项目进展汇报 |

---

## 七、Figma 集成（9 个）

| Skill | 专业功能 | 典型触发场景 |
|-------|----------|--------------|
| **figma-swiftui** | SwiftUI ↔ Figma 双向翻译 | 「把这个 Figma 设计实现成 SwiftUI」「把 SwiftUI 页面推回 Figma」 |
| **figma-use** | Figma Plugin API 基础（所有 Figma 操作的前置 Skill） | 创建/编辑节点、变量、组件 |
| **figma-generate-design** | 代码/描述 → Figma 完整页面（用设计系统组件组装） | 「把这个 Dashboard 页面建到 Figma」 |
| **figma-generate-library** | 从代码库构建 Figma 设计系统：Token、组件库、Light/Dark 主题 | 「为 Bonne-Santé 建设计系统」 |
| **figma-code-connect** | Figma Code Connect：组件 ↔ 代码片段映射（`.figma.ts`） | 设计-开发组件同步 |
| **figma-generate-diagram** | FigJam 图表：流程图、架构图、时序图、ERD、甘特图 | 系统架构、数据流可视化 |
| **figma-create-new-file** | 创建新 Figma 文件（Design / FigJam / Slides） | 新建设计文件 |
| **figma-use-figjam** | FigJam 白板操作：便签、连线、表格 | 头脑风暴、用户旅程图 |
| **figma-use-slides** | Figma Slides 演示文稿操作 | 产品 Demo 幻灯片 |

---

## Bonne-Santé 推荐组合

| 场景 | 推荐 Skills |
|------|-------------|
| UI 设计 | `design-decision-chain` + `figma-swiftui` |
| 设计落地 | `design-to-code` + `figma-generate-design` |
| 代码审查 | `review-bugbot` + `review-security` |
| 文档写作 | `doc-coauthoring`（PRD / 方案） |
| 项目规范 | `create-rule`（已有 `.cursor/rules/` 4 条规则） |
| 健康数据表 | `xlsx`（营养 / 体检数据导出分析） |
| AI 集成参考 | `claude-api`（LLM 架构与 Token 优化参考） |

---

## 安装位置速查

| 目录 | 数量 | 说明 |
|------|------|------|
| `~/.cursor/skills/` | 23 | 用户 / 通用专业 Skills |
| `~/.cursor/skills-cursor/` | 18 | Cursor 内置平台 Skills |
| Figma 插件缓存 | 9 | Figma MCP 专用 Skills |

迁移包备份：`../cursor-skills-migration.zip`（已解压至全局目录，可保留作备份）
