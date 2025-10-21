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
        // 新しいセンシングフロー
        case .floorMapSetting:
            FloorMapSettingView()
        case .antennaConfiguration:
            AntennaPositioningView()  // 改修済み：向き設定機能付き
        case .devicePairing:
            PairingSettingView()
        case .systemCalibration:
            // 自動アンテナキャリブレーション画面（2Dアフィン変換による自動キャリブレーション）
            AutoAntennaCalibrationView()
        case .sensingExecution:
            SensingManagementView()
        case .sensingDataViewer:
            DataDisplayView()
        // レガシー画面（互換性のため）
        case .welcomePage:
            WelcomeView()
        case .antennaPositioning:
            AntennaPositioningView()
        case .sensingManagement:
            SensingManagementView()
        case .trajectoryView:
            TrajectoryView()
        // メイン機能画面
        case .fieldSettingPage:
            FieldSettingView()
        case .pairingSettingPage:
            PairingSettingView()
        case .dataCollectionPage:
            DataCollectionView()
        case .dataDisplayPage:
            DataDisplayView()
        case .connectionManagementPage:
            ConnectionManagementView()
        case .advertiserPage:
            AdvertiserView()
        case .mainTabView:
            MainTabView()
        }
    }
}
