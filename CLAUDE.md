## 言語設定
**重要**：このプロジェクトでは、Claude Codeは必ず日本語で回答してください。技術用語は必要に応じて英語のまま使用可能です

## 作業実行方針
**重要**：すべての作業実行は以下の方針に従ってください
- すべての実行はタスクに分割して行う
- 複雑な作業や調査が必要な場合はサブエージェント（Task tool）を使用して実行する
- 並列実行可能なタスクは積極的に並列化する

## 開発フロー

### Git/GitHub運用
- **GitHub Flow**を採用し、ブランチベースの開発を実施します
- **ghコマンド**を使用してissueの作成、PRの作成・管理を行います
- 作業前に適切なissueを作成し、ブランチ名はissue番号を含めてください
- コミットメッセージは簡潔かつ明確に記述します
- PRマージ前にレビューコメントがある場合は対応します

### テストフレームワーク
- **Swift Testing（SwiftTest）**を使用します
- **XCTestは使用しません**
- テストカバレッジは100%を目標とし、すべてのテストが通ることを確認します
- 新規機能開発時は必ず対応するテストを作成します

### 終了前チェックリスト
1. **SwiftFormatの実行**: `make format`コマンドでコードフォーマットを統一
2. **テストの実行**: すべてのSwiftTestが100%通ることを確認
3. **ビルドの確認**: エラーなくビルドが完了することを確認
4. **不要なコードの削除**: デバッグ用コード、コメントアウトされた古いコード等を削除

## アーキテクチャ

### 全体構造
本プロジェクトは**Clean Architecture + MVVM**パターンを採用しています。

### レイヤー構成

#### 1. Domain層 (`Domain/`)
- **Entity**: ビジネスエンティティ（ObservationData, DevicePairing, SensingSession等）
- **Repository**: データアクセスインターフェース（DataRepository, SwiftDataRepository）
- **Usecase**: ビジネスロジック（CalibrationUsecase, SensorManager, ConnectionManagementUsecase等）
- **DataModel**: 永続化モデル（SwiftData用のPersistent〜モデル）
- **Utils**: ユーティリティクラス（AffineTransform, LeastSquaresCalibration等）

#### 2. Presentation層 (`Presentation/`)
- **Scenes**: 画面単位のView/ViewModel
  - FloorMapTab: フロアマップ関連画面
  - SensingTab: センシング関連画面
  - SettingsTab: 設定画面
  - MainTab: メインタブコンテナ
  - Common: 共通画面（Welcome等）
- **Components**: 再利用可能なUIコンポーネント
- **Router**: ナビゲーション管理（NavigationRouter, SensingFlowNavigator）

#### 3. Devices層 (`Devices/`)
- UWBデバイス関連の通信・制御ロジック

### データフロー
1. View → ViewModel → Usecase → Repository → SwiftData/External API
2. ViewModelは@Published/@StateObjectでViewと双方向バインディング
3. Usecaseは複数のRepositoryを組み合わせてビジネスロジックを実装
4. Repositoryは実際のデータアクセスを抽象化

### 主要な技術スタック
- **SwiftUI**: UIフレームワーク
- **SwiftData**: データ永続化
- **Swift Testing**: テストフレームワーク
- **NearbyConnections**: デバイス間通信
- **swift-format**: コードフォーマッター

### 命名規則
- View: `〜View.swift`
- ViewModel: `〜ViewModel.swift`
- Usecase: `〜Usecase.swift`
- Repository: `〜Repository.swift`
- Entity/Model: 単数形の名詞

### コード品質管理
- 不要なimport文は削除
- デッドコードは削除
- コメントは必要最小限に留め、コード自体を自己文書化
- SwiftFormatルールに従ったフォーマット
- 警告は0を維持
