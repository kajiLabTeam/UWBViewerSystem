import SwiftData
import SwiftUI

struct FloorMapView: View {
    @StateObject private var viewModel = FloorMapViewModel()
    @EnvironmentObject var router: NavigationRouterModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        #if os(macOS)
            NavigationSplitView {
                VStack(spacing: 20) {
                    self.headerSection

                    if self.viewModel.floorMaps.isEmpty {
                        self.emptyStateView
                    } else {
                        self.floorMapList
                    }

                    Spacer()

                    self.addFloorMapButton
                }
                .padding()
                .navigationSplitViewColumnWidth(min: 300, ideal: 350)
            } detail: {
                if let selectedMap = viewModel.selectedFloorMap {
                    FloorMapDetailView(floorMap: selectedMap)
                } else {
                    Text("フロアマップを選択してください")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .onAppear {
                print("📱 FloorMapView (macOS): onAppear called")
                self.viewModel.setModelContext(self.modelContext)

                // データが空の場合は少し遅れて再読み込み
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.viewModel.floorMaps.isEmpty {
                        print("🔄 フロアマップが空のため再読み込み")
                        self.viewModel.loadFloorMaps()
                    }
                }
            }
            .onChange(of: self.modelContext) { _, newContext in
                self.viewModel.setModelContext(newContext)
            }
        #else
            NavigationView {
                VStack(spacing: 20) {
                    self.headerSection

                    if self.viewModel.floorMaps.isEmpty {
                        self.emptyStateView
                    } else {
                        self.floorMapList
                    }

                    Spacer()

                    self.addFloorMapButton
                }
                .padding()
                .navigationTitle("フロアマップ")
                .navigationBarTitleDisplayModeIfAvailable(.large)
                .onAppear {
                    print("📱 FloorMapView (iOS): onAppear called")
                    self.viewModel.setModelContext(self.modelContext)

                    // データが空の場合は少し遅れて再読み込み
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.viewModel.floorMaps.isEmpty {
                            print("🔄 フロアマップが空のため再読み込み")
                            self.viewModel.loadFloorMaps()
                        }
                    }
                }
                .onChange(of: self.modelContext) { _, newContext in
                    self.viewModel.setModelContext(newContext)
                }
            }
        #endif
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundColor(.green)

                Text("フロアマップ管理")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text("UWBアンテナの配置とフロアマップの設定")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("フロアマップが登録されていません")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("新しいフロアマップを登録してアンテナを配置してください")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var floorMapList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(self.viewModel.floorMaps) { map in
                    FloorMapRow(map: map) {
                        self.viewModel.selectFloorMap(map)
                        #if os(iOS)
                            self.router.push(.antennaConfiguration(floorMapId: map.id))
                        #endif
                    } onDelete: {
                        self.viewModel.deleteFloorMap(map)
                    } onToggleActive: {
                        self.viewModel.toggleActiveFloorMap(map)
                    }
                }
            }
        }
    }

    private var addFloorMapButton: some View {
        Button(action: {
            self.router.push(.floorMapSetting)
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)

                Text("フロアマップを登録")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }
}

struct FloorMapRow: View {
    let map: FloorMap
    let onTap: () -> Void
    let onDelete: () -> Void
    let onToggleActive: () -> Void

    var body: some View {
        HStack {
            // チェックボックス（独立したボタン）
            Button(action: self.onToggleActive) {
                Image(systemName: self.map.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(self.map.isActive ? .green : .gray)
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())

            // メインコンテンツ（詳細表示用ボタン）
            Button(action: self.onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(self.map.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Label("\(self.map.antennaCount) アンテナ", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text(self.map.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // 削除ボタン（独立したボタン）
            Button(action: self.onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(self.map.isActive ? Color.green.opacity(0.05) : Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct FloorMapDetailView: View {
    let floorMap: FloorMap
    @EnvironmentObject var router: NavigationRouterModel

    var body: some View {
        VStack(spacing: 30) {
            // ヘッダー
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(self.floorMap.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        HStack {
                            Label(
                                "\(self.floorMap.antennaCount) アンテナ", systemImage: "antenna.radiowaves.left.and.right"
                            )
                            .foregroundColor(.secondary)

                            Text("•")
                                .foregroundColor(.secondary)

                            Text(self.floorMap.formattedSize)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if self.floorMap.isActive {
                        Label("アクティブ", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)

            // アクション
            VStack(spacing: 16) {
                Button(action: {
                    self.router.push(.antennaConfiguration(floorMapId: self.floorMap.id))
                }) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("アンテナ配置を設定")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Button(action: {
                    self.router.push(.pairingSettingPage(floorMapId: self.floorMap.id))
                }) {
                    HStack {
                        Image(systemName: "link.circle")
                        Text("端末ペアリング設定")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Button(action: {
                    self.router.push(.dataCollectionPage(floorMapId: self.floorMap.id))
                }) {
                    HStack {
                        Image(systemName: "play.circle")
                        Text("センシング開始")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
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
    FloorMapView()
        .environmentObject(NavigationRouterModel())
}
