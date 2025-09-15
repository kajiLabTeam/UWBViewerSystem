# UWB Viewer System - 詳細プロジェクト構造

## ディレクトリ構造詳細

### Domain層（ビジネスロジック）
```
Domain/
├── Entity/                     # ビジネスエンティティ
│   ├── AntennaPositionData.swift
│   ├── CommonTypes.swift
│   ├── DevicePairing.swift
│   ├── RealtimeData.swift
│   ├── ReceivedFile.swift
│   └── SensingSession.swift
├── UseCase/                    # ビジネスユースケース
│   ├── ConnectionManagementUsecase.swift
│   ├── DataMigrationUsecase.swift
│   ├── DevicePairingUsecase.swift
│   ├── FileManagementUsecase.swift
│   ├── RealtimeDataUsecase.swift
│   ├── SensingControlUsecase.swift
│   └── SensorManager.swift
├── Repository/                 # データアクセス抽象化
│   ├── DataRepository.swift   # プロトコル定義
│   └── SwiftDataRepository.swift  # SwiftData実装
├── DataModel/                  # 永続化モデル
│   ├── SwiftDataModels.swift
│   └── PersistentReceivedFile.swift
└── Utils/                      # ユーティリティ
    └── DateUtils.swift
```

### Presentation層（UI）
```
Presentation/
├── Scenes/                     # 各画面
│   ├── MainTab/               # メインタブ
│   ├── FloorMapTab/           # フロアマップ設定
│   ├── SensingTab/            # センシング実行
│   ├── SettingsTab/           # 設定画面
│   └── Common/                # 共通コンポーネント
├── Router/                     # 画面遷移管理
└── Common/                     # 共通UI部品
```

### Devices層（外部デバイス連携）
```
Devices/
└── NearByConnection/          # Bluetooth通信
    ├── NearbyConnectionManager.swift
    └── 関連ファイル
```

## 主要な画面フロー

### 1. MainTab（メインタブ）
- アプリのメインナビゲーション
- 各機能へのエントリーポイント

### 2. FloorMapTab（フロアマップ設定）
- 測定環境のマップ設定
- 3D空間の定義

### 3. SensingTab（センシング）
- リアルタイム測定
- データ収集・記録
- 軌跡表示

### 4. SettingsTab（設定）
- アンテナ位置設定
- デバイスペアリング
- システムキャリブレーション

## ビューモデルパターン
各画面は以下の構成：
- **View**: SwiftUIによるUI定義
- **ViewModel**: @MainActor, ObservableObject準拠
- **依存性注入**: コンストラクタインジェクション

## データフロー
1. View → ViewModel → UseCase → Repository → SwiftData
2. SwiftData → Repository → UseCase → ViewModel → View（データ変更通知）

## 重要なプロトコル
- `DataRepositoryProtocol`: データアクセス層の抽象化
- `SwiftDataRepositoryProtocol`: SwiftData固有の操作
- `ObservableObject`: ViewModelの基底プロトコル

## テスト構造
```
UWBViewerSystemTests/
├── Domain/
│   ├── Repository/
│   │   └── SwiftDataRepositoryTests.swift
│   └── UseCase/
│       └── 各UseCaseのテスト
└── Presentation/
    └── ViewModel/
        └── 各ViewModelのテスト
```