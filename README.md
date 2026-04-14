# WeItems

我的物品管理应用

## 系统要求

- **iOS 18.0** 或更高版本
- **iPadOS 18.0** 或更高版本

## 功能特性

- 添加和管理个人物品
- 物品分组管理
- 图片上传
- 购买链接记录
- 价格统计

## 技术栈

- Swift 5.0
- SwiftUI
- PhotosUI (图片选择)

## 支持的设备

- iPhone
- iPad

## 最低部署目标

- iOS 18.0

## 编译与打包

### 前置条件

```bash
# 确保 xcode-select 指向 Xcode.app
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### 一键构建

```bash
python3 build.py
```

可选参数：

| 参数 | 说明 |
|------|------|
| `--clean` | 构建前清理旧产物 |
| `--no-export` | 只编译 Archive，不导出 IPA |
| `--app-store` | 使用 App Store 方式导出 |

示例：

```bash
# 清理后完整构建
python3 build.py --clean

# 仅编译 Archive
python3 build.py --no-export

# App Store 提交包
python3 build.py --clean --app-store
```

构建完成后 IPA 文件在 `build/ipa/WeItems.ipa`。
