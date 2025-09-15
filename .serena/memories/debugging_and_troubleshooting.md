# UWB Viewer System - デバッグとトラブルシューティング

## デバッグ方法

### Xcodeデバッグ
```bash
# Xcodeでプロジェクトを開く
open UWBViewerSystem.xcodeproj

# ブレークポイント設定
# Xcode内で行番号をクリック
```

### コンソールログ確認
```bash
# macOSでのログ確認
log show --predicate 'subsystem == "com.example.UWBViewerSystem"' --info

# iOS Simulatorログ
xcrun simctl spawn booted log stream --level debug
```

### SwiftDataデバッグ
- データベースのデバッグ出力機能が実装済み
- SwiftDataRepository内でprint文によるデバッグ
- モデルコンテキストの状態確認

## よくある問題と解決方法

### 1. ビルドエラー

#### 依存関係の問題
```bash
# パッケージをクリーンして再解決
swift package clean
swift package resolve
swift build
```

#### DerivedDataの問題
```bash
# Xcodeキャッシュをクリア
rm -rf ~/Library/Developer/Xcode/DerivedData

# または reset_xcode.sh を実行
./reset_xcode.sh
```

### 2. SwiftData関連

#### スキーマ変更時のクラッシュ
- アプリを完全に削除して再インストール
- シミュレータの場合: Device → Erase All Content and Settings
- 実機の場合: アプリを削除して再インストール

#### データ移行の問題
- UserDefaultsからSwiftDataへの自動移行機能あり
- DataMigrationUsecaseで処理
- 初回起動時に自動実行

### 3. Bluetooth/Nearby接続問題

#### 権限の確認
- Info.plistでBluetooth権限設定を確認
- Privacy - Bluetooth Always Usage Description
- Privacy - Bluetooth Peripheral Usage Description

#### Android端末との接続
- Android端末でDiscoveryモードが有効か確認
- 両デバイスが同じネットワークにあるか確認
- Nearbyサービスが起動しているか確認

### 4. パフォーマンス問題

#### メモリリーク検出
```bash
# Instrumentsを使用
xcrun xctrace record --template "Leaks" --attach "UWBViewerSystem"
```

#### リアルタイムデータ更新
- 更新頻度の調整
- @Publishedプロパティの最適化
- バックグラウンド処理の確認

### 5. テスト失敗

#### テスト環境のリセット
```bash
# テストデータをクリア
swift test --skip-build --filter "cleanup"

# 特定のテストを実行
swift test --filter "SwiftDataRepositoryTests"
```

## デバッグツール

### 環境変数設定
```bash
# デバッグモードで実行
export DEBUG_MODE=1
swift run

# Xcodeの場合
# Edit Scheme → Run → Arguments → Environment Variables
```

### ログレベル設定
- デバッグビルド: 詳細ログ出力
- リリースビルド: エラーログのみ

### アサーション
- デバッグビルドでのみ有効
- `assert()`と`precondition()`を使い分け

## トラブルシューティングチェックリスト

### アプリが起動しない
- [ ] iOS/macOSバージョンを確認（17.0/14.0以上）
- [ ] Xcodeバージョンを確認（15.0以上）
- [ ] 依存関係を再解決
- [ ] DerivedDataをクリア

### データが保存されない
- [ ] SwiftDataモデルの定義を確認
- [ ] モデルコンテキストの保存を確認
- [ ] 権限設定を確認
- [ ] ディスク容量を確認

### Bluetooth接続できない
- [ ] 権限設定を確認
- [ ] Bluetoothが有効か確認
- [ ] デバイスの互換性を確認
- [ ] Nearbyサービスの状態を確認

### ビルドが遅い
- [ ] 依存関係を最小化
- [ ] インクリメンタルビルドを使用
- [ ] モジュール分割を検討
- [ ] ビルドキャッシュをクリア

## サポート情報
- Githubイシュー: プロジェクトのIssuesセクション
- ドキュメント: READMEとコード内コメント
- ログ出力: デバッグビルドで詳細ログ