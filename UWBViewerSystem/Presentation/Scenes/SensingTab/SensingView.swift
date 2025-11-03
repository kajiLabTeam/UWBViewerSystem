import SwiftUI

struct SensingView: View {
    @StateObject private var viewModel = SensingViewModel()
    @EnvironmentObject var router: NavigationRouterModel
    @State private var showValidationAlert = false
    @State private var validationMessage = ""

    var body: some View {
        #if os(macOS)
            NavigationSplitView {
                VStack(spacing: 20) {
                    self.headerSection

                    if self.viewModel.savedSensingData.isEmpty {
                        self.emptyStateView
                    } else {
                        self.sensingDataList
                    }

                    Spacer()

                    self.startSensingButton
                }
                .padding()
                .navigationSplitViewColumnWidth(min: 300, ideal: 350)
            } detail: {
                if let selectedData = viewModel.selectedSensingData {
                    SensingDetailView(sensingData: selectedData)
                } else {
                    Text("センシングデータを選択してください")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                }
            }
        #else
            NavigationView {
                VStack(spacing: 20) {
                    self.headerSection

                    if self.viewModel.savedSensingData.isEmpty {
                        self.emptyStateView
                    } else {
                        self.sensingDataList
                    }

                    Spacer()

                    self.startSensingButton
                }
                .padding()
                .navigationTitle("センシング")
                .navigationBarTitleDisplayModeIfAvailable(.large)
            }
            .alert("設定が必要です", isPresented: self.$showValidationAlert) {
                Button("フロアマップ設定へ") {
                    self.router.push(.fieldSettingPage)
                }
                Button("端末接続設定へ") {
                    self.router.push(.connectionManagementPage)
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(self.validationMessage)
            }
            .onAppear {
                self.viewModel.loadSavedData()
            }
        #endif
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("センシングデータ管理")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text("保存されたセンシングデータの確認と新規センシングの開始")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("保存されたデータがありません")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("センシングを開始してデータを収集してください")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var sensingDataList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(self.viewModel.savedSensingData) { data in
                    SensingDataRow(
                        data: data,
                        onTap: {
                            self.viewModel.selectSensingData(data)
                            #if os(iOS)
                                self.router.push(.dataDisplayPage)
                            #endif
                        }
                    ) {
                        self.viewModel.deleteSensingData(data)
                    }
                }
            }
        }
    }

    private var startSensingButton: some View {
        Button(action: {
            self.validateAndStartSensing()
        }) {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.title2)

                Text("センシング開始")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }

    private func validateAndStartSensing() {
        let validation = self.viewModel.validateSensingRequirements()

        if validation.isValid {
            self.router.push(.dataCollectionPage)
        } else {
            self.validationMessage = validation.message
            self.showValidationAlert = true
        }
    }
}

struct SensingDataRow: View {
    let data: SensingData
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: self.onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(self.data.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Label("\(self.data.dataPoints) データポイント", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text(self.data.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: self.onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct SensingDetailView: View {
    let sensingData: SensingData
    @EnvironmentObject var router: NavigationRouterModel

    var body: some View {
        VStack(spacing: 30) {
            // ヘッダー
            VStack(alignment: .leading, spacing: 16) {
                Text(self.sensingData.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                HStack {
                    Label("\(self.sensingData.dataPoints) データポイント", systemImage: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(self.sensingData.formattedDate)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)

            // データ表示エリア
            VStack(spacing: 16) {
                Text("データ詳細")
                    .font(.headline)

                // ここに実際のデータ可視化やグラフを追加可能
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .frame(height: 200)
                    .overlay(
                        VStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.largeTitle)
                                .foregroundColor(.blue)
                            Text("データ可視化エリア")
                                .foregroundColor(.secondary)
                        }
                    )
            }

            // アクション
            VStack(spacing: 16) {
                Button(action: {
                    self.router.push(.trajectoryView)
                }) {
                    HStack {
                        Image(systemName: "map")
                        Text("軌跡を表示")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Button(action: {
                    // データエクスポート処理
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("データをエクスポート")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #else
            .background(Color(UIColor.systemBackground))
        #endif
    }
}

#Preview {
    SensingView()
        .environmentObject(NavigationRouterModel())
}
