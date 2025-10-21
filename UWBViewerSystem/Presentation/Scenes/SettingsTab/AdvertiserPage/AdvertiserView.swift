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
            self.ControlView()
                .tabItem {
                    Label("制御", systemImage: "antenna.radiowaves.left.and.right")
                }

            // 端末管理タブ
            self.DeviceManagementView()
                .tabItem {
                    Label("端末管理", systemImage: "externaldrive.connected.to.line.below")
                }

            // メッセージタブ
            self.MessagesView()
                .tabItem {
                    Label("メッセージ", systemImage: "message")
                }
        }
        .navigationTitle("広告専用画面")
        .alert("接続要求", isPresented: self.$showingConnectionAlert) {
            Button("承認") {
                if let request = selectedRequest {
                    self.viewModel.approveConnection(for: request)
                }
                self.selectedRequest = nil
            }
            Button("拒否", role: .cancel) {
                if let request = selectedRequest {
                    self.viewModel.rejectConnection(for: request)
                }
                self.selectedRequest = nil
            }
        } message: {
            if let request = selectedRequest {
                Text("端末: \(request.deviceName)\nID: \(request.endpointId)")
            }
        }
        .onChange(of: self.viewModel.connectionRequests) { _, newRequests in
            if let latestRequest = newRequests.last {
                self.selectedRequest = latestRequest
                self.showingConnectionAlert = true
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
                Text("状態: \(self.viewModel.statusMessage)")
                    .foregroundColor(self.viewModel.isAdvertising ? .green : .secondary)

                HStack(spacing: 16) {
                    Button(action: {
                        self.viewModel.startAdvertising()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("広告開始")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.viewModel.isAdvertising)

                    Button(action: {
                        self.viewModel.stopAdvertising()
                    }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("広告停止")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!self.viewModel.isAdvertising)
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

            if self.viewModel.connectedDevices.isEmpty {
                ContentUnavailableView(
                    "接続済み端末がありません",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("広告を開始して端末からの接続を待ってください")
                )
            } else {
                List(self.viewModel.connectedDevices) { device in
                    ConnectedDeviceRow(
                        device: device,
                        onDisconnect: {
                            self.viewModel.disconnectDevice(device)
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
            if self.viewModel.messages.isEmpty {
                ContentUnavailableView(
                    "メッセージがありません",
                    systemImage: "message.badge",
                    description: Text("端末が接続されるとメッセージのやり取りができます")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(self.viewModel.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding()
                }
            }

            // メッセージ入力
            HStack {
                TextField("メッセージを入力...", text: self.$viewModel.newMessageText)
                    .textFieldStyle(.roundedBorder)

                Button("送信") {
                    self.viewModel.sendMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    self.viewModel.newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || self.viewModel.connectedDevices.isEmpty)
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
                Text(self.device.deviceName)
                    .font(.headline)

                Text("接続時刻: \(self.device.connectTime, style: .time)")
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
                    .fill(self.device.isActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Button("切断", role: .destructive) {
                    self.onDisconnect()
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
            if self.message.isOutgoing {
                Spacer()
            }

            VStack(alignment: self.message.isOutgoing ? .trailing : .leading, spacing: 4) {
                if !self.message.isOutgoing {
                    Text(self.message.senderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(self.message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(self.message.isOutgoing ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(self.message.isOutgoing ? .white : .primary)
                    .cornerRadius(16)

                Text(self.message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !self.message.isOutgoing {
                Spacer()
            }
        }
    }
}

#Preview {
    AdvertiserView()
}
