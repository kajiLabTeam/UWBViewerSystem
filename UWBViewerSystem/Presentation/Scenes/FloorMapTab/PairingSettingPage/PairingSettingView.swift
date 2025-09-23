import SwiftData
import SwiftUI

struct PairingSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: PairingSettingViewModel
    @StateObject private var flowNavigator = SensingFlowNavigator()
    @EnvironmentObject var router: NavigationRouterModel

    init() {
        // ViewModelの初期化時に一時的なダミーリポジトリを使用
        // onAppearで実際のModelContextベースのリポジトリに置き換える
        _viewModel = StateObject(
            wrappedValue: PairingSettingViewModel(swiftDataRepository: DummySwiftDataRepository()))
    }

    var body: some View {
        VStack(spacing: 0) {
            // フロープログレス表示
            SensingFlowProgressView(navigator: flowNavigator)

            ScrollView {
                VStack(spacing: 20) {
                    headerSection

                    // 左右分割のメインコンテンツ
                    HStack(spacing: 20) {
                        // 左側: アンテナ情報
                        VStack(alignment: .leading, spacing: 16) {
                            Label("アンテナ情報", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.headline)
                                .foregroundColor(.primary)

                            antennaListSection

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(12)

                        // 右側: デバイス情報
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Android端末", systemImage: "iphone.gen3")
                                .font(.headline)
                                .foregroundColor(.primary)

                            deviceSection

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(12)
                    }
                    .frame(maxHeight: .infinity)

                    // ペアリング状況表示
                    if !viewModel.antennaPairings.isEmpty {
                        pairingStatusSection
                    }

                    Spacer(minLength: 80)
                }
                .padding()
            }

            navigationSection
        }
        .navigationTitle("Android端末ペアリング")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
        #endif
        .alert(isPresented: $viewModel.showingConnectionAlert) {
            Alert(
                title: Text("ペアリング情報"),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            // ModelContextからSwiftDataRepositoryを作成してViewModelに設定
            let repository = SwiftDataRepository(modelContext: modelContext)
            viewModel.setSwiftDataRepository(repository)
            flowNavigator.currentStep = .devicePairing
            flowNavigator.setRouter(router)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Label("Android端末ペアリング", systemImage: "link")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("アンテナとAndroid端末をペアリングしてセンサーデータを収集します")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var antennaListSection: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(viewModel.selectedAntennas, id: \.id) { antenna in
                    PairingAntennaListItem(
                        antenna: antenna,
                        isPaired: viewModel.antennaPairings.contains { $0.antenna.id == antenna.id }
                    )
                }
            }
        }
    }

    private var deviceSection: some View {
        VStack(spacing: 16) {
            // デバイス検索ボタン
            Button(action: {
                if viewModel.isScanning {
                    viewModel.stopDeviceDiscovery()
                } else {
                    viewModel.startDeviceDiscovery()
                }
            }) {
                HStack {
                    if viewModel.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("検索中...")
                    } else {
                        Image(systemName: "magnifyingglass")
                        Text("端末を検索")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(viewModel.isScanning ? Color.orange : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(viewModel.isScanning)

            // 見つかった端末一覧
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.availableDevices) { device in
                        DeviceListItem(
                            device: device,
                            antennas: viewModel.selectedAntennas.filter { antenna in
                                !viewModel.antennaPairings.contains { $0.antenna.id == antenna.id }
                            },
                            antennaPairings: viewModel.antennaPairings,
                            onPair: { antenna in
                                viewModel.pairAntennaWithDevice(antenna: antenna, device: device)
                            }
                        )
                    }
                }
            }
        }
    }

    private var pairingStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ペアリング状況", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)

                Spacer()

                Button("すべて解除") {
                    viewModel.removeAllPairings()
                }
                .foregroundColor(.red)
                .font(.caption)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.antennaPairings) { pairing in
                        PairingStatusCard(
                            pairing: pairing,
                            onRemove: {
                                viewModel.removePairing(pairing)
                            },
                            onTest: {
                                viewModel.testConnection(for: pairing)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private var navigationSection: some View {
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
                    if viewModel.savePairingForFlow() {
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

// MARK: - Subviews

struct PairingAntennaListItem: View {
    let antenna: AntennaInfo
    let isPaired: Bool

    var body: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(antenna.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text("位置: (\(Int(antenna.coordinates.x)), \(Int(antenna.coordinates.y)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Circle()
                .fill(isPaired ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct DeviceListItem: View {
    let device: AndroidDevice
    let antennas: [AntennaInfo]
    let antennaPairings: [AntennaPairing]
    let onPair: (AntennaInfo) -> Void

    @State private var selectedAntenna: AntennaInfo?
    @State private var showingPairAlert = false

    var availableAntennas: [AntennaInfo] {
        // まだペアリングされていないアンテナのみ表示
        antennas
    }

    var body: some View {
        HStack {
            // NearBy Connectionデバイスには専用アイコンを表示
            Image(systemName: device.isNearbyDevice ? "antenna.radiowaves.left.and.right" : "iphone.gen3")
                .foregroundColor(device.isNearbyDevice ? .green : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(device.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if device.isNearbyDevice {
                        Text("NearBy")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .cornerRadius(3)
                    }
                }

                Text("ID: \(device.id.prefix(8))...")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("発見時刻: \(formatDate(device.lastSeen))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // アンテナと紐付け済みかチェック
            let isAntennaLinked = antennaPairings.contains(where: { $0.device.id == device.id })

            if isAntennaLinked {
                // アンテナと紐付け済みの場合は「ペア済み」を表示
                Text("ペア済み")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            } else if !availableAntennas.isEmpty {
                // 未接続で利用可能なアンテナがある場合のみアンテナ紐付けボタンを表示
                Button("アンテナ紐付け") {
                    if availableAntennas.count == 1 {
                        onPair(availableAntennas.first!)
                    } else {
                        showingPairAlert = true
                    }
                }
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange)
                .cornerRadius(8)
            } else {
                // 利用可能なアンテナがない場合（すべてのアンテナが他の端末と紐付け済み）
                Text("アンテナなし")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .alert("アンテナを選択", isPresented: $showingPairAlert) {
            ForEach(availableAntennas, id: \.id) { antenna in
                Button(antenna.name) {
                    onPair(antenna)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この端末と紐付けるアンテナを選択してください")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct PairingStatusCard: View {
    let pairing: AntennaPairing
    let onRemove: () -> Void
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "link.circle.fill")
                    .foregroundColor(.green)

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pairing.antenna.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)

                Image(systemName: "arrow.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(pairing.device.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)

                // 接続状況を表示
                HStack {
                    Circle()
                        .fill(pairing.device.isConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(pairing.device.isConnected ? "接続中" : "未接続")
                        .font(.caption2)
                        .foregroundColor(pairing.device.isConnected ? .green : .red)
                }
            }

            Button("接続テスト") {
                onTest()
            }
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .cornerRadius(6)
        }
        .padding()
        .frame(width: 120)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .gray.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    PairingSettingView()
}
