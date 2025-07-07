//
//  WelcomeView.swift
//  UWBViewerSystem
//
//  Created by user on 2025/02/18.
//

import SwiftUI

/// アプリの初期化画面（スプラッシュスクリーン）
struct WelcomeView: View {

    var body: some View {
        ZStack {
            Color.clear
                .edgesIgnoringSafeArea(.all)

            VStack {
                Image(systemName: "sensor")
                    .imageScale(.large)
                    .foregroundColor(.accentColor)
                    .padding(.bottom, 8)

                Text("UWBViewerSystem")
                    .font(.title)
                    .fontWeight(.bold)

                Text("UWBのセンサーを集めたり表示したりします。")

                Spacer()
                    .frame(height: 50)
            }
        }
        .padding()
    }
}

#Preview {
    WelcomeView()
}
