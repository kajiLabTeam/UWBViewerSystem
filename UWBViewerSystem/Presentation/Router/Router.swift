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

    // センシングフロー
    case floorMapSetting  // フロアマップ設定
    case antennaConfiguration  // アンテナ設定（向き設定機能付き）
    case systemCalibration  // システムキャリブレーション（自動アンテナキャリブレーション）
    case trajectoryView  // センシングデータの軌跡確認

    // メイン機能画面
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
