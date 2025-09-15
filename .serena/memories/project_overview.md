# UWB Viewer System プロジェクト概要

## プロジェクトの目的
UWBViewerSystemは、UWB（Ultra-Wideband）技術を活用した位置測定・センシングシステムのiOS/macOSアプリケーションです。AndroidデバイスとのBluetooth連携により、リアルタイムな位置測定とデータ可視化を実現します。

## 技術スタック
- **プラットフォーム**: iOS 17.0+, macOS 14.0+
- **言語**: Swift 5.9+
- **UI**: SwiftUI
- **データ永続化**: SwiftData
- **通信**: Google Nearby Connections
- **アーキテクチャ**: Clean Architecture + MVVM
- **DI**: Dependency Injection パターン
- **テスト**: Swift Testing Framework

## プロジェクト構造
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

## 主な機能
1. **センシング・データ収集**: リアルタイム位置測定、データ可視化、セッション管理
2. **デバイス連携**: Bluetooth接続、デバイスペアリング、ファイル転送
3. **設定・キャリブレーション**: アンテナ設定、フロアマップ設定、システムキャリブレーション

## センシングフロー
1. フロアマップ設定
2. アンテナ設定
3. デバイスペアリング
4. システムキャリブレーション
5. センシング実行
6. データ閲覧