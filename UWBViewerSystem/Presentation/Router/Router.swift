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
    case homePage
    case editPage
    case advertiserPage
}

/// アプリの初期状態を管理
enum AppState {
    case initializing
    case authenticated
    case unauthenticated
}
