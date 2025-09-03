#!/bin/bash

# SwiftFormatを実行してコードをフォーマット
echo "Running swift-format..."

# Swift Formatが利用可能か確認
if command -v swift-format &> /dev/null; then
    # 全てのSwiftファイルをフォーマット
    find UWBViewerSystem -name "*.swift" -type f -exec swift-format --in-place --configuration .swift-format {} +
    echo "✅ SwiftFormat completed successfully"
else
    echo "⚠️ Warning: swift-format not found. Please install it via: brew install swift-format"
    exit 1
fi

exit 0