import SwiftData
import SwiftUI

/// データ取得専用画面
/// センシング制御に特化し、参考デザイン「Stitch Design-4.png」に対応
struct DataCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: DataCollectionViewModel
    @EnvironmentObject var router: NavigationRouterModel
    @State private var sensingFileName = ""
    @State private var showFileNameAlert = false

    init() {
        // StateObjectの初期化はinitで行う必要がある
        // ただし、modelContextはinitの段階ではアクセスできないため、
        // ViewModelにmodelContextを設定する別の方法を取る
        _viewModel = StateObject(wrappedValue: DataCollectionViewModel())
    }

    var body: some View {
        ZStack {
            // 背景: フロアマップを全画面表示
            if self.viewModel.currentFloorMapInfo != nil {
                self.fullScreenFloorMap
            } else {
                Color.gray.opacity(0.1)
                    .ignoresSafeArea()
            }

            // 前面: コントロールパネル（半透明背景）
            VStack {
                Spacer()

                VStack(spacing: 16) {
                    // センシング制御（コンパクト版）
                    self.compactSensingControl

                    // リアルタイムデータ表示（コンパクト版）
                    if !self.viewModel.deviceRealtimeDataList.isEmpty {
                        self.compactRealtimeDataDisplay
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(UIColor.systemBackground).opacity(0.95))
                        .shadow(radius: 10)
                )
                .padding()
            }
        }
        .navigationTitle("データ取得")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    self.router.push(.dataDisplayPage)
                }) {
                    Image(systemName: "list.bullet")
                }
            }
        }
        .onAppear {
            // ModelContextを使ってSwiftDataRepositoryを初期化
            self.viewModel.setupSwiftDataRepository(modelContext: self.modelContext)
        }
        .alert("ファイル名が必要です", isPresented: self.$showFileNameAlert) {
            Button("OK") {}
        } message: {
            Text("センシングを開始するには、ファイル名を入力してください。")
        }
    }

    // MARK: - Full Screen Floor Map

    private var fullScreenFloorMap: some View {
        GeometryReader { geometry in
            if let floorMapInfo = self.viewModel.currentFloorMapInfo {
                FloorMapCanvas(
                    floorMapImage: self.viewModel.floorMapImage,
                    floorMapInfo: floorMapInfo,
                    calibrationPoints: nil,
                    onMapTap: nil,
                    enableZoom: true,
                    fixedHeight: nil,
                    showGrid: true
                ) { canvasGeometry in
                    // アンテナ位置を表示
                    ForEach(self.viewModel.allAntennaPositions, id: \.id) { antenna in
                        let normalizedPoint = canvasGeometry.realWorldToNormalized(
                            CGPoint(x: antenna.position.x, y: antenna.position.y)
                        )
                        let screenPos = canvasGeometry.normalizedToImageCoordinate(normalizedPoint)

                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                )

                            Text(antenna.antennaId)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.red.opacity(0.9))
                                .cornerRadius(6)
                                .offset(x: 0, y: -25)
                        }
                        .position(screenPos)
                    }

                    // タグのリアルタイム位置を表示
                    ForEach(Array(self.viewModel.globalCoordinates.keys.sorted()), id: \.self) {
                        deviceName in
                        if let tagPos = self.viewModel.globalCoordinates[deviceName] {
                            let normalizedPoint = canvasGeometry.realWorldToNormalized(
                                CGPoint(x: tagPos.x, y: tagPos.y)
                            )
                            let screenPos = canvasGeometry.normalizedToImageCoordinate(normalizedPoint)

                            ZStack {
                                // パルスエフェクト
                                Circle()
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 4)
                                    .scaleEffect(2.0)
                                    .opacity(0.3)

                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                    )

                                Text(deviceName)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.blue.opacity(0.9))
                                    .cornerRadius(6)
                                    .offset(x: 0, y: -25)
                            }
                            .position(screenPos)
                            .animation(.easeInOut(duration: 0.3), value: screenPos)
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Compact Sensing Control

    private var compactSensingControl: some View {
        VStack(spacing: 12) {
            HStack {
                // ファイル名入力
                TextField("ファイル名", text: self.$sensingFileName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(self.viewModel.isSensingActive)

                // センシングトグルボタン
                Button(action: {
                    if self.viewModel.isSensingActive {
                        self.stopSensing()
                    } else {
                        self.startSensing()
                    }
                }) {
                    Image(systemName: self.viewModel.isSensingActive ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(self.viewModel.isSensingActive ? Color.red : Color.green)
                        .clipShape(Circle())
                }
            }

            // ステータス表示
            HStack {
                Circle()
                    .fill(self.viewModel.isSensingActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(self.viewModel.sensingStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if self.viewModel.isSensingActive {
                    Text(self.viewModel.elapsedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Compact Realtime Data Display

    private var compactRealtimeDataDisplay: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                Text("\(self.viewModel.deviceRealtimeDataList.count)台のデバイス")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Button(action: {
                    // 詳細表示に遷移
                }) {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                }
            }

            // 簡易データ表示
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(self.viewModel.deviceRealtimeDataList) { deviceData in
                        if let latestData = deviceData.latestData {
                            CompactDeviceDataView(deviceData: deviceData, latestData: latestData)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("UWBデータ収集制御")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text("UWBセンサーからのリアルタイムデータを収集し、指定したファイルに保存します")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Sensing Control Card

    private var sensingControlCard: some View {
        VStack(spacing: 20) {
            Text("センシング制御")
                .font(.headline)
                .fontWeight(.semibold)

            // ファイル名入力
            VStack(alignment: .leading, spacing: 8) {
                Text("ファイル名")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    TextField("例: experiment_001", text: self.$sensingFileName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(self.viewModel.isSensingActive)

                    Text(".csv")
                        .foregroundColor(.secondary)
                }
            }

            // 制御ボタン
            HStack(spacing: 16) {
                Button(action: self.startSensing) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("センシング開始")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.blue]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .disabled(self.viewModel.isSensingActive || self.sensingFileName.isEmpty)

                Button(action: self.stopSensing) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("センシング終了")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.red, Color.orange]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .disabled(!self.viewModel.isSensingActive)
            }

            // 状態表示
            self.statusIndicator
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack {
            Circle()
                .fill(self.viewModel.isSensingActive ? Color.green : Color.gray)
                .frame(width: 12, height: 12)

            Text(self.viewModel.sensingStatus)
                .font(.body)
                .fontWeight(.medium)

            Spacer()

            if self.viewModel.isSensingActive {
                Text("経過時間: \(self.viewModel.elapsedTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(self.viewModel.isSensingActive ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Recent Sessions Card

    private var recentSessionsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("最近のセッション")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: {
                    self.router.push(.dataDisplayPage)
                }) {
                    Text("全て表示")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if self.viewModel.recentSessions.isEmpty {
                Text("まだセッションがありません")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(self.viewModel.recentSessions.prefix(3)), id: \.name) { session in
                        SessionRowView(session: session)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }

    // MARK: - Actions

    private func startSensing() {
        guard !self.sensingFileName.isEmpty else {
            self.showFileNameAlert = true
            return
        }

        self.viewModel.startSensing(fileName: self.sensingFileName)
    }

    private func stopSensing() {
        self.viewModel.stopSensing()
    }

    // MARK: - Standalone Realtime Data Display Section

    private var realtimeDataDisplaySection: some View {
        VStack(spacing: 16) {
            // デバッグ表示
            Text("🔍 セクション内部: count=\(self.viewModel.dataPointCount)")
                .font(.caption2)
                .foregroundColor(.red)

            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("リアルタイムセンサーデータ")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }

            // リアルタイムデータ接続状態表示
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(self.viewModel.deviceRealtimeDataList.isEmpty ? Color.gray : Color.green)
                        .frame(width: 8, height: 8)

                    Text(self.viewModel.deviceRealtimeDataList.isEmpty ? "UWBデータ待機中" : "UWBデータ受信中")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !self.viewModel.deviceRealtimeDataList.isEmpty {
                    VStack(spacing: 2) {
                        Text("最終更新: \(Date().formatted(.dateTime.hour().minute().second()))")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("受信デバイス数: \(self.viewModel.deviceRealtimeDataList.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(spacing: 2) {
                        Text("REALTIME_DATAメッセージ待機中")
                            .font(.caption2)
                            .foregroundColor(.orange)

                        Text("Android側でセンシング開始済みか確認")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.vertical, 8)

            if self.viewModel.deviceRealtimeDataList.isEmpty {
                // データなしの表示
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)

                    Text("センサーデータを待機中...")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Android端末を接続してセンシングを開始してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    // 操作手順の表示
                    VStack(spacing: 4) {
                        Text("操作手順:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.top, 8)

                        Text("1. Android端末で「センシング開始」ボタンを押す")
                        Text("2. UWBセンサーデータがリアルタイム表示されます")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(40)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            } else {
                // リアルタイムデータ表示
                VStack(spacing: 12) {
                    // 接続状態ヘッダー
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)

                            Text("接続中")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }

                        Spacer()

                        Text("\(self.viewModel.deviceRealtimeDataList.count)台のデバイス")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: {
                            // データをクリア（デバッグ用）
                            self.viewModel.clearRealtimeData()
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.horizontal)

                    // デバイス別データ表示
                    ForEach(self.viewModel.deviceRealtimeDataList) { deviceData in
                        if let latestData = deviceData.latestData {
                            RealtimeDeviceCardView(deviceData: deviceData, latestData: latestData)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }

    // MARK: - Realtime Data Section

    private var realtimeDataSection: some View {
        Group {
            if !self.viewModel.deviceRealtimeDataList.isEmpty {
                VStack(spacing: 12) {
                    self.realtimeDataHeader

                    ForEach(self.viewModel.deviceRealtimeDataList) { deviceData in
                        if let latestData = deviceData.latestData {
                            DeviceDataCardView(deviceData: deviceData, latestData: latestData)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    private var realtimeDataHeader: some View {
        HStack {
            Text("リアルタイム計測値")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Spacer()

            Text("接続中: \(self.viewModel.deviceRealtimeDataList.count)台")
                .font(.caption)
                .foregroundColor(.green)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Floor Map Display Section

    private var floorMapDisplaySection: some View {
        VStack(spacing: 16) {
            self.floorMapHeader

            if let floorMapInfo = viewModel.currentFloorMapInfo {
                VStack(spacing: 12) {
                    self.floorMapInfo

                    self.floorMapCanvas(floorMapInfo: floorMapInfo)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )

                    self.floorMapLegend
                }
            } else {
                Text("フロアマップが読み込まれていません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }

    private var floorMapHeader: some View {
        HStack {
            Image(systemName: "map")
                .font(.title2)
                .foregroundColor(.blue)
            Text("フロアマップ - リアルタイム位置")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
    }

    private var floorMapInfo: some View {
        HStack {
            Text(self.viewModel.currentFloorMapInfo?.name ?? "")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Text("タグ: \(self.viewModel.globalCoordinates.count)台")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("アンテナ: \(self.viewModel.allAntennaPositions.count)台")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func floorMapCanvas(floorMapInfo: FloorMapInfo) -> some View {
        FloorMapCanvas(
            floorMapImage: self.viewModel.floorMapImage,
            floorMapInfo: floorMapInfo,
            calibrationPoints: nil,
            onMapTap: nil,
            enableZoom: true,
            fixedHeight: 400,
            showGrid: true
        ) { geometry in
            // アンテナ位置を表示
            ForEach(self.viewModel.allAntennaPositions, id: \.id) { antenna in
                let normalizedPoint = geometry.realWorldToNormalized(
                    CGPoint(x: antenna.position.x, y: antenna.position.y)
                )
                let screenPos = geometry.normalizedToImageCoordinate(normalizedPoint)

                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )

                    Text(antenna.antennaId)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(4)
                        .offset(x: 0, y: -20)
                }
                .position(screenPos)
            }

            // タグのリアルタイム位置を表示
            ForEach(Array(self.viewModel.globalCoordinates.keys.sorted()), id: \.self) { deviceName in
                if let tagPos = self.viewModel.globalCoordinates[deviceName] {
                    let normalizedPoint = geometry.realWorldToNormalized(
                        CGPoint(x: tagPos.x, y: tagPos.y)
                    )
                    let screenPos = geometry.normalizedToImageCoordinate(normalizedPoint)

                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 8)
                                    .scaleEffect(1.5)
                                    .opacity(0.5)
                            )

                        Text(deviceName)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(4)
                            .offset(x: 0, y: -20)
                    }
                    .position(screenPos)
                    .animation(.easeInOut(duration: 0.3), value: screenPos)
                }
            }
        }
    }

    private var floorMapLegend: some View {
        HStack(spacing: 20) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                Text("アンテナ")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                Text("タグ")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Compact Device Data View

struct CompactDeviceDataView: View {
    let deviceData: DeviceRealtimeData
    let latestData: RealtimeData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.deviceData.deviceName)
                .font(.caption2)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("距離")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", self.latestData.distance))cm")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                Divider()
                    .frame(height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("RSSI")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.0f", self.latestData.rssi))dBm")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Realtime Device Card View

struct RealtimeDeviceCardView: View {
    let deviceData: DeviceRealtimeData
    let latestData: RealtimeData

    var body: some View {
        VStack(spacing: 10) {
            // デバイス名とリアルタイム更新インジケータ
            HStack {
                Text(self.deviceData.deviceName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(self.deviceData.isRecentlyUpdated ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    Text(self.deviceData.isRecentlyUpdated ? "LIVE" : "OFFLINE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(self.deviceData.isRecentlyUpdated ? .green : .red)
                }
            }

            // データ品質バー
            self.dataQualityBar

            // メイン計測値（大きく表示）
            self.mainMeasurements

            // 補助情報
            self.auxiliaryInfo

            // データ履歴
            HStack {
                Text("データ履歴: \(self.deviceData.dataHistory.count)件")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("更新: \(formatTimeAgo(self.deviceData.lastUpdateTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    self.deviceData.isRecentlyUpdated ? Color.blue.opacity(0.05) : Color.gray.opacity(0.05),
                    self.deviceData.isRecentlyUpdated ? Color.green.opacity(0.05) : Color.gray.opacity(0.02),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    self.deviceData.isRecentlyUpdated ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2),
                    lineWidth: 1
                )
        )
    }

    private var dataQualityBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(self.qualityBarColor(for: index))
                    .frame(height: 4)
            }
        }
        .frame(height: 4)
    }

    private func qualityBarColor(for index: Int) -> Color {
        let quality = self.dataQuality
        if index < quality {
            return quality >= 4 ? .green : quality >= 2 ? .orange : .red
        } else {
            return .gray.opacity(0.3)
        }
    }

    private var dataQuality: Int {
        var quality = 0
        if self.latestData.distance > 0 { quality += 1 }
        if self.latestData.elevation != 0 { quality += 1 }
        if self.latestData.azimuth != 0 { quality += 1 }
        if self.latestData.rssi > -80 { quality += 1 }
        if self.latestData.nlos == 0 { quality += 1 }
        return quality
    }

    private var mainMeasurements: some View {
        VStack(spacing: 16) {
            // 距離表示（進歩バー式）
            VStack(spacing: 8) {
                HStack {
                    Text("距離")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(String(format: "%.0f", self.latestData.distance)) cm")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                DistanceProgressView(distance: self.latestData.distance, maxDistance: 1000.0)  // 10m = 1000cm
            }

            // 仰角と方位（コンパス形式）
            HStack(spacing: 24) {
                // 仰角ゲージ
                VStack(spacing: 8) {
                    Text("仰角")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ElevationGaugeView(elevation: self.latestData.elevation)

                    Text("\(String(format: "%.1f", self.latestData.elevation))°")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 80)

                // 方位コンパス
                VStack(spacing: 8) {
                    Text("方位")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    AzimuthCompassView(azimuth: self.latestData.azimuth)

                    Text("\(String(format: "%.1f", self.latestData.azimuth))°")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var auxiliaryInfo: some View {
        HStack(spacing: 16) {
            HStack {
                Text("RSSI:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(String(format: "%.0f", self.latestData.rssi))dBm")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
            }

            HStack {
                Text("NLOS:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(self.latestData.nlos)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(self.latestData.nlos == 0 ? .green : .red)
            }

            Spacer()

            HStack {
                Text("Seq:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(self.latestData.seqCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Device Data Card View

struct DeviceDataCardView: View {
    let deviceData: DeviceRealtimeData
    let latestData: RealtimeData

    var body: some View {
        VStack(spacing: 8) {
            self.deviceStatusHeader
            self.measurementValues
        }
        .padding(12)
        .background(self.backgroundColor)
        .cornerRadius(8)
        .overlay(self.borderOverlay)
    }

    private var deviceStatusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.deviceData.deviceName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Circle()
                        .fill(self.deviceData.isRecentlyUpdated ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(self.deviceData.isRecentlyUpdated ? "アクティブ" : "非アクティブ")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("更新: \(formatTimeAgo(self.deviceData.lastUpdateTime))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("データ履歴")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(self.deviceData.dataHistory.count)件")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
        }
    }

    private var measurementValues: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                MeasurementValueView(
                    title: "距離",
                    value: String(format: "%.2f", self.latestData.distance),
                    unit: "m",
                    color: .blue,
                    quality: self.latestData.distance > 0 ? .good : .poor
                )

                MeasurementValueView(
                    title: "仰角",
                    value: String(format: "%.1f", self.latestData.elevation),
                    unit: "°",
                    color: .green,
                    quality: self.latestData.elevation != 0 ? .good : .poor
                )

                MeasurementValueView(
                    title: "方位",
                    value: String(format: "%.1f", self.latestData.azimuth),
                    unit: "°",
                    color: .orange,
                    quality: self.latestData.azimuth != 0 ? .good : .poor
                )
            }

            HStack(spacing: 12) {
                MeasurementValueView(
                    title: "RSSI",
                    value: String(format: "%.0f", self.latestData.rssi),
                    unit: "dBm",
                    color: .purple,
                    quality: self.latestData.rssi > -80 ? .good : .poor
                )

                MeasurementValueView(
                    title: "NLOS",
                    value: "\(self.latestData.nlos)",
                    unit: "",
                    color: self.latestData.nlos == 0 ? .green : .red,
                    quality: self.latestData.nlos == 0 ? .good : .poor
                )

                MeasurementValueView(
                    title: "SeqCount",
                    value: "\(self.latestData.seqCount)",
                    unit: "",
                    color: .gray,
                    quality: .good
                )
            }
        }
    }

    private var backgroundColor: Color {
        self.deviceData.isRecentlyUpdated ? Color.green.opacity(0.05) : Color.orange.opacity(0.05)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                self.deviceData.isRecentlyUpdated ? Color.green.opacity(0.3) : Color.orange.opacity(0.3),
                lineWidth: 1
            )
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: SensingSession

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.session.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(self.session.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(self.session.dataPoints) points")
                    .font(.caption)
                    .fontWeight(.medium)

                Text(self.session.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Supporting Views and Functions

enum MeasurementQuality {
    case good, poor
}

struct MeasurementValueView: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let quality: MeasurementQuality

    var body: some View {
        VStack(spacing: 2) {
            Text(self.title)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 2) {
                Text(self.value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(self.color)

                if !self.unit.isEmpty {
                    Text(self.unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // 品質インジケータ
            Circle()
                .fill(self.quality == .good ? Color.green : Color.red)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}

private func formatTimeAgo(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)

    if interval < 1 {
        return "今"
    } else if interval < 60 {
        return "\(Int(interval))秒前"
    } else if interval < 3600 {
        return "\(Int(interval / 60))分前"
    } else {
        return "\(Int(interval / 3600))時間前"
    }
}

// MARK: - GUI Components for Sensor Data

struct DistanceProgressView: View {
    let distance: Double
    let maxDistance: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景バー
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)

                // 進歩バー
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.cyan]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: self.progressWidth(geometry.size.width), height: 8)
                    .animation(.easeInOut(duration: 0.3), value: self.distance)

                // 距離マーカー（100cm刻み）
                ForEach(stride(from: 0, to: Int(self.maxDistance) + 1, by: 100).map { $0 }, id: \.self) { cm in
                    VStack {
                        Rectangle()
                            .fill(Color.gray)
                            .frame(width: 1, height: cm % 200 == 0 ? 12 : 6)

                        if cm % 200 == 0 {
                            Text("\(cm / 100)m")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .offset(x: CGFloat(cm) / self.maxDistance * geometry.size.width - 0.5)
                }
            }
        }
        .frame(height: 24)
    }

    private func progressWidth(_ totalWidth: CGFloat) -> CGFloat {
        let progress = min(distance / self.maxDistance, 1.0)
        return totalWidth * progress
    }
}

struct ElevationGaugeView: View {
    let elevation: Double

    var body: some View {
        ZStack {
            // 背景円弧（右半分）
            Path { path in
                path.addArc(
                    center: CGPoint(x: 30, y: 30),
                    radius: 25,
                    startAngle: .degrees(0),
                    endAngle: .degrees(180),
                    clockwise: false
                )
            }
            .stroke(Color.gray.opacity(0.3), lineWidth: 6)

            // 仰角インジケータ円弧
            Path { path in
                let startAngle: Double = 0
                let endAngle = (elevation + 60) / 120 * 180  // -60°〜+60° を 0°〜180° にマップ
                path.addArc(
                    center: CGPoint(x: 30, y: 30),
                    radius: 25,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(endAngle),
                    clockwise: false
                )
            }
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [Color.green, Color.yellow]),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
            .animation(.easeInOut(duration: 0.3), value: self.elevation)

            // 中心点
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)

            // 角度マーカー（-60°〜+60°用に調整）
            ForEach([-60, -30, 0, 30, 60], id: \.self) { angle in
                let markerAngle = (Double(angle) + 60) / 120 * 180  // -60°〜+60° を 0°〜180° にマップ
                let centerX: Double = 30
                let centerY: Double = 30
                let startRadius = angle == 0 ? 20.0 : 22.0
                let endRadius = angle == 0 ? 30.0 : 28.0

                ZStack {
                    Path { path in
                        let startX = centerX + cos(markerAngle * .pi / 180) * startRadius
                        let startY = centerY + sin(markerAngle * .pi / 180) * startRadius
                        let endX = centerX + cos(markerAngle * .pi / 180) * endRadius
                        let endY = centerY + sin(markerAngle * .pi / 180) * endRadius

                        path.move(to: CGPoint(x: startX, y: startY))
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    }
                    .stroke(Color.gray, lineWidth: angle == 0 ? 2 : 1)

                    if angle == 0 {
                        Text("0°")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .position(
                                x: centerX + cos(markerAngle * .pi / 180) * 35,
                                y: centerY + sin(markerAngle * .pi / 180) * 35)
                    }
                }
            }
        }
        .frame(width: 60, height: 40)
    }
}

struct AzimuthCompassView: View {
    let azimuth: Double

    var body: some View {
        ZStack {
            // 背景円
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                .frame(width: 50, height: 50)

            // 方位マーカー（N, E, S, W）
            ForEach([(0, "N"), (90, "E"), (180, "S"), (270, "W")], id: \.0) { angle, label in
                VStack {
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(label == "N" ? .red : .secondary)
                    Rectangle()
                        .fill(label == "N" ? Color.red : Color.gray)
                        .frame(width: 1, height: label == "N" ? 8 : 4)
                }
                .offset(y: -25)
                .rotationEffect(.degrees(Double(angle)))
            }

            // 方位針
            Path { path in
                path.move(to: CGPoint(x: 25, y: 25))
                path.addLine(to: CGPoint(x: 25, y: 8))
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(self.azimuth))
            .animation(.easeInOut(duration: 0.3), value: self.azimuth)

            // 中心点
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
        }
        .frame(width: 50, height: 50)
    }
}

#Preview {
    DataCollectionView()
        .environmentObject(NavigationRouterModel())
}
