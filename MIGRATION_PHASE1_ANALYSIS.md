# DataRepository廃止計画 Phase 1 実装分析レポート

## 概要

本ドキュメントは、DataRepository（UserDefaultsベース）からSwiftDataRepository（SwiftDataベース）への段階的移行計画のPhase 1における実装分析結果をまとめたものです。

## Phase 1の目的

1. DataRepository使用箇所の完全な特定
2. SwiftDataRepositoryへの移行状況の検証
3. データ整合性の確認
4. Phase 2以降の計画策定

## DataRepository使用箇所の分析

### 1. 現在のDataRepository使用箇所

#### 1.1 DataMigrationUsecase
**ファイル**: `UWBViewerSystem/Domain/Usecase/DataMigrationUsecase.swift`

**使用状況**:
```swift
private let dataRepository: DataRepository
```

**目的**: UserDefaultsからSwiftDataへのデータマイグレーション

**Phase 1での評価**:
- ✅ **適切な使用** - マイグレーション目的で意図的に残されている
- ✅ マイグレーション完了後も一定期間必要
- ⚠️ Phase 3で削除予定

**依存機能**:
- `loadAntennaPositions()` - UserDefaultsからアンテナ位置データを読み込み
- マイグレーション完了フラグの管理

---

#### 1.2 ObservationDataUsecase
**ファイル**: `UWBViewerSystem/Domain/Usecase/ObservationDataUsecase.swift`

**使用状況**:
```swift
private let dataRepository: DataRepositoryProtocol

public init(
    dataRepository: DataRepositoryProtocol,
    uwbManager: UWBDataManager,
    preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
)
```

**Phase 1での評価**:
- ❌ **要移行** - SwiftDataRepositoryへの移行が必要
- 📝 現在はDataRepositoryProtocolに依存
- 📝 TODO コメントあり（Line 420, 518）

**移行の影響範囲**:
- UWBデータの観測セッション管理
- リアルタイムデータ収集
- データ品質監視

**Phase 2での対応**:
- DataRepositoryProtocolからSwiftDataRepositoryProtocolへ変更
- 観測セッションの保存・読み込みメソッドの実装

---

#### 1.3 FieldSettingViewModel
**ファイル**: `UWBViewerSystem/Presentation/Scenes/FloorMapTab/FieldSettingPage/FieldSettingViewModel.swift`

**使用状況**:
```swift
private let dataRepository: DataRepositoryProtocol

init(dataRepository: DataRepositoryProtocol = DataRepository())
```

**Phase 1での評価**:
- ❌ **要移行** - SwiftDataRepositoryへの移行が必要
- 📝 フィールドアンテナ設定の保存に使用

**使用メソッド**:
- `saveFieldAntennaConfiguration(_:)` - アンテナ設定の保存
- `loadFieldAntennaConfiguration()` - アンテナ設定の読み込み

**Phase 2での対応**:
- SwiftDataRepositoryを使用するように変更
- AntennaPositionDataとして保存

---

#### 1.4 AutoAntennaCalibrationViewModel
**ファイル**: `UWBViewerSystem/Presentation/Scenes/FloorMapTab/AutoAntennaCalibrationPage/AutoAntennaCalibrationViewModel.swift`

**使用状況**:
```swift
let dataRepository = DataRepository()
```

**Phase 1での評価**:
- ❌ **要移行** - 一時的なインスタンス生成
- 📝 Line 186: `setup(modelContext:)` 内で生成

**Phase 2での対応**:
- DataRepository削除
- SwiftDataRepositoryのみを使用

---

### 2. SwiftDataRepository機能の実装状況

#### 2.1 完全実装済み機能

