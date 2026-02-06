import SwiftData
import SwiftUI

/// データ表示専用画面
/// リアルタイムデータ表示とファイル管理に特化し、参考デザイン「Stitch Design-5.png」に対応
struct DataDisplayView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = DataDisplayViewModel()
    @EnvironmentObject var router: NavigationRouterModel
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var sessionToDelete: SensingSession?
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    self.headerSection

                    self.historyDataView

                    Spacer(minLength: 20)
                }
                .padding()
            }
        }
        .navigationTitle("取得データ")
        .sheet(isPresented: self.$showShareSheet, onDismiss: {
            print("🎬 ShareSheetが閉じられました")
            self.shareURL = nil
        }) {
            if let url = self.shareURL {
                #if os(iOS)
                    ShareSheet(items: [url])
                        .onAppear {
                            print("🎬 ShareSheetを表示: \(url.path)")
                        }
                #else
                    Text("macOSでは共有機能は利用できません")
                #endif
            } else {
                Text("共有するファイルが見つかりません")
                    .foregroundColor(.red)
                    .onAppear {
                        print("⚠️ shareURLがnilです")
                    }
            }
        }
        .alert("セッション削除", isPresented: self.$showDeleteAlert, presenting: self.sessionToDelete) { session in
            Button("キャンセル", role: .cancel) {
                self.sessionToDelete = nil
            }
            Button("削除", role: .destructive) {
                Task {
                    let success = await self.viewModel.deleteSessionData(session)
                    if success {
                        print("✅ セッション削除成功: \(session.name)")
                    } else {
                        print("❌ セッション削除失敗: \(session.name)")
                    }
                    self.sessionToDelete = nil
                }
            }
        } message: { session in
            Text("「\(session.name)」を削除しますか？\nSwiftDataとCSVファイルの両方が削除されます。")
        }
        .onAppear {
            // ModelContextからSwiftDataRepositoryを作成してViewModelに設定
            let repository = SwiftDataRepository(modelContext: modelContext)
            self.viewModel.setSwiftDataRepository(repository)
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

    // MARK: - History Data View

    private var historyDataView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("履歴データ")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: self.viewModel.refreshHistoryData) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }

            if self.viewModel.historyData.isEmpty {
                EmptyDataView(
                    icon: "clock",
                    title: "履歴なし",
                    subtitle: "まだ保存されたデータがありません"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(self.viewModel.historyData, id: \.id) { session in
                            HistorySessionCard(
                                session: session,
                                onShare: {
                                    Task {
                                        print("🔄 共有ボタンがタップされました: \(session.name)")
                                        if let url = await self.viewModel.shareSessionData(session) {
                                            print("✅ ZIPファイルURL取得成功: \(url.path)")
                                            await MainActor.run {
                                                self.shareURL = url
                                                self.showShareSheet = true
                                            }
                                        } else {
                                            print("❌ ZIPファイルの生成に失敗しました")
                                        }
                                    }
                                },
                                onDelete: {
                                    self.sessionToDelete = session
                                    self.showDeleteAlert = true
                                }
                            )
                        }
                    }
                }
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
            Text(self.label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(self.value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - History Session Card

struct HistorySessionCard: View {
    let session: SensingSession
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.session.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(self.session.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(self.session.dataPoints) points")
                    .font(.caption)
                    .fontWeight(.medium)

                Text(self.session.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: self.onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
                    .foregroundColor(.blue)
            }

            Button(action: self.onDelete) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Empty Data View

struct EmptyDataView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: self.icon)
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.3))

            Text(self.title)
                .font(.headline)
                .foregroundColor(.secondary)

            Text(self.subtitle)
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

// MARK: - ShareSheet for iOS

#if os(iOS)
    struct ShareSheet: UIViewControllerRepresentable {
        let items: [Any]

        func makeUIViewController(context: Context) -> UIActivityViewController {
            print("🎬 ShareSheet: UIActivityViewControllerを作成中")
            print("🎬 共有アイテム数: \(self.items.count)")
            for (index, item) in self.items.enumerated() {
                print("🎬 アイテム[\(index)]: \(type(of: item)) = \(item)")
            }

            let controller = UIActivityViewController(activityItems: self.items, applicationActivities: nil)

            return controller
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
            // No update needed
        }
    }
#endif

#Preview {
    DataDisplayView()
        .environmentObject(NavigationRouterModel())
}
