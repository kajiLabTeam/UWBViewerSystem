//
//  Router.swift
//  UWBViewerSystem
//
//  Created by 牧野遥斗 on R 7/04/07.
//

import Foundation

/// 画面遷移先の一覧
/// 遷移先は全てここに書く
enum Route: Hashable {
    case welcomePage

    // 新しいセンシングフロー
    case floorMapSetting  // フロアマップ設定（新規追加）
    case antennaConfiguration  // アンテナ設定（向き設定機能付き）
    case devicePairing  // デバイスペアリング
    case systemCalibration  // システムキャリブレーション（新規実装）
    case sensingExecution  // センシング実行
    case sensingDataViewer  // センシングデータ閲覧

    // レガシー画面（互換性のため残す）
    case antennaPositioning  // アンテナ位置の設定（フロアマップの登録）
    case sensingManagement  // センシングの管理
    case trajectoryView  // センシングデータの軌跡確認

    // メイン機能画面
    case fieldSettingPage
    case pairingSettingPage
    case dataCollectionPage
    case dataDisplayPage
    case connectionManagementPage
    case advertiserPage
    case mainTabView
}

/// アプリの初期状態を管理
enum AppState {
    case initializing
    case authenticated
    case unauthenticated
}
