import SwiftData
import SwiftUI

struct SensingManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var viewModel = SensingManagementViewModel()

    var body: some View {
        VStack(spacing: 20) {
            HeaderSection()

            HStack(spacing: 20) {
                AntennaStatusSection(viewModel: viewModel)

                SensingControlSection(viewModel: viewModel)
            }

            RealtimeDataSection(viewModel: viewModel)

            NavigationButtonsSection(viewModel: viewModel)
        }
        .navigationTitle("センシング管理")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
            .background(Color(UIColor.systemBackground))
        #endif
        .onAppear {
            // ModelContextからSwiftDataRepositoryを作成してViewModelに設定
            let repository = SwiftDataRepository(modelContext: modelContext)
            viewModel.setSwiftDataRepository(repository)
            viewModel.initialize()
        }
    }

    // MARK: - Header Section
    @ViewBuilder
    private func HeaderSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UWBセンシング管理")
                .font(.title2)
                .fontWeight(.medium)

            Text("各アンテナの状態を確認し、センシングの開始・停止を制御できます。リアルタイムでデータの取得状況を監視してください。")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Navigation Buttons
    @ViewBuilder
    private func NavigationButtonsSection(viewModel: SensingManagementViewModel) -> some View {
        HStack(spacing: 20) {
            Button("戻る") {
                router.pop()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("データを確認") {
                router.push(.trajectoryView)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.hasDataToView)
        }
        .padding()
    }
}

// MARK: - Antenna Status Section
struct AntennaStatusSection: View {
    @ObservedObject var viewModel: SensingManagementViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("アンテナ状態")
                    .font(.headline)

                Spacer()

                Button("更新") {
                    viewModel.refreshAntennaStatus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            LazyVStack(spacing: 12) {
                ForEach(viewModel.antennaDevices) { device in
                    AntennaStatusCard(device: device)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sensing Control Section
struct SensingControlSection: View {
    @ObservedObject var viewModel: SensingManagementViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("センシング制御")
                .font(.headline)

            VStack(spacing: 20) {
                // センシング状態表示
                SensingStatusCard(viewModel: viewModel)

                // センシング設定
                SensingSettingsCard(viewModel: viewModel)

                // センシング制御ボタン
                SensingControlButtons(viewModel: viewModel)

                Spacer()
            }
        }
        .frame(width: 350)
    }
}

// MARK: - Realtime Data Section
struct RealtimeDataSection: View {
    @ObservedObject var viewModel: SensingManagementViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("リアルタイムデータ")
                    .font(.headline)

                Spacer()

                if viewModel.isSensingActive {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("データ受信中")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            if viewModel.realtimeData.isEmpty {
                SensingEmptyDataView()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.realtimeData) { data in
                        RealtimeDataRow(data: data)
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                #if os(macOS)
                    .fill(Color(NSColor.controlColor))
                #elseif os(iOS)
                    .fill(Color(UIColor.systemGray6))
                #endif
        )
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

struct AntennaStatusCard: View {
    let device: AntennaDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(device.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                ConnectionStatusIndicator(status: device.connectionStatus)
            }

            HStack {
                StatusItem(title: "RSSI", value: "\(device.rssi) dBm", color: device.rssiColor)
                StatusItem(title: "バッテリー", value: "\(device.batteryLevel)%", color: device.batteryColor)
                StatusItem(title: "データレート", value: "\(device.dataRate) Hz", color: .blue)
            }

            if let lastUpdate = device.lastUpdate {
                Text("最終更新: \(DateFormatter.timeFormatter.string(from: lastUpdate))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    device.connectionStatus == .connected
                        ? Color(.systemGreen).opacity(0.1)
                        : {
                            #if os(macOS)
                                return Color(NSColor.controlColor)
                            #elseif os(iOS)
                                return Color(UIColor.systemGray6)
                            #endif
                        }())
        )
    }
}

struct SensingStatusCard: View {
    @ObservedObject var viewModel: SensingManagementViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("現在の状態")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                StatusBadge(
                    text: viewModel.isSensingActive ? "実行中" : "停止",
                    color: viewModel.isSensingActive ? .green : .red
                )
            }

            if viewModel.isSensingActive {
                VStack(alignment: .leading, spacing: 5) {
                    Text("実行時間: \(viewModel.sensingDuration)")
                        .font(.caption)
                    Text("取得データ数: \(viewModel.dataPointCount)")
                        .font(.caption)
                    Text("現在のファイル: \(viewModel.currentFileName)")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                #if os(macOS)
                    .fill(Color(NSColor.controlBackgroundColor))
                #elseif os(iOS)
                    .fill(Color(UIColor.systemBackground))
                #endif
                .shadow(radius: 1)
        )
    }
}

struct SensingSettingsCard: View {
    @ObservedObject var viewModel: SensingManagementViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("センシング設定")
                .font(.subheadline)
                .fontWeight(.medium)

            VStack(spacing: 10) {
                HStack {
                    Text("ファイル名")
                        .frame(width: 80, alignment: .leading)
                    TextField("ファイル名", text: $viewModel.sensingFileName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isSensingActive)
                }

                HStack {
                    Text("サンプル率")
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: $viewModel.sampleRate) {
                        Text("1 Hz").tag(1)
                        Text("5 Hz").tag(5)
                        Text("10 Hz").tag(10)
                        Text("20 Hz").tag(20)
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isSensingActive)
                }

                Toggle("自動保存", isOn: $viewModel.autoSave)
                    .disabled(viewModel.isSensingActive)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                #if os(macOS)
                    .fill(Color(NSColor.controlBackgroundColor))
                #elseif os(iOS)
                    .fill(Color(UIColor.systemBackground))
                #endif
                .shadow(radius: 1)
        )
    }
}

struct SensingControlButtons: View {
    @ObservedObject var viewModel: SensingManagementViewModel

    var body: some View {
        VStack(spacing: 10) {
            if !viewModel.isSensingActive {
                Button("センシング開始") {
                    viewModel.startSensing()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStartSensing)
            } else {
                Button("センシング停止") {
                    viewModel.stopSensing()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }

            if viewModel.isSensingActive {
                Button("一時停止") {
                    viewModel.pauseSensing()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isPaused)

                if viewModel.isPaused {
                    Button("再開") {
                        viewModel.resumeSensing()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct ConnectionStatusIndicator: View {
    let status: DeviceConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct StatusItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

struct RealtimeDataRow: View {
    let data: RealtimeData

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(data.deviceName)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text(data.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("距離: \(String(format: "%.2f", data.distance))m")
                        .font(.caption2)
                        .foregroundColor(.blue)

                    Text("仰角: \(String(format: "%.1f", data.elevation))°")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("方位: \(String(format: "%.1f", data.azimuth))°")
                        .font(.caption2)
                        .foregroundColor(.orange)

                    Text("RSSI: \(String(format: "%.0f", data.rssi))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

struct SensingEmptyDataView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wave.3.right")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("データがありません")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("センシングを開始してデータを取得してください")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }
}

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    NavigationStack {
        SensingManagementView()
            .environmentObject(NavigationRouterModel.shared)
    }
}
