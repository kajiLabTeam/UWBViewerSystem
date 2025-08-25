//
//  AdvertiserView.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import SwiftUI

struct AdvertiserView: View {
    @StateObject private var viewModel = AdvertiserViewModel()
    @State private var selectedRequest: ConnectionRequest?
    @State private var showingConnectionAlert = false
    @State private var messageText = ""
    
    var body: some View {
        TabView {
            // 制御タブ
            ControlView()
                .tabItem {
                    Label("制御", systemImage: "antenna.radiowaves.left.and.right")
                }
            
            // 端末管理タブ
            DeviceManagementView()
                .tabItem {
                    Label("端末管理", systemImage: "externaldrive.connected.to.line.below")
                }
            
            // メッセージタブ
            MessagesView()
                .tabItem {
                    Label("メッセージ", systemImage: "message")
                }
        }
        .navigationTitle("広告専用画面")
        .alert("接続要求", isPresented: $showingConnectionAlert, presenting: selectedRequest) { request in
            Button("承認") {
                viewModel.approveConnection(for: request)
                selectedRequest = nil
            }
            Button("拒否", role: .cancel) {
                viewModel.rejectConnection(for: request)
                selectedRequest = nil
            }
        } message: { request in
            VStack(alignment: .leading) {
                Text("端末名: \(request.deviceName)")
                Text("ID: \(request.endpointId)")
                Text("要求時刻: \(request.requestTime, style: .time)")
            }
        }
        .onChange(of: viewModel.connectionRequests) { _, newRequests in
            if let latestRequest = newRequests.last {
                selectedRequest = latestRequest
                showingConnectionAlert = true
            }
        }
    }
    
    // MARK: - 制御ビュー
    @ViewBuilder
    private func ControlView() -> some View {
        VStack(spacing: 20) {
            Text("Nearby Connection 広告制御")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                Text("状態: \(viewModel.statusMessage)")
                    .foregroundColor(viewModel.isAdvertising ? .green : .secondary)
                
                HStack(spacing: 16) {
                    Button(action: {
                        viewModel.startAdvertising()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("広告開始")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAdvertising)
                    
                    Button(action: {
                        viewModel.stopAdvertising()
                    }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("広告停止")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.isAdvertising)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - 端末管理ビュー
    @ViewBuilder
    private func DeviceManagementView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("接続済み端末")
                .font(.title2)
                .fontWeight(.bold)
            
            if viewModel.connectedDevices.isEmpty {
                ContentUnavailableView(
                    "接続済み端末がありません",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("広告を開始して端末からの接続を待ってください")
                )
            } else {
                List(viewModel.connectedDevices) { device in
                    ConnectedDeviceRow(device: device, onDisconnect: {
                        viewModel.disconnectDevice(device)
                    })
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - メッセージビュー
    @ViewBuilder
    private func MessagesView() -> some View {
        VStack(spacing: 0) {
            // メッセージ履歴
            if viewModel.messages.isEmpty {
                ContentUnavailableView(
                    "メッセージがありません",
                    systemImage: "message.badge",
                    description: Text("端末が接続されるとメッセージのやり取りができます")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding()
                }
            }
            
            // メッセージ入力
            HStack {
                TextField("メッセージを入力...", text: $viewModel.newMessageText)
                    .textFieldStyle(.roundedBorder)
                
                Button("送信") {
                    viewModel.sendMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.connectedDevices.isEmpty)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
        }
    }
}

// MARK: - Connected Device Row
struct ConnectedDeviceRow: View {
    let device: ConnectedDevice
    let onDisconnect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.deviceName)
                    .font(.headline)
                
                Text("接続時刻: \(device.connectTime, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let lastMessageTime = device.lastMessageTime {
                    Text("最終メッセージ: \(lastMessageTime, style: .time)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Circle()
                    .fill(device.isActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Button("切断", role: .destructive) {
                    onDisconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer()
            }
            
            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                if !message.isOutgoing {
                    Text(message.fromDeviceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isOutgoing ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.isOutgoing ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isOutgoing {
                Spacer()
            }
        }
    }
}

#Preview {
    AdvertiserView()
} 