| 機能分類 | メソッド | 実装状況 |
|---------|---------|----------|
| **センシングセッション** | saveSensingSession | ✅ 完全実装 |
| | loadSensingSession | ✅ 完全実装 |
| | loadAllSensingSessions | ✅ 完全実装 |
| | deleteSensingSession | ✅ 完全実装 |
| | updateSensingSession | ✅ 完全実装 |
| **アンテナ位置** | saveAntennaPosition | ✅ 完全実装（重複対応含む） |
| | loadAntennaPositions | ✅ 完全実装 |
| | loadAntennaPositions(for:) | ✅ 完全実装 |
| | deleteAntennaPosition | ✅ 完全実装 |
| | updateAntennaPosition | ✅ 完全実装 |
| **ペアリング** | saveAntennaPairing | ✅ 完全実装 |
| | loadAntennaPairings | ✅ 完全実装 |
| | deleteAntennaPairing | ✅ 完全実装 |
| | updateAntennaPairing | ✅ 完全実装 |
| **キャリブレーション** | saveCalibrationData | ✅ 完全実装 |
| | loadCalibrationData | ✅ 完全実装 |
| | loadCalibrationData(for:) | ✅ 完全実装 |
| | deleteCalibrationData | ✅ 完全実装 |
| | deleteAllCalibrationData | ✅ 完全実装 |
| **マップキャリブレーション** | saveMapCalibrationData | ✅ 完全実装 |
| | loadMapCalibrationData | ✅ 完全実装 |
| | loadMapCalibrationData(for:floorMapId:) | ✅ 完全実装 |
| | deleteMapCalibrationData | ✅ 完全実装 |
| | deleteAllMapCalibrationData | ✅ 完全実装 |
| **フロアマップ** | saveFloorMap | ✅ 完全実装 |
| | loadAllFloorMaps | ✅ 完全実装 |
| | loadFloorMap(by:) | ✅ 完全実装 |
| | deleteFloorMap | ✅ 完全実装 |
| | setActiveFloorMap | ✅ 完全実装 |
| **プロジェクト進行** | saveProjectProgress | ✅ 完全実装 |
| | loadProjectProgress(by:) | ✅ 完全実装 |
| | loadProjectProgress(for:) | ✅ 完全実装 |
| | loadAllProjectProgress | ✅ 完全実装 |
| | deleteProjectProgress | ✅ 完全実装 |
| | updateProjectProgress | ✅ 完全実装 |
| **リアルタイムデータ** | saveRealtimeData | ✅ 完全実装 |
| | loadRealtimeData | ✅ 完全実装 |
| | deleteRealtimeData | ✅ 完全実装 |
| **システム活動履歴** | saveSystemActivity | ✅ 完全実装 |
| | loadRecentSystemActivities | ✅ 完全実装 |
| | deleteOldSystemActivities | ✅ 完全実装 |
| **受信ファイル** | saveReceivedFile | ✅ 完全実装 |
| | loadReceivedFiles | ✅ 完全実装 |
| | deleteReceivedFile | ✅ 完全実装 |
| | deleteAllReceivedFiles | ✅ 完全実装 |

#### 2.2 データ整合性機能

| 機能 | メソッド | 実装状況 |
|-----|---------|----------|
| **重複データクリーンアップ** | cleanupDuplicateAntennaPositions | ✅ 完全実装 |
| | cleanupAllDuplicateData | ✅ 完全実装 |
| **データ検証** | validateDataIntegrity | ✅ 完全実装 |

### 3. DataRepository vs SwiftDataRepository 機能比較

| 機能分類 | DataRepository | SwiftDataRepository | 移行状況 |
|---------|---------------|---------------------|---------|
| センシングセッション | ⚠️ 基本的な保存/読み込みのみ | ✅ 完全なCRUD + クエリ | ✅ 完了 |
| アンテナ位置 | ⚠️ 配列での保存 | ✅ 個別管理 + フロアマップ紐付け | ✅ 完了 |
| ペアリング | ⚠️ 配列での保存 | ✅ 完全なCRUD | ✅ 完了 |
| キャリブレーション | ⚠️ 基本的な保存/読み込み | ✅ 個別管理 + マップベース対応 | ✅ 完了 |
| フロアマップ | ❌ 未対応 | ✅ 完全なCRUD | ✅ 完了 |
| プロジェクト進行 | ❌ 未対応 | ✅ 完全なCRUD | ✅ 完了 |
| リアルタイムデータ | ❌ 未対応 | ✅ セッション紐付け管理 | ✅ 完了 |
| システム活動履歴 | ⚠️ 配列での保存 | ✅ 完全なCRUD + 期限管理 | ✅ 完了 |
| 受信ファイル | ❌ 未対応 | ✅ 完全なCRUD | ✅ 完了 |
| データ整合性チェック | ❌ 未対応 | ✅ 検証・クリーンアップ機能 | ✅ 完了 |

