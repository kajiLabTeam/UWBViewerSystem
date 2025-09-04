#!/bin/bash

# SwiftFormatを使用してコードをフォーマット
echo "🚀 Running SwiftFormat..."

# カレントディレクトリがプロジェクトルートかチェック
if [ ! -f ".swift-format" ]; then
    echo "❌ .swift-format file not found. Please run this script from the project root."
    exit 1
fi

# SwiftFormatが利用可能か確認
if ! command -v swift-format &> /dev/null; then
    echo "❌ swift-format not found. Please install it via: brew install swift-format"
    exit 1
fi

# 全てのSwiftファイルをフォーマット
find UWBViewerSystem -name "*.swift" -type f -exec swift-format --in-place --configuration .swift-format {} +

echo "✅ SwiftFormat completed successfully!"

# フォーマット後の変更があるかチェック（git環境の場合）
if git rev-parse --git-dir > /dev/null 2>&1; then
    if [[ $(git diff --name-only) ]]; then
        echo "📝 Files were formatted. The following files have been modified:"
        git diff --name-only
    else
        echo "✨ No formatting changes were needed."
    fi
fi