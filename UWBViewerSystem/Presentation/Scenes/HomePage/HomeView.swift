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
    
    var body: some View {
        VStack(spacing: 20) {
            // タイトル
            Text("Nearby Connections Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // 接続状態表示
            Text("状態: \(viewModel.connectState)")
                .font(.headline)
                .foregroundColor(.blue)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            // 制御ボタン
            HStack(spacing: 15) {
                Button("広告開始") {
                    viewModel.startAdvertise()
                }
                .buttonStyle(.borderedProminent)
                
                Button("発見開始") {
                    viewModel.startDiscovery()
                }
                .buttonStyle(.borderedProminent)
                
                Button("全切断") {
                    viewModel.disconnectAll()
                }
                .buttonStyle(.bordered)
                
                Button("リセット") {
                    viewModel.resetAll()
                }
                .buttonStyle(.bordered)
            }
            
            // メッセージ送信
            VStack {
                HStack {
                    TextField("送信メッセージ", text: $messageToSend)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("送信") {
                        viewModel.sendData(text: messageToSend)
                        messageToSend = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(messageToSend.isEmpty)
                }
            }
            .padding()
            
            // 受信データ一覧
            VStack {
                Text("受信データ (\(viewModel.receivedDataList.count))")
                    .font(.headline)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.receivedDataList.enumerated()), id: \.offset) { index, item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("From: \(item.0)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(item.1)
                                    .font(.body)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .padding()
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    HomeView()
}