## Phase 1の検証結果

### テスト実装

**ファイル**: `UWBViewerSystemTests/DataRepositoryDeprecationTests.swift`

実装したテスト:
1. ✅ SwiftDataRepository全機能動作確認
2. ✅ DataMigrationUsecase動作確認
3. ✅ データ整合性検証機能の確認
4. ✅ 重複データクリーンアップ機能の確認
5. ✅ CalibrationData CRUD操作確認
6. ✅ MapCalibrationData CRUD操作確認
7. ✅ FloorMapInfo CRUD操作確認
8. ✅ ProjectProgress CRUD操作確認

### データマイグレーション機能

**実装状況**: ✅ 完全実装

- UserDefaultsからSwiftDataへの自動マイグレーション
- 冪等性の保証（複数回実行しても安全）
- 段階的な移行（データ種別ごと）
- エラー耐性（一部失敗しても続行）

**対象データ**:
- センシングセッション
- アンテナ位置データ
- システム活動履歴

## Phase 2以降の実装計画

### Phase 2: DataRepositoryの非推奨化

**スケジュール**: Phase 1完了後

**実装内容**:
1. DataRepositoryクラスに`@available(*, deprecated, message: "Use SwiftDataRepository instead")`を追加
2. DataRepositoryProtocolに非推奨マーカーを追加
3. 使用箇所の警告を確認
4. ドキュメントを更新

**移行対象**:
- ObservationDataUsecase → SwiftDataRepositoryProtocol使用
- FieldSettingViewModel → SwiftDataRepository使用
- AutoAntennaCalibrationViewModel → DataRepository削除

### Phase 3: DataRepositoryの完全削除

**スケジュール**: Phase 2完了後

**実装内容**:
1. DataRepository.swiftファイルの削除
2. DataRepositoryProtocolの削除
3. DataMigrationUsecaseの調整（必要に応じて）
4. テストコードの更新
5. ビルド・テストの完全パス確認

**削除チェックリスト**:
- [ ] DataRepository.swiftファイル削除
- [ ] DataRepositoryProtocol削除
- [ ] 全参照箇所の削除確認
- [ ] テストコード更新
- [ ] ドキュメント更新
- [ ] ビルド成功確認
- [ ] 全テスト（61テスト）パス確認

## まとめ

### Phase 1の達成事項

✅ **完了項目**:
1. DataRepository使用箇所の完全な特定（4箇所）
2. SwiftDataRepositoryの機能確認（全機能実装済み）
3. データマイグレーション機能の実装と検証
4. データ整合性機能の実装
5. Phase 1検証テストの作成（8テストケース）
6. 詳細な実装分析ドキュメントの作成

### SwiftDataRepositoryの優位性

| 項目 | DataRepository | SwiftDataRepository |
|-----|---------------|---------------------|
| **データ永続化** | UserDefaults（メモリ制約あり） | SwiftData（効率的） |
| **リレーションシップ** | 手動管理 | 自動管理 |
| **クエリ機能** | 限定的 | 高度なクエリ対応 |
| **データ整合性** | 手動チェック | 組み込み検証機能 |
| **パフォーマンス** | 大量データで低下 | 大量データでも高速 |
| **将来性** | 非推奨予定 | Apple推奨の最新技術 |

### 移行の安全性

✅ **確認済み事項**:
- SwiftDataRepositoryは全機能が正常動作
- データマイグレーション機能が正常動作
- データ整合性チェック機能が実装済み
- 重複データのクリーンアップ機能が実装済み
- 全テストケースが成功

### 次のステップ

**Phase 2への準備完了**:
- DataRepository使用箇所が明確
- SwiftDataRepositoryの機能が十分
- マイグレーション戦略が確立
- テスト体制が整備済み

---

**作成日**: 2025-11-04
**作成者**: 🤖 Claude Code
