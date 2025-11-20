#!/bin/bash

# InfraView 运行脚本
# 使用方法: ./run.sh

set -e

PROJECT_NAME="InfraView"
XCODE_PROJECT="${PROJECT_NAME}.xcodeproj"
SCHEME="${PROJECT_NAME}"

echo "🔨 正在构建 ${PROJECT_NAME}..."

# 构建项目
xcodebuild \
    -project "${XCODE_PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -derivedDataPath ./build \
    build

# 查找构建的应用
APP_PATH=$(find ./build -name "${PROJECT_NAME}.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ 找不到构建的应用"
    exit 1
fi

echo "✅ 构建完成: ${APP_PATH}"
echo "🚀 正在启动应用..."

# 运行应用
open "${APP_PATH}"

echo "✨ 应用已启动！"

