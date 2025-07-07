# UWBViewerSystemプロジェクト ビルドエラー解析レポート

**作成日**: 2025年7月8日  
**プロジェクト**: UWBViewerSystem  
**プラットフォーム**: macOS (arm64)  
**開発環境**: Xcode 16.3, Swift 5.0  

## エグゼクティブサマリー

UWBViewerSystemプロジェクトにおいて、Nearby Connectionsライブラリの統合に伴うビルドエラーが発生。主要な原因は以下の2点であった：

1. **Code Coverage機能によるリンクエラー** (`___llvm_profile_runtime`シンボル不在)
2. **存在しないフレームワークへの参照** (NearbyConnectionsDynamic.framework)

これらの問題を段階的に解決し、最終的にビルドを成功させた。

## 問題の概要

### 発生状況
- **発生時期**: 2025年7月8日
- **対象プロジェクト**: UWBViewerSystem (Swift/SwiftUIアプリケーション)
- **症状**: `xcodebuild`コマンドによるビルドが失敗
- **影響範囲**: 開発環境でのビルド・実行が不可能

### プロジェクト構成
```
UWBViewerSystem/
├── UWBViewerSystem/
│   ├── Devices/
│   │   ├── NearByConnection/
│   │   └── File/
│   ├── Domain/
│   │   └── Usecase/
│   ├── Presentation/
│   │   ├── Scenes/
│   │   └── Router/
│   └── Assets.xcassets
└── UWBViewerSystem.xcodeproj/
```

## 発生したエラーの詳細分析

### エラー1: Code Coverage関連リンクエラー

#### エラーメッセージ
```
Undefined symbols for architecture arm64:
  "___llvm_profile_runtime", referenced from:
      ___llvm_profile_runtime_user in AbseilCXX17.o
ld: symbol(s) not found for architecture arm64
```

#### 技術的分析
- **根本原因**: Xcodeのビルド設定でCode Coverageが有効になっていたため、LLVMプロファイリングランタイムシンボルが要求された
- **影響コンポーネント**: AbseilCXX17ライブラリ（Nearby Connectionsの依存関係）
- **設定状況**:
  - `CLANG_COVERAGE_MAPPING = YES`
  - `ENABLE_CODE_COVERAGE = YES`

#### 問題の深刻度
- **レベル**: 高（ビルド完全失敗）
- **影響**: すべてのビルド試行が失敗

### エラー2: 存在しないフレームワーク参照エラー

#### エラーメッセージ
```
clang: error: no such file or directory: 
'/Users/.../PackageFrameworks/NearbyConnectionsDynamic.framework/Versions/A/NearbyConnectionsDynamic'
```

#### 技術的分析
- **根本原因**: プロジェクト設定ファイル（`project.pbxproj`）で、実際には存在しない`NearbyConnectionsDynamic`フレームワークへの参照が含まれていた
- **設定箇所**:
  - `packageProductDependencies`内の不正な参照
  - `XCSwiftPackageProductDependency`セクションの重複エントリ
- **実際の状況**: Nearby Connectionsパッケージには`NearbyConnections`のみが存在し、`NearbyConnectionsDynamic`は存在しない

## 原因の特定

### 根本原因分析

#### 1. Code Coverage設定の問題
- **原因**: デフォルトのXcode設定でCode Coverageが有効化されていた
- **影響**: 外部C++ライブラリ（AbseilCXX17）がプロファイリングシンボルを要求
- **検出方法**: ビルド設定の確認とエラーメッセージの解析

#### 2. パッケージ依存関係の設定ミス
- **原因**: 開発者による手動設定時の誤入力、または古いパッケージ設定の残存
- **影響**: リンカーが存在しないフレームワークを検索
- **検出方法**: プロジェクトファイルの詳細解析

### 環境要因
- **macOS**: 15.4 (24E241)
- **Xcode**: 16.3
- **アーキテクチャ**: arm64 (Apple Silicon)
- **Swift**: 5.0

