# UWB Viewer System - 重要なファイルとエントリーポイント

## アプリケーションエントリーポイント

### メインアプリファイル
- **UWBViewerSystemApp.swift**: アプリケーションのエントリーポイント
  - @main属性でアプリ起動
  - SwiftDataモデルコンテナの初期化
  - 初期画面の設定

## 中核となるファイル

### データ層
1. **SwiftDataRepository.swift**
   - データアクセスの中心
   - CRUD操作の実装
   - SwiftDataとの橋渡し

2. **SwiftDataModels.swift**
   - 永続化モデルの定義
   - @Modelマクロ使用
   - リレーションシップ定義

### ビジネスロジック層
1. **SensorManager.swift**
   - センサー管理の中核
   - データ収集制御

2. **ConnectionManagementUsecase.swift**
   - Bluetooth接続管理
   - デバイス間通信

3. **DataMigrationUsecase.swift**
   - データ移行処理
   - 初回起動時の処理

### プレゼンテーション層
1. **MainTabView.swift** (推定)
   - メインナビゲーション
   - タブ切り替え管理

2. **各TabのViewModel**
   - ビジネスロジックとUIの橋渡し
   - @MainActorで UI スレッド保証

### デバイス連携
1. **NearbyConnectionManager.swift**
   - Google Nearby使用
   - Android端末との通信

## 設定ファイル

### プロジェクト設定
- **Package.swift**: パッケージ依存関係
- **Info.plist**: アプリ設定、権限
- **UWBViewerSystem.entitlements**: アプリ権限

### コード品質
- **.swift-format**: フォーマット設定
- **.swiftformat**: 代替フォーマット設定
- **Makefile**: ビルドタスク定義

### Git関連
- **.gitignore**: 除外ファイル指定
- **.githooks/**: Gitフック設定

## 重要なプロトコルとインターフェース

### Repository層
```swift
protocol DataRepositoryProtocol
protocol SwiftDataRepositoryProtocol
```

### ViewModel層
```swift
protocol ObservableObject
@MainActor クラス
```

## デバッグ用エントリーポイント

### テスト実行
```bash
# 全テスト
swift test

# 特定のテストファイル
swift test --filter "SwiftDataRepositoryTests"
```

### 開発サーバー起動（該当する場合）
```bash
# Xcodeから実行
# または
swift run UWBViewerSystem
```

## データフローの起点

### ユーザーインタラクション
1. View (SwiftUI) → タップ/入力
2. ViewModel → アクション処理
3. UseCase → ビジネスロジック実行
4. Repository → データ永続化

### データ変更通知
1. SwiftData → 変更検知
2. Repository → 通知発行
3. ViewModel → @Published更新
4. View → UI自動更新

## 初期化シーケンス

1. **アプリ起動**
   - UWBViewerSystemApp.swift
   - SwiftDataコンテナ初期化

2. **データ移行**
   - DataMigrationUsecase
   - UserDefaults → SwiftData

3. **メイン画面表示**
   - MainTabView
   - 各タブの初期化

4. **バックグラウンドサービス**
   - NearbyConnectionManager
   - センサー監視開始

## 重要な拡張ポイント

### 新機能追加時
1. Entity作成 → Domain/Entity/
2. UseCase作成 → Domain/UseCase/
3. ViewModel作成 → Presentation/Scenes/
4. View作成 → Presentation/Scenes/

### テスト追加時
1. UnitTest → UWBViewerSystemTests/
2. モック作成 → 必要に応じて