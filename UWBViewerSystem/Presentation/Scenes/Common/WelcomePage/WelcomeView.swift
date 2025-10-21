//
//  WelcomeView.swift
//  UWBViewerSystem
//
//  Created by user on 2025/02/18.
//

import SwiftUI

/// アプリの初期化画面（スプラッシュスクリーン）
struct WelcomeView: View {
    @EnvironmentObject var navigationModel: NavigationRouterModel
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.clear
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Image(systemName: "sensor")
                    .imageScale(.large)
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                    .padding(.bottom, 8)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)

                Text("UWBViewerSystem")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("UWBのセンサーを集めたり表示したりします。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
                    .frame(height: 50)
            }
        }
        .padding()
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    WelcomeView()
}
