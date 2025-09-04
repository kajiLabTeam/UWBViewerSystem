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

                VStack(spacing: 15) {
                    Button(action: {
                        navigationModel.navigate(to: .floorMapSetting)
                    }) {
                        Label("新しいセンシングを開始", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: {
                        navigationModel.navigate(to: .mainTabView)
                    }) {
                        Label("既存データを確認", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.subheadline)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
        .padding()
        .onAppear {
            isAnimating = true
            // 自動遷移（オプション）
            // DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            //     navigationModel.navigate(to: .fieldSettingPage)
            // }
        }
    }
}

#Preview {
    WelcomeView()
}