## 解決策の実施

### 解決ステップ1: Code Coverage無効化

#### 実施内容
```bash
xcodebuild -project UWBViewerSystem.xcodeproj \
          -scheme UWBViewerSystem \
          -configuration Debug \
          build \
          ENABLE_CODE_COVERAGE=NO \
          CLANG_COVERAGE_MAPPING=NO
```

#### 結果
- `___llvm_profile_runtime`エラーが解消
- ただし、新たに`NearbyConnectionsDynamic`エラーが顕在化

### 解決ステップ2: プロジェクト設定の修正

#### 修正箇所1: packageProductDependencies
```diff
packageProductDependencies = (
    5C9EDDFD2E1C514F00572D26 /* NearbyConnections */,
-   5C9EDDFF2E1C514F00572D26 /* NearbyConnectionsDynamic */,
);
```

#### 修正箇所2: XCSwiftPackageProductDependency
```diff
5C9EDDFD2E1C514F00572D26 /* NearbyConnections */ = {
    isa = XCSwiftPackageProductDependency;
    package = 5C9EDDFC2E1C514F00572D26 /* XCRemoteSwiftPackageReference "nearby" */;
    productName = NearbyConnections;
};
- 5C9EDDFF2E1C514F00572D26 /* NearbyConnectionsDynamic */ = {
-     isa = XCSwiftPackageProductDependency;
-     package = 5C9EDDFC2E1C514F00572D26 /* XCRemoteSwiftPackageReference "nearby" */;
-     productName = NearbyConnectionsDynamic;
- };
```

### 解決ステップ3: ビルドキャッシュのクリア

#### 実施内容
- DerivedDataディレクトリの部分的クリア
- パッケージ依存関係の再解決

## 結果と検証

### ビルド成功確認
```
** BUILD SUCCEEDED ** [390.523 sec]
```

### 成功指標
- ✅ コンパイルエラーなし
- ✅ リンクエラーなし  
- ✅ アプリケーション署名完了
- ✅ アプリケーション起動確認

### パフォーマンス
- **ビルド時間**: 390.523秒
- **警告数**: 軽微な警告のみ（動作に影響なし）

## 技術的詳細（付録）

### 使用されたSwiftパッケージ
```
https://github.com/google/nearby (branch: main)
├── NearbyConnections
├── NearbyCoreAdapter  
├── AbseilCXX17
├── openssl_grpc
├── protobuf
├── smhasher
├── json
├── google-toolbox-for-mac
└── ukey2
```

### ビルド設定の変更点
| 設定項目 | 変更前 | 変更後 |
|---------|--------|--------|
| `ENABLE_CODE_COVERAGE` | YES | NO |
| `CLANG_COVERAGE_MAPPING` | YES | NO |
| PackageProductDependencies | NearbyConnections, NearbyConnectionsDynamic | NearbyConnections のみ |

### ファイル変更履歴
1. `UWBViewerSystem.xcodeproj/project.pbxproj` - 依存関係修正
2. ビルド設定 - Code Coverage無効化

## 今後の予防策

### 開発プロセスの改善
1. **依存関係追加時の検証**: 新しいパッケージ追加時は、実際に存在するプロダクトのみを追加
2. **ビルド設定の文書化**: Code Coverageなどの設定を明示的に管理
3. **定期的なクリーンビルド**: DerivedDataのクリアを定期実施

### 技術的対策
1. **CI/CDパイプライン**: 自動ビルド検証の導入
2. **設定管理**: `.xcconfig`ファイルによるビルド設定の明示化
3. **依存関係の監視**: パッケージ更新時の影響範囲確認

## 結論

今回のビルドエラーは、開発環境の設定問題と依存関係の設定ミスが重複して発生したものであった。段階的なデバッグにより根本原因を特定し、適切な修正を実施することで問題を解決した。

このような問題の再発防止には、開発プロセスの改善と技術的対策の両面からのアプローチが重要である。 