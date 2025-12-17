import SwiftUI

/// 接続復旧画面
///
/// ニアバイコネクションの接続が切れた際に表示される復旧用の画面です。
/// 接続状態の可視化と自動再接続機能を提供します。
struct ConnectionRecoveryView: View {
    @ObservedObject var connectionUsecase: ConnectionManagementUsecase
    @Binding var isPresented: Bool
    @State private var isReconnecting = false
    @State private var reconnectAttempt = 0
    private let maxReconnectAttempts = 3

    var body: some View {
        VStack(spacing: 24) {
            // ヘッダー
            self.headerSection

            // 接続状態表示
            self.connectionStatusSection

            // アクションボタン
            self.actionButtons

            Spacer()
        }
        .padding()
        .frame(maxWidth: 500)
        #if os(iOS)
            .background(Color(UIColor.systemBackground))
        #elseif os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #endif
            .cornerRadius(16)
            .shadow(radius: 10)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("接続が切断されました")
                .font(.title2)
                .fontWeight(.bold)

            Text("デバイスとの接続が失われました。\n再接続を試みてください。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Connection Status Section

    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("接続情報")
                    .font(.headline)
            }

            Divider()

            // 接続済みデバイス数
            HStack {
                Text("接続済みデバイス:")
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(self.connectionUsecase.getConnectedDeviceCount())台")
                    .fontWeight(.medium)
                    .foregroundColor(
                        self.connectionUsecase.getConnectedDeviceCount() > 0 ? .green : .red
                    )
            }

            // 接続状態
            HStack {
                Text("接続状態:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(self.connectionUsecase.connectState)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
            }

            // 再接続試行回数
            if self.isReconnecting {
                HStack {
                    Text("再接続試行:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(self.reconnectAttempt)/\(self.maxReconnectAttempts)")
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // 自動再接続ボタン
            Button(action: {
                self.attemptAutoReconnect()
            }) {
                HStack {
                    if self.isReconnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        #if os(iOS)
                            .tint(.white)
                        #endif
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(self.isReconnecting ? "再接続中..." : "再接続")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(self.isReconnecting ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(self.isReconnecting)

            // キャンセルボタン
            Button(action: {
                self.isPresented = false
            }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("キャンセル")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Private Methods

    /// 自動再接続を試行
    private func attemptAutoReconnect() {
        self.isReconnecting = true
        self.reconnectAttempt = 0

        Task {
            for attempt in 1...self.maxReconnectAttempts {
                await MainActor.run {
                    self.reconnectAttempt = attempt
                }

                print("🔄 再接続試行 \(attempt)/\(self.maxReconnectAttempts)")

                // 既存の接続をクリア
                await MainActor.run {
                    self.connectionUsecase.resetAll()
                }

                // 少し待機
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                // エラーフラグをクリア
                await MainActor.run {
                    self.connectionUsecase.hasConnectionError = false
                    self.connectionUsecase.lastDisconnectedDevice = nil
                }

                // 再度広告と検索を開始
                await MainActor.run {
                    self.connectionUsecase.startAdvertising()
                    self.connectionUsecase.startDiscovery()
                }

                // 接続確立を待機（最大5秒）
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 500_000_000)

                    if await MainActor.run(body: {
                        self.connectionUsecase.hasConnectedDevices()
                    }) {
                        print("✅ 再接続成功")
                        await MainActor.run {
                            self.isReconnecting = false
                            self.isPresented = false
                        }
                        return
                    }
                }

                // バックオフ：次の試行まで待機時間を増やす
                let backoffDelay = UInt64(attempt * 2_000_000_000)  // 2秒, 4秒, 6秒...
                try? await Task.sleep(nanoseconds: backoffDelay)
            }

            // すべての試行が失敗
            await MainActor.run {
                self.isReconnecting = false
                print("❌ 再接続失敗: 最大試行回数に達しました")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ConnectionRecoveryView(
        connectionUsecase: ConnectionManagementUsecase.shared,
        isPresented: .constant(true)
    )
}
