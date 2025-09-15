# UWB Viewer System - コーディングスタイルと規約

## Swift コーディング規約

### 基本設定
- **行長制限**: 120文字
- **インデント**: スペース4文字
- **タブ幅**: 4文字
- **最大空行数**: 1行
- **ファイルスコープのプライベート宣言**: private

### 命名規則
- **変数・関数名**: lowerCamelCase（例: `userName`, `calculateDistance()`）
- **型名・プロトコル名**: UpperCamelCase（例: `UserData`, `DataRepositoryProtocol`）
- **定数**: lowerCamelCase（enumのケースも同様）
- **ASCII文字のみ使用**: 識別子はASCII文字のみ

### コードスタイル
- **セミコロン不使用**: 行末にセミコロンを使わない
- **早期リターン**: 可能な場合は早期リターンを使用
- **Force Unwrap**: 必要な場合のみ使用可（NeverForceUnwrap: false）
- **暗黙的アンラップオプショナル**: 必要な場合のみ使用可
- **ブロックコメント禁止**: `/* */`の使用禁止、`//`を使用
- **ドキュメントコメント**: `///`を使用

### SwiftUIとMVVM
- **View**: UIのみを担当、ロジックは含まない
- **ViewModel**: `@MainActor`でUIスレッドでの実行を保証
- **ObservableObject**: ViewModelは必ず`ObservableObject`を準拠
- **@Published**: UIに反映するプロパティに使用

### アーキテクチャ規約
- **Clean Architecture**: Domain層、Presentation層、Devices層の分離
- **依存性の方向**: Presentation → Domain ← Devices
- **プロトコル指向**: 具象クラスではなくプロトコルに依存
- **DI（依存性注入）**: コンストラクタインジェクションを使用

### SwiftData規約
- **Model定義**: `@Model`マクロを使用
- **プロパティ**: 必要に応じて`@Attribute`、`@Relationship`を使用
- **マイグレーション**: スキーマ変更時は適切に対応

### エラーハンドリング
- **do-catch**: エラーの可能性がある場合は適切にハンドリング
- **try?**: エラーを無視しても問題ない場合のみ使用
- **エラーログ**: 本番環境では適切にログ出力

### テスト規約
- **テストファイル名**: `[対象クラス名]Tests.swift`
- **テストメソッド名**: `test[機能名]_[条件]_[期待結果]()`
- **AAA パターン**: Arrange, Act, Assert の構造
- **モック使用**: 外部依存はモックで置き換え

### インポート順序
1. システムフレームワーク（Foundation, SwiftUI等）
2. サードパーティライブラリ
3. プロジェクト内のモジュール
（OrderedImports: true により自動整列）

### その他の規約
- **1行1変数宣言**: 複数の変数を1行で宣言しない
- **case文**: 1行に1つのケース
- **trailing closure**: 引数が1つの場合のみ使用
- **早期Exit**: guard文を積極的に活用
- **型推論**: 可能な限り型推論を活用（UseShorthandTypeNames: true）