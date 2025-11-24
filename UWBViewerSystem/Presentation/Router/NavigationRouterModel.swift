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
    static let shared = NavigationRouterModel()

    @Published var path = NavigationPath()
    @Published var appState: AppState = .initializing
    @Published var currentRoute: Route = .welcomePage

    init() {}  // public initializer for flexibility

    /// 画面を遷移する
    ///
    /// - Parameter route: 遷移先の画面
    /// - Note: 遷移先の画面はRouteに定義されているものを使用すること
    func push(_ route: Route) {
        print("🚀 NavigationRouter.push(\(route))が呼び出されました")
        print("🚀 self instance: \(ObjectIdentifier(self))")
        print("🚀 現在のpath.count: \(self.path.count)")
        self.path.append(route)
        print("🚀 push後のpath.count: \(self.path.count)")
    }

    /// 一つ前の画面に戻る
    func pop() {
        self.path.removeLast()
    }

    /// 一番最初の画面に戻る
    func reset() {
        self.path.removeLast(self.path.count)
    }

    /// 指定されたルートに直接遷移する
    /// - Parameters:
    ///   - route: 遷移先のルート
    ///   - resetStack: スタックをクリアしてから遷移するかどうか（デフォルト: false）
    func navigateTo(_ route: Route, resetStack: Bool = false) {
        print("🔄 NavigationRouter.navigateTo(\(route), resetStack: \(resetStack)) called")
        print("🔄 Current path count: \(self.path.count)")

        if resetStack {
            self.reset()
            print("🔄 Path reset, count: \(self.path.count)")
        }

        self.currentRoute = route
        print("🔄 Current route updated to: \(self.currentRoute)")
        self.push(route)
        print("🔄 Final path count: \(self.path.count)")
    }

    /// アプリの初期化とログイン状態チェック
    func initializeApp() async {
        print("🔧 NavigationRouterModel: 初期化開始")
        self.appState = .initializing
        // 少し待ってからログイン状態をチェック
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒

        // もしここにログイン処理とか書く場合はこちらに
        print("🔧 NavigationRouterModel: 認証状態に変更")
        self.appState = .authenticated
        print("🔧 NavigationRouterModel: 初期化完了 - appState: \(self.appState)")
    }

    /// ログイン成功時の処理
    func onLoginSuccess() {
        self.appState = .authenticated
    }

    /// 指定したルートに遷移する（新しいファイル用のメソッド）
    func navigate(to route: Route) {
        self.navigateTo(route)
    }
}
