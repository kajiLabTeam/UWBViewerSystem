# UWB Viewer System - 依存関係とライブラリ

## Swift Package Manager 依存関係

### 外部パッケージ
1. **swift-format** (Apple)
   - バージョン: 509.0.0以上
   - URL: https://github.com/apple/swift-format.git
   - 用途: コードフォーマット、スタイル統一
   - 使用方法: `make format` または BuildToolsディレクトリ経由

2. **Google Nearby Connections**
   - ブランチ: main
   - URL: https://github.com/google/nearby.git
   - 用途: Bluetooth通信、デバイス間接続
   - モジュール: NearbyConnections
   - Android端末との通信に使用

## システムフレームワーク

### iOS/macOS標準フレームワーク
- **SwiftUI**: UI構築
- **SwiftData**: データ永続化（iOS 17+）
- **Foundation**: 基本機能
- **Combine**: リアクティブプログラミング
- **CoreBluetooth**: Bluetooth通信（Nearbyと併用）

### プラットフォーム要件
- **iOS**: 17.0以上
- **macOS**: 14.0以上
- **Swift**: 5.9以上
- **Xcode**: 15.0以上

## ビルドツール

### SwiftFormat設定
- BuildToolsディレクトリに設定
- Package.swiftで管理
- .swift-formatファイルで設定定義

### Git Hooks
- .githooksディレクトリに格納
- pre-pushフックでフォーマット自動実行
- `make init`で設定

## パッケージ構成

### メインターゲット
```swift
.target(
    name: "UWBViewerSystem",
    dependencies: [
        .product(name: "NearbyConnections", package: "nearby")
    ],
    path: "UWBViewerSystem",
    exclude: ["UWBViewerSystemApp.swift"],
    resources: [
        .process("Assets.xcassets"),
        .copy("UWBViewerSystem.entitlements")
    ]
)
```

### テストターゲット
```swift
.testTarget(
    name: "UWBViewerSystemTests",
    dependencies: ["UWBViewerSystem"],
    path: "UWBViewerSystemTests"
)
```

## リソース管理
- **Assets.xcassets**: 画像・色リソース
- **entitlements**: アプリ権限設定
- **Info.plist**: アプリ設定

## 依存関係の管理コマンド

### パッケージ解決
```bash
swift package resolve
```

### パッケージ更新
```bash
swift package update
```

### パッケージクリーン
```bash
swift package clean
```

### ビルド（依存関係含む）
```bash
swift build
```

## 注意事項
- SwiftDataはiOS 17以降でのみ利用可能
- Google Nearbyはmainブランチを使用（安定性に注意）
- swift-formatはビルドツールとして使用（実行時依存なし）