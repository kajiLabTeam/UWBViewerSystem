import SwiftData
import SwiftUI

/// データ表示専用画面
/// リアルタイムデータ表示とファイル管理に特化し、参考デザイン「Stitch Design-5.png」に対応
struct DataDisplayView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = DataDisplayViewModel()
    @StateObject private var flowNavigator = SensingFlowNavigator()
    @EnvironmentObject var router: NavigationRouterModel
    @State private var selectedDisplayMode: DisplayMode = .history

    enum DisplayMode: String, CaseIterable {
        case history = "履歴データ"
        case files = "ファイル管理"
    }

    var body: some View {
        VStack(spacing: 0) {
            // フロープログレス表示
            SensingFlowProgressView(navigator: flowNavigator)

            ScrollView {
                VStack(spacing: 20) {
                    headerSection

                    displayModeSelector

                    contentArea

                    Spacer(minLength: 80)
                }
                .padding()
            }

            // ナビゲーションボタン
            navigationButtons
        }
        .navigationTitle("データ表示")
        .onAppear {
            // ModelContextからSwiftDataRepositoryを作成してViewModelに設定
            let repository = SwiftDataRepository(modelContext: modelContext)
            viewModel.setSwiftDataRepository(repository)
            flowNavigator.currentStep = .dataViewer
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("UWBデータ表示・分析")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text("履歴データの分析、ファイル管理を行います")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Display Mode Selector

    private var displayModeSelector: some View {
        Picker("表示モード", selection: $selectedDisplayMode) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch selectedDisplayMode {
        case .history:
            historyDataView
        case .files:
            fileManagementView
        }
    }

    // MARK: - History Data View

    private var historyDataView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("履歴データ")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: viewModel.refreshHistoryData) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }

            if viewModel.historyData.isEmpty {
                EmptyDataView(
                    icon: "clock",
                    title: "履歴なし",
                    subtitle: "まだ保存されたデータがありません"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.historyData, id: \.id) { session in
                            HistorySessionCard(session: session) {
                                viewModel.loadSessionData(session)
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

    // MARK: - File Management View

    private var fileManagementView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("ファイル管理")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: viewModel.openStorageFolder) {
                    HStack {
                        Image(systemName: "folder")
                        Text("フォルダを開く")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
            }

            if viewModel.receivedFiles.isEmpty {
                EmptyDataView(
                    icon: "doc",
                    title: "ファイルなし",
                    subtitle: "まだ受信されたファイルがありません"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.receivedFiles, id: \.name) { file in
                            FileItemCard(file: file) {
                                viewModel.openFile(file)
                            }
                        }
                    }
                }
            }

            // ファイル転送進捗
            if !viewModel.fileTransferProgress.isEmpty {
                VStack(spacing: 8) {
                    Text("ファイル転送中")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(Array(viewModel.fileTransferProgress.keys), id: \.self) { endpointId in
                        if let progress = viewModel.fileTransferProgress[endpointId] {
                            FileTransferProgressView(
                                endpointId: endpointId,
                                progress: progress
                            )
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - Data Row

struct DataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - History Session Card

struct HistorySessionCard: View {
    let session: SensingSession
    let onTap: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(session.dataPoints) points")
                    .font(.caption)
                    .fontWeight(.medium)

                Text(session.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onTap) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - File Item Card

struct FileItemCard: View {
    let file: DataDisplayFile
    let onTap: () -> Void

    var body: some View {
        HStack {
            Image(systemName: file.isCSV ? "doc.text" : "doc")
                .foregroundColor(file.isCSV ? .green : .blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(file.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(file.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: onTap) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - File Transfer Progress View

struct FileTransferProgressView: View {
    let endpointId: String
    let progress: Int

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("端末: \(endpointId)")
                    .font(.caption)
                Spacer()
                Text("\(progress)%")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            ProgressView(value: Double(progress), total: 100)
                .progressViewStyle(LinearProgressViewStyle())
        }
    }
}

// MARK: - Navigation Buttons

extension DataDisplayView {
    private var navigationButtons: some View {
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

                Button("フローを完了") {
                    flowNavigator.completeFlow()
                    router.reset()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(Color.green)
                .cornerRadius(8)
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

// MARK: - Empty Data View

struct EmptyDataView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.3))

            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    DataDisplayView()
        .environmentObject(NavigationRouterModel())
}
