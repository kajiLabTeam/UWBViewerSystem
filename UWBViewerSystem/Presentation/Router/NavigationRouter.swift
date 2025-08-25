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
                        print("🎯 NavigationStack destinationView called for route: \(route)")
                        return destinationView(for: route)
                    }
                    .onChange(of: router.path) { _, newPath in
                        print("🎯 NavigationStack path changed, count: \(newPath.count)")
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
            MainTabView()
        case .unauthenticated:
            WelcomeView()
        }
    }

    @ViewBuilder
    private func destinationView(for route: Route) -> some View {
        switch route {
        // 新しい画面遷移フロー
        case .welcomePage:
            WelcomeView()
        case .indoorMapRegistration:
            IndoorMapRegistrationView()
        case .deviceSelection:
            DeviceSelectionView()
        case .antennaPositioning:
            AntennaPositioningView()
        case .calibration:
            CalibrationView()
        case .sensingManagement:
            SensingManagementView()
        case .trajectoryView:
            TrajectoryView()
            
        // 既存の画面
        case .fieldSettingPage:
            FieldSettingView()
        case .pairingSettingPage:
            PairingSettingView()
        case .homePage:
            NewHomeView()
        case .dataCollectionPage:
            DataCollectionView()
        case .dataDisplayPage:
            DataDisplayView()
        case .connectionManagementPage:
            ConnectionManagementView()
        case .editPage:
            EditView()
        case .advertiserPage:
            AdvertiserView()
        case .mainTabView:
            MainTabView()
        }
    }
}
