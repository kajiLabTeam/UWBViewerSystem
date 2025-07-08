//
//  HomeView.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/04/07.
//
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var messageToSend = ""
    @EnvironmentObject var router: NavigationRouterModel
    
    var body: some View {
        VStack(spacing: 20) {
            // 専用広告画面への遷移
            VStack(spacing: 12) {
                Divider()
                
                Button(action: {
                    router.push(.advertiserPage)
                }) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("広告専用画面を開く")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                
                Text("端末確認機能付きの広告専用画面")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
            }
            .padding(.vertical)
            Spacer()
        }
        .padding()
    }
}

#Preview {
    HomeView()
}
