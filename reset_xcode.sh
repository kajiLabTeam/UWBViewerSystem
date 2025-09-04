#!/bin/bash

# Xcodeプロジェクトのパッケージ設定をリセットするスクリプト

echo "Cleaning Xcode project package references..."

# 1. DerivedDataをクリーンアップ
echo "Cleaning DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/UWBViewerSystem-*

# 2. .buildディレクトリを削除
echo "Removing .build directory..."
rm -rf .build

# 3. SPM関連のXcodeプロジェクト設定をリセット
echo "Resetting SPM configurations..."
rm -rf UWBViewerSystem.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
rm -rf UWBViewerSystem.xcodeproj/project.xcworkspace/xcuserdata
rm -rf UWBViewerSystem.xcodeproj/xcuserdata

# 4. パッケージ解決
echo "Resolving packages..."
swift package resolve

echo "Done! Now open the project in Xcode and it should re-download packages."
echo "If you still see errors, try:"
echo "1. Open Xcode"
echo "2. File > Packages > Reset Package Caches"
echo "3. File > Packages > Update to Latest Package Versions"