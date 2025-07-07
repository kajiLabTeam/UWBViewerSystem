//
//  NavigationRouter.swift
//  UWBViewerSystem
//
//  Created by 牧野遥斗 on R 7/04/07.
//

import SwiftUI

/// 画面遷移のルーティングをまとめている
///
/// - Note: NavigationRouterModelを使用して、画面遷移を行う
/// - Note: NavigationRouterModelはObservableObjectを継承しているため、@EnvironmentObjectで使用することができる
struct NavigationRouter: View {
    @EnvironmentObject var router: NavigationRouterModel

    var body: some View {
        Group {
            NavigationStack(path: $router.path) {
                rootView
                    .navigationDestination(for: Route.self) { route in
                        destinationView(for: route)
                    }
            }
        }
        .onAppear {
            print("🔍 NavigationRouter: NavigationStack appeared")
            // アプリ起動時の初期化
            Task {
                await router.initializeApp()
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch router.appState {
        case .initializing:
            WelcomeView()
        case .authenticated:
            HomeView()
        case .unauthenticated:
            WelcomeView()
        }
    }

    @ViewBuilder
    private func destinationView(for route: Route) -> some View {
        switch route {
        case .welcomePage:
            WelcomeView()
        case .homePage:
            HomeView()
        case .editPage:
            EditView()
        }
    }
}
