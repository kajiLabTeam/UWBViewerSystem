//
//  NavigationRouterModel.swift
//  UWBViewerSystem
//
//  Created by 牧野遥斗 on R 7/04/07.
//

import SwiftUI

/// 画面遷移の動作をまとめている
@MainActor
class NavigationRouterModel: ObservableObject {
    @Published var path = NavigationPath()
    @Published var appState: AppState = .initializing
    @Published var currentRoute: Route = .welcomePage

    /// 画面を遷移する
    ///
    /// - Parameter route: 遷移先の画面
    /// - Note: 遷移先の画面はRouteに定義されているものを使用すること
    func push(_ route: Route) {
        path.append(route)
    }

    /// 一つ前の画面に戻る
    func pop() {
        path.removeLast()
    }

    /// 一番最初の画面に戻る
    func reset() {
        path.removeLast(path.count)
    }

    /// 指定されたルートに直接遷移する（スタックをクリアしてから）
    func navigateTo(_ route: Route) {
        reset()
        currentRoute = route
    }

    /// アプリの初期化とログイン状態チェック
    func initializeApp() async {
        appState = .initializing
        // 少し待ってからログイン状態をチェック
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

        // もしここにログイン処理とか書く場合はこちらに

        appState = .authenticated
    }

    /// ログイン成功時の処理
    func onLoginSuccess() {
        appState = .authenticated
    }
}
