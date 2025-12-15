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
            NavigationStack(path: self.$router.path) {
                self.rootView
                    .navigationDestination(for: Route.self) { route in
                        print("🎯 NavigationStack destinationView called for route: \(route)")
                        return self.destinationView(for: route)
                    }
                    .onChange(of: self.router.path) { _, newPath in
                        print("🎯 NavigationStack path changed, count: \(newPath.count)")
                    }
            }
        }
        .onAppear {
            print("🔍 NavigationRouter: NavigationStack appeared")
            // アプリ起動時の初期化
            Task {
                await self.router.initializeApp()
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch self.router.appState {
        case .initializing:
            WelcomeView()
        case .authenticated:
            MainTabView()
        case .unauthenticated:
            WelcomeView()
        }
    }

    @ViewBuilder
    private func destinationView(for route: Route) -> some View {
        switch route {
        // センシングフロー
        case .floorMapSetting:
            FloorMapSettingView()
        case .antennaConfiguration(let floorMapId):
            AntennaPositioningView(floorMapId: floorMapId)
        case .systemCalibration(let floorMapId):
            AutoAntennaCalibrationView(floorMapId: floorMapId)
        case .walkThroughCalibration(let floorMapId):
            WalkThroughCalibrationView(floorMapId: floorMapId)
        case .trajectoryView:
            TrajectoryView()
        case .welcomePage:
            WelcomeView()
        // メイン機能画面
        case .pairingSettingPage(let floorMapId):
            PairingSettingView(floorMapId: floorMapId)
        case .dataCollectionPage(let floorMapId):
            DataCollectionView(floorMapId: floorMapId)
        case .dataDisplayPage:
            DataDisplayView()
        case .mainTabView:
            MainTabView()
        }
    }
}
