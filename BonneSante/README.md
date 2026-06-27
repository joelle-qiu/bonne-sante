# Bonne-Santé iOS

本目录为 **Bonne-Santé** Xcode 工程。产品说明、快速开始与文档索引见仓库根目录 [README.md](../README.md)。

## 工程

| 项 | 值 |
|----|-----|
| 打开方式 | `open BonneSante.xcodeproj` |
| Target | BonneSante |
| Bundle ID | `com.bonnesante.app` |
| 最低系统 | iOS 17.0+ |

## 资源

| 文件 | 说明 |
|------|------|
| `docs/AppIcon.png` | 当前 App 图标（三环能量） |
| `docs/AppIcon-heart-variant.png` | 备选图标（心形健康） |
| `Config.xcconfig.template` / `Secrets.swift.template` | API Key 配置模板 |

## 编译

```bash
xcodebuild -scheme BonneSante \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build
```
