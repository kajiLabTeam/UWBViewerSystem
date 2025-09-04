import SwiftData
import SwiftUI

struct SensingManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var viewModel = SensingManagementViewModel()
    @StateObject private var flowNavigator = SensingFlowNavigator()

    var body: some View {
        VStack(spacing: 0) {
            // フロープログレス表示
            SensingFlowProgressView(navigator: flowNavigator)

            ScrollView {
                VStack(spacing: 20) {
                    HeaderSection()

                    HStack(spacing: 20) {
                        AntennaStatusSection(viewModel: viewModel)

                        SensingControlSection(viewModel: viewModel)
                    }

                    RealtimeDataSection(viewModel: viewModel)

                    Spacer(minLength: 80)
                }
                .padding()
            }

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
            flowNavigator.currentStep = .sensingExecution
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
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 16) {
                Button("戻る") {
                    flowNavigator.goToPreviousStep()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.secondary)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                Button("次へ") {
                    if viewModel.saveSensingSessionForFlow() {
                        flowNavigator.proceedToNextStep()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(viewModel.canProceedToNext ? Color.blue : Color.gray)
                .cornerRadius(8)
                .disabled(!viewModel.canProceedToNext)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .alert("エラー", isPresented: Binding.constant(flowNavigator.lastError != nil)) {
            Button("OK") {
                flowNavigator.lastError = nil
            }
        } message: {
            Text(flowNavigator.lastError ?? "")
        }
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

                ConnectionStatusIndicator(
                    isConnected: device.connectionStatus == .connected,
                    label: device.connectionStatus.displayName
                )
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
                    status: viewModel.isSensingActive ? .success : .error
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
