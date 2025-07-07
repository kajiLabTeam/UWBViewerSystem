//
//  UWBViewerSystemApp.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import SwiftData
import SwiftUI

@main
struct UWBViewerSystemApp: App {
    /// アプリ全体で使用するルーター
    /// - Note: NavigationRouterModelはObservableObjectを継承しているため、@StateObjectで使用することができる
    @StateObject var router = NavigationRouterModel()

    var body: some Scene {
        WindowGroup {
            NavigationRouter()
                .environmentObject(router)
        }
    }
}
