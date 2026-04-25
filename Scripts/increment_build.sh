#!/bin/bash
# Archive 时自动递增 Build Number，version 变更时重置为 1
# 通过 Scheme Archive Pre-Action 调用，不受 Xcode Build Phase 沙盒限制

PBXPROJ="${PROJECT_DIR}/WeItems.xcodeproj/project.pbxproj"
VERSION_FILE="${PROJECT_DIR}/.last_marketing_version"

# 检查文件存在
if [ ! -f "$PBXPROJ" ]; then
    echo "❌ project.pbxproj not found: $PBXPROJ"
    exit 1
fi

# 读取当前 MARKETING_VERSION（取第一个匹配）
MARKETING_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed -n 's/.*= *\(.*\);/\1/p')
MARKETING_VERSION=$(echo "$MARKETING_VERSION" | xargs)

if [ -z "$MARKETING_VERSION" ]; then
    echo "⚠️  MARKETING_VERSION not found, skip"
    exit 0
fi

# 读取当前 CURRENT_PROJECT_VERSION（取第一个匹配）
BUILD_NUMBER=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed -n 's/.*= *\(.*\);/\1/p')
BUILD_NUMBER=$(echo "$BUILD_NUMBER" | xargs)

if [ -z "$BUILD_NUMBER" ]; then
    echo "⚠️  CURRENT_PROJECT_VERSION not found, skip"
    exit 0
fi

# 检查 version 是否变更
LAST_VERSION=""
if [ -f "$VERSION_FILE" ]; then
    LAST_VERSION=$(cat "$VERSION_FILE")
fi

if [ "$MARKETING_VERSION" != "$LAST_VERSION" ]; then
    NEW_BUILD=1
    echo "📌 Version changed: $LAST_VERSION → $MARKETING_VERSION, reset build to 1"
else
    NEW_BUILD=$((BUILD_NUMBER + 1))
    echo "📌 Build Number: $BUILD_NUMBER → $NEW_BUILD"
fi

# 更新 pbxproj 中所有 CURRENT_PROJECT_VERSION
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = $NEW_BUILD/g" "$PBXPROJ"

# 记录当前 version
echo "$MARKETING_VERSION" > "$VERSION_FILE"

echo "✅ MARKETING_VERSION=$MARKETING_VERSION BUILD=$NEW_BUILD"
