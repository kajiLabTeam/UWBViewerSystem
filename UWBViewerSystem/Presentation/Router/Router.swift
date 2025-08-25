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
    case indoorMapRegistration    // 屋内マップの登録
    case deviceSelection         // 接続するデバイスの選択
    case antennaPositioning      // アンテナ位置の設定（フロアマップの登録）
    case calibration            // キャリブレーション
    case sensingManagement      // センシングの管理
    case trajectoryView         // センシングデータの軌跡確認
    
    // 既存の画面
    case fieldSettingPage
    case pairingSettingPage
    case homePage
    case dataCollectionPage
    case dataDisplayPage
    case connectionManagementPage
    case editPage
    case advertiserPage
    case mainTabView
}

/// アプリの初期状態を管理
enum AppState {
    case initializing
    case authenticated
    case unauthenticated
}
