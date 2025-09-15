# UWB Viewer System - 推奨コマンド

## ビルドコマンド
```bash
# Swift Package Manager でのビルド
swift build

# Xcodeでプロジェクトを開く
open UWBViewerSystem.xcodeproj

# Xcodeコマンドラインビルド（iOS）
xcodebuild -project UWBViewerSystem.xcodeproj -scheme UWBViewerSystem -sdk iphonesimulator build

# Xcodeコマンドラインビルド（macOS）
xcodebuild -project UWBViewerSystem.xcodeproj -scheme UWBViewerSystem build
```

## テストコマンド
```bash
# 全てのテストを実行
swift test

# 特定のテストクラスを実行
swift test --filter "SwiftDataRepositoryTests"

# Xcodeでテストを実行
xcodebuild test -project UWBViewerSystem.xcodeproj -scheme UWBViewerSystem -sdk iphonesimulator
```

## コードフォーマット
```bash
# SwiftFormatを使用（Makefile経由）
make format

# 直接SwiftFormatを実行
cd ./BuildTools && swift build && swift run -c release swiftformat ../

# swift-formatコマンドを直接使用
swift-format --in-place --configuration .swift-format UWBViewerSystem/**/*.swift

# フォーマットスクリプトを実行
./scripts/format_code.sh
```

## Git関連
```bash
# Gitフックの設定
make init

# 手動でGitフックを設定
git config --local core.hooksPath .githooks
chmod -R +x .githooks/
```

## 依存関係管理
```bash
# Swift Package Managerの依存関係を解決
swift package resolve

# パッケージのクリーン
swift package clean

# パッケージの更新
swift package update
```

## システムコマンド（Darwin）
```bash
# ファイル検索
find . -name "*.swift" -type f

# ディレクトリ一覧
ls -la

# プロセス確認
ps aux | grep swift

# ログ確認（macOS）
log show --predicate 'subsystem == "com.example.UWBViewerSystem"' --info
```

## Xcodeキャッシュクリア
```bash
# DerivedDataのクリア
rm -rf ~/Library/Developer/Xcode/DerivedData

# リセットスクリプトを実行
./reset_xcode.sh
```