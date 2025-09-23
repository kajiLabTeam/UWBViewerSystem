# UWB Viewer System

[![Swift Test](https://github.com/kajiLabTeam/UWBViewerSystem/actions/workflows/swift-test.yml/badge.svg)](https://github.com/kajiLabTeam/UWBViewerSystem/actions/workflows/swift-test.yml)
[![Swift Lint](https://github.com/kajiLabTeam/UWBViewerSystem/actions/workflows/SwiftFormat.yml/badge.svg)](https://github.com/kajiLabTeam/UWBViewerSystem/actions/workflows/SwiftFormat.yml)

UWBViewerSystemは、UWB（Ultra-Wideband）技術を活用した位置測定・センシングシステムのiOS/macOSアプリケーションです。AndroidデバイスとのBluetooth連携により、リアルタイムな位置測定とデータ可視化を実現します。

## 主な機能

### 🎯 センシング・データ収集
- **リアルタイム位置測定**: UWBセンサーによる高精度な位置測定
- **データ可視化**: 取得したセンサーデータのリアルタイム表示
- **セッション管理**: センシングセッションの記録と履歴管理
- **軌跡表示**: 移動経路の可視化とトラッキング

### 🔗 デバイス連携
- **Bluetooth接続**: Android端末との無線通信
- **デバイスペアリング**: アンテナとAndroidデバイスの紐付け管理
- **ファイル転送**: 測定データの送受信機能
- **接続状態監視**: デバイス接続の状態管理と自動復旧

### 📍 設定・キャリブレーション
- **アンテナ設定**: 3D空間でのアンテナ位置・向きの設定
- **フロアマップ設定**: 測定環境のマップ登録と管理
- **システムキャリブレーション**: 測定精度向上のための校正機能

## システム要件

- **iOS**: 17.0以降
- **macOS**: 14.0以降
- **Swift**: 5.9以降
- **Xcode**: 15.0以降

## アーキテクチャ

本プロジェクトはClean Architecture + MVVMパターンを採用しており、以下の層構造で設計されています：

```
UWBViewerSystem/
├── Domain/                     # ビジネスロジック層
│   ├── Entity/                 # エンティティクラス
│   ├── UseCase/               # ビジネスロジック
│   ├── Repository/            # データアクセス層の抽象化
│   └── DataModel/             # SwiftDataモデル
├── Presentation/              # UI層
│   ├── Scenes/                # 画面とViewModel
│   ├── Router/                # 画面遷移管理
│   └── Common/                # 共通コンポーネント
└── Devices/                   # 外部デバイス連携
    └── NearByConnection/      # Bluetooth通信
```

### 技術スタック

- **UI**: SwiftUI
- **データ永続化**: SwiftData (iOS 17+)
- **通信**: Google Nearby Connections
- **アーキテクチャ**: Clean Architecture + MVVM
- **DI**: Dependency Injection パターン
- **テスト**: Swift Testing Framework

## セットアップ

### 1. プロジェクトのクローン
```bash
git clone <repository-url>
cd UWBViewerSystem
```

### 2. 依存関係の解決
```bash
# Swift Package Manager の依存関係を解決
swift package resolve
```

### 3. コード品質ツールの設定
```bash
# SwiftFormat のインストール（Homebrew）
brew install swift-format

# pre-push hook の設定（既に設定済み）
# .git/hooks/pre-push に自動フォーマット設定済み
```

### 4. ビルドと実行
```bash
# コマンドラインでのビルド
swift build

# または Xcode でプロジェクトを開く
open UWBViewerSystem.xcodeproj
```

## 新しいセンシングフロー

アプリケーションは以下の段階的なフローでセンシングを実行します：

1. **フロアマップ設定** → 測定環境の設定
2. **アンテナ設定** → UWBアンテナの位置・向き調整  
3. **デバイスペアリング** → Android端末とのペアリング
4. **システムキャリブレーション** → 測定精度の校正
5. **センシング実行** → データ収集と記録
6. **データ閲覧** → 結果の可視化と分析

## データ管理

### SwiftDataによる永続化
- **センシングセッション**: 測定セッションの記録
- **アンテナ位置データ**: 3D空間でのアンテナ配置情報
- **ペアリング情報**: デバイスとアンテナの関連付け
- **リアルタイムデータ**: 測定中に取得される位置データ
- **受信ファイル**: Android端末から転送されるファイル
- **システム活動履歴**: アプリケーションの操作ログ

### 自動データ移行
初回起動時に UserDefaults から SwiftData への自動データ移行を実行

## テスト

```bash
# ユニットテストの実行
swift test

# 特定のテストの実行  
swift test --filter "SwiftDataRepositoryTests"
```

### テスト対象
- SwiftDataRepository の CRUD 操作
- ViewModel のビジネスロジック
- UseCase 層の処理フロー
- データ変換と検証ロジック

## コード品質

### 自動フォーマット
- **SwiftFormat**: コードスタイルの統一
- **Pre-push Hook**: プッシュ前の自動フォーマット実行
- **.swift-format**: プロジェクト固有の設定ファイル

### コーディング規約
- 行長制限: 120文字
- インデント: スペース4文字
- アクセス修飾子: 適切なカプセル化
- 命名規則: Swift標準に準拠

## 開発ガイドライン

### 新機能の追加
1. **Entity層**: 必要なデータ構造を定義
2. **UseCase層**: ビジネスロジックを実装  
3. **Repository層**: データアクセス処理を実装
4. **ViewModel**: UI用のデータ変換を実装
5. **View**: SwiftUIでのUI実装
6. **テスト**: 各層の動作を検証

### Pull Request
- コードフォーマットの確認
- ユニットテストの追加と実行
- アーキテクチャ原則の遵守
- 適切なコミットメッセージ

## トラブルシューティング

### ビルドエラー
```bash
# 依存関係の再解決
swift package clean
swift package resolve

# SwiftData のスキーマ変更時
# アプリを削除してクリーンインストール
```

### 接続問題
- Bluetooth権限の確認
- Android端末のDiscovery設定
- ネットワーク環境の確認

### パフォーマンス
- リアルタイムデータの更新頻度調整
- メモリリークの確認
- バックグラウンド処理の最適化

## 貢献

プロジェクトへの貢献を歓迎します：

1. Issues での問題報告
2. Feature Request での機能提案  
3. Pull Request での改善提案
4. ドキュメントの改善

## ライセンス

このプロジェクトは [ライセンス] の下で公開されています。

## 更新履歴

### v2.0.0 (2024年12月)
- SwiftData による完全なデータ永続化システム
- 新しいセンシングフローの実装
- DI パターンの導入とアーキテクチャ改善
- 未使用画面の整理とUI改善
- 自動データ移行機能
- コード品質ツールの統合

### v1.x.x
- 基本的なUWB測定機能
- Android連携機能
- リアルタイムデータ表示

---

> **注意**: 本アプリケーションを使用する前に、使用環境でのUWB技術の規制や制限を確認してください。