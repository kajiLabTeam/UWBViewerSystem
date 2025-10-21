import SwiftUI

/// 接続管理専用画面
/// NearBy Connection管理に特化し、参考デザイン「Stitch Design-6.png」に対応
struct ConnectionManagementView: View {
    @StateObject private var viewModel = ConnectionManagementViewModel()
    @EnvironmentObject var router: NavigationRouterModel
    @State private var selectedTab: ConnectionTab = .control
    @State private var messageToSend = ""

    enum ConnectionTab: String, CaseIterable {
        case control = "接続制御"
        case devices = "端末管理"
        case messages = "メッセージ"
    }

    var body: some View {
        VStack(spacing: 20) {
            self.headerSection

            self.tabSelector

            self.tabContent

            Spacer()
        }
        .padding()
        .navigationTitle("接続管理")
        .onAppear {
            self.viewModel.initializeConnection()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("NearBy Connection管理")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text("Android端末との接続管理、メッセージング、デバイス監視を行います")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        Picker("タブ", selection: self.$selectedTab) {
            ForEach(ConnectionTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch self.selectedTab {
        case .control:
            self.connectionControlView
        case .devices:
            self.deviceManagementView
        case .messages:
            self.messageView
        }
    }

    // MARK: - Connection Control View

    private var connectionControlView: some View {
        VStack(spacing: 20) {
            // 接続状態表示
            self.connectionStatusCard

            // 制御ボタン
            self.connectionControlButtons

            // 詳細統計情報
            self.connectionStatistics
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }

    private var connectionStatusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("接続状態")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                StatusIndicator(
                    isActive: self.viewModel.isAdvertising,
                    activeText: "広告中",
                    inactiveText: "停止中"
                )
            }

            HStack(spacing: 20) {
                ConnectionMetric(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "広告状態",
                    value: self.viewModel.isAdvertising ? "アクティブ" : "非アクティブ",
                    color: self.viewModel.isAdvertising ? .green : .gray
                )

                ConnectionMetric(
                    icon: "iphone.and.arrow.forward",
                    title: "接続端末",
                    value: "\(self.viewModel.connectedDevices.count)台",
                    color: .blue
                )

                ConnectionMetric(
                    icon: "clock",
                    title: "稼働時間",
                    value: self.viewModel.uptime,
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var connectionControlButtons: some View {
        HStack(spacing: 16) {
            Button(action: self.viewModel.toggleAdvertising) {
                HStack {
                    Image(systemName: self.viewModel.isAdvertising ? "stop.circle.fill" : "play.circle.fill")
                    Text(self.viewModel.isAdvertising ? "広告停止" : "広告開始")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: self.viewModel.isAdvertising ? [.red, .orange] : [.green, .blue]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }

            Button(action: self.viewModel.startDiscovery) {
                HStack {
                    Image(systemName: "magnifyingglass.circle.fill")
                    Text("デバイス発見")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(self.viewModel.isDiscovering)
        }
    }

    private var connectionStatistics: some View {
        VStack(spacing: 12) {
            Text("接続統計")
                .font(.headline)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                StatisticItem(
                    label: "総接続数",
                    value: "\(self.viewModel.totalConnections)"
                )

                StatisticItem(
                    label: "アクティブ接続",
                    value: "\(self.viewModel.activeConnections)"
                )

                StatisticItem(
                    label: "メッセージ数",
                    value: "\(self.viewModel.totalMessages)"
                )

                StatisticItem(
                    label: "データ転送量",
                    value: self.viewModel.formattedDataTransferred
                )
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Device Management View

    private var deviceManagementView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("接続デバイス")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: self.viewModel.refreshDevices) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }

            if self.viewModel.connectedDevices.isEmpty {
                EmptyDevicesView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(self.viewModel.connectedDevices, id: \.id) { device in
                            ConnectionDeviceCard(device: device) {
                                self.viewModel.disconnectDevice(device)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }

    // MARK: - Message View

    private var messageView: some View {
        VStack(spacing: 16) {
            // メッセージ履歴
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(self.viewModel.messageHistory, id: \.id) { message in
                        ConnectionMessageBubble(message: message)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 300)
            .background(Color.gray.opacity(0.02))
            .cornerRadius(8)

            // メッセージ送信
            HStack(spacing: 12) {
                TextField("メッセージを入力", text: self.$messageToSend)
                    .textFieldStyle(.roundedBorder)

                Button(action: self.sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .disabled(self.messageToSend.isEmpty || self.viewModel.connectedDevices.isEmpty)
            }

            // 操作ボタン
            HStack(spacing: 16) {
                Button(action: self.viewModel.clearMessages) {
                    Text("履歴クリア")
                        .foregroundColor(.red)
                }

                Spacer()

                Button(action: self.viewModel.disconnectAll) {
                    Text("全て切断")
                        .foregroundColor(.orange)
                }
                .disabled(self.viewModel.connectedDevices.isEmpty)
            }
            .font(.caption)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }

    private func sendMessage() {
        self.viewModel.sendMessage(self.messageToSend)
        self.messageToSend = ""
    }
}

// MARK: - Supporting Views

struct StatusIndicator: View {
    let isActive: Bool
    let activeText: String
    let inactiveText: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(self.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(self.isActive ? self.activeText : self.inactiveText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(self.isActive ? .green : .gray)
        }
    }
}

struct ConnectionMetric: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: self.icon)
                .font(.title2)
                .foregroundColor(self.color)

            Text(self.title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(self.value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatisticItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(self.value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.blue)

            Text(self.label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ConnectionDeviceCard: View {
    let device: ConnectionDeviceInfo
    let onDisconnect: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "iphone")
                .foregroundColor(.blue)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.device.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text("接続時刻: \(self.device.formattedConnectionTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("最終通信: \(self.device.formattedLastMessage)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 8) {
                StatusIndicator(
                    isActive: self.device.isConnected,
                    activeText: "接続中",
                    inactiveText: "切断"
                )

                Button(action: self.onDisconnect) {
                    Text("切断")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ConnectionMessageBubble: View {
    let message: ConnectionMessage

    var body: some View {
        HStack {
            if self.message.isOutgoing {
                Spacer()
            }

            VStack(alignment: self.message.isOutgoing ? .trailing : .leading, spacing: 4) {
                Text(self.message.content)
                    .font(.body)
                    .padding(12)
                    .background(self.message.isOutgoing ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(self.message.isOutgoing ? .white : .primary)
                    .cornerRadius(16)

                HStack {
                    if !self.message.isOutgoing {
                        Text(self.message.deviceName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text(self.message.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !self.message.isOutgoing {
                Spacer()
            }
        }
    }
}

struct EmptyDevicesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.3))

            Text("接続デバイスなし")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Android端末からの接続をお待ちください")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    ConnectionManagementView()
        .environmentObject(NavigationRouterModel())
}
