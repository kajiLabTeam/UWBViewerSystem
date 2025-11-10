import SwiftData
import SwiftUI

/// 自動アンテナキャリブレーション画面
///
/// 各アンテナの位置と角度を自動推定するためのキャリブレーション画面。
/// 複数のタグ位置（既知）でセンシングを行い、各アンテナが観測した座標から
/// アフィン変換を推定してアンテナのANTENNA_CONFIGを自動生成します。
struct AutoAntennaCalibrationView: View {
    @StateObject private var viewModel = AutoAntennaCalibrationViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            self.headerSection

            // フルスクリーンマップ with フローティングコントロール
            ZStack {
                // 背景: フルスクリーンマップ
                CalibrationMapCanvasSection(viewModel: self.viewModel)

                // 左側: コントロールパネル
                VStack {
                    HStack {
                        FloatingCalibrationControlPanel(viewModel: self.viewModel)
                            .frame(maxWidth: 450)

                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)
            }
        }
        .onAppear {
            self.viewModel.setup(modelContext: self.modelContext)
        }
        .alert("エラー", isPresented: self.$viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.viewModel.errorMessage)
        }
        .alert("キャリブレーション完了", isPresented: self.$viewModel.showSuccessAlert) {
            Button("新しいキャリブレーション", role: .none) {
                self.viewModel.resetCalibration()
            }
            Button("完了", role: .cancel) {}
        } message: {
            Text("全てのアンテナのキャリブレーションが正常に完了しました")
        }
        .sheet(isPresented: self.$viewModel.showConnectionRecovery) {
            ConnectionRecoveryView(
                connectionUsecase: ConnectionManagementUsecase.shared,
                isPresented: self.$viewModel.showConnectionRecovery
            )
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.blue)
                    .font(.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text("自動アンテナキャリブレーション")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("ステップ \(self.viewModel.currentStep + 1) / 4: \(self.viewModel.currentStepTitle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if self.viewModel.currentAntennaId != nil {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("対象アンテナ")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(self.viewModel.currentAntennaName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
            }

            ProgressView(value: Double(self.viewModel.currentStep), total: 3.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }
}

// MARK: - Calibration Map Canvas Section

struct CalibrationMapCanvasSection: View {
    @ObservedObject var viewModel: AutoAntennaCalibrationViewModel

    var body: some View {
        if let floorMapImage = viewModel.floorMapImage,
           let floorMapInfo = viewModel.currentFloorMapInfo
        {
            FloorMapCanvas(
                floorMapImage: floorMapImage,
                floorMapInfo: floorMapInfo,
                calibrationPoints: nil,
                onMapTap: self.handleMapTap,
                enableZoom: true,
                fixedHeight: nil,
                showGrid: true
            ) { geometry in
                // 他のアンテナ位置マーカー（現在のアンテナ以外）
                ForEach(self.viewModel.allAntennaPositions.filter { $0.antennaId != self.viewModel.currentAntennaId }) { antennaPos in
                    let normalizedPoint = geometry.realWorldToNormalized(
                        CGPoint(x: antennaPos.position.x, y: antennaPos.position.y)
                    )
                    let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                    let antennaDisplayData = AntennaDisplayData(
                        id: antennaPos.antennaId,
                        name: antennaPos.antennaName,
                        rotation: antennaPos.rotation,
                        color: Color.gray.opacity(0.6)
                    )

                    AntennaMarker(
                        antenna: antennaDisplayData,
                        position: displayPosition,
                        size: geometry.antennaSizeInPixels(),
                        sensorRange: nil,
                        isSelected: false,
                        isDraggable: false,
                        showRotationControls: false
                    )
                }

                // 現在キャリブレーション中のアンテナ位置
                if let currentAntenna = self.viewModel.originalAntennaPosition {
                    let normalizedPoint = geometry.realWorldToNormalized(
                        CGPoint(x: currentAntenna.position.x, y: currentAntenna.position.y)
                    )
                    let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                    let currentAntennaDisplayData = AntennaDisplayData(
                        id: currentAntenna.antennaId,
                        name: currentAntenna.antennaName,
                        rotation: currentAntenna.rotation,
                        color: Color.blue
                    )

                    AntennaMarker(
                        antenna: currentAntennaDisplayData,
                        position: displayPosition,
                        size: geometry.antennaSizeInPixels(),
                        sensorRange: geometry.sensorRangeInPixels(),
                        isSelected: true,
                        isDraggable: false,
                        showRotationControls: false
                    )
                }

                // キャリブレーション結果表示（ステップ3）
                if self.viewModel.currentStep == 3, let result = self.viewModel.currentAntennaResult {
                    // 変更前のアンテナ位置（赤、半透明）
                    if let original = self.viewModel.originalAntennaPosition {
                        let originalNormalizedPoint = geometry.realWorldToNormalized(
                            CGPoint(x: original.position.x, y: original.position.y)
                        )
                        let originalDisplayPosition = geometry.normalizedToImageCoordinate(originalNormalizedPoint)

                        let originalAntennaDisplayData = AntennaDisplayData(
                            id: original.antennaId,
                            name: "変更前",
                            rotation: original.rotation,
                            color: Color.red.opacity(0.5)
                        )

                        AntennaMarker(
                            antenna: originalAntennaDisplayData,
                            position: originalDisplayPosition,
                            size: geometry.antennaSizeInPixels(),
                            sensorRange: nil,
                            isSelected: false,
                            isDraggable: false,
                            showRotationControls: false
                        )

                        // 変更前から変更後への移動線
                        let newNormalizedPoint = geometry.realWorldToNormalized(
                            CGPoint(x: result.position.x, y: result.position.y)
                        )
                        let newDisplayPosition = geometry.normalizedToImageCoordinate(newNormalizedPoint)

                        Path { path in
                            path.move(to: originalDisplayPosition)
                            path.addLine(to: newDisplayPosition)
                        }
                        .stroke(Color.purple.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 4]))
                    }

                    // 推定されたアンテナ位置（新しい位置）
                    let antennaNormalizedPoint = geometry.realWorldToNormalized(
                        CGPoint(x: result.position.x, y: result.position.y)
                    )
                    let antennaDisplayPosition = geometry.normalizedToImageCoordinate(antennaNormalizedPoint)

                    let newAntennaDisplayData = AntennaDisplayData(
                        id: self.viewModel.currentAntennaId ?? "",
                        name: self.viewModel.currentAntennaName,
                        rotation: result.angleDegrees,
                        color: Color.blue
                    )

                    AntennaMarker(
                        antenna: newAntennaDisplayData,
                        position: antennaDisplayPosition,
                        size: geometry.antennaSizeInPixels(),
                        sensorRange: nil,
                        isSelected: true,
                        isDraggable: false,
                        showRotationControls: false
                    )
                }

                // タグ位置マーカー
                ForEach(Array(self.viewModel.trueTagPositions.enumerated()), id: \.offset) { index, tagPos in
                    let normalizedPoint = geometry.realWorldToNormalized(
                        CGPoint(x: tagPos.position.x, y: tagPos.position.y)
                    )
                    let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                    let isCurrentTag = index == self.viewModel.currentTagPositionIndex
                    let color: Color = tagPos.isCollected ? .green : (isCurrentTag ? .orange : .blue)

                    ZStack {
                        Circle()
                            .fill(color)
                            .frame(width: 16, height: 16)

                        Text("\(index + 1)")
                            .font(.system(size: 8))
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if tagPos.isCollected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 6))
                                .foregroundColor(.white)
                                .offset(x: 6, y: -6)
                        }
                    }
                    .position(displayPosition)
                }

                // 測定データポイント（センシング中のみ）
                if self.viewModel.isCollecting {
                    ForEach(Array(self.viewModel.currentSensingDataPoints.enumerated()), id: \.offset) { _, dataPoint in
                        let normalizedPoint = geometry.realWorldToNormalized(
                            CGPoint(x: dataPoint.x, y: dataPoint.y)
                        )
                        let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                        Circle()
                            .fill(Color.red.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .position(displayPosition)
                    }
                }
            }
        } else {
            ZStack {
                Color.secondary.opacity(0.1)

                VStack(spacing: 12) {
                    ProgressView()
                    Text("フロアマップを読み込んでいます...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func handleMapTap(at location: CGPoint) {
        guard self.viewModel.currentStep == 1 else { return }

        let point = Point3D(
            x: Double(location.x),
            y: Double(location.y),
            z: 0.0
        )
        self.viewModel.addTagPosition(at: point)
    }
}

// MARK: - Floating Calibration Control Panel

struct FloatingCalibrationControlPanel: View {
    @ObservedObject var viewModel: AutoAntennaCalibrationViewModel
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.blue)

                Text("ステップ \(self.viewModel.currentStep + 1) / 4")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    withAnimation {
                        self.isExpanded.toggle()
                    }
                }) {
                    Image(systemName: self.isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color.blue.opacity(0.1))

            if self.isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // ステップコンテンツ
                        self.currentStepContent

                        // ナビゲーションボタン
                        self.navigationButtons
                    }
                    .padding()
                }
                .frame(maxHeight: 600)
            }
        }
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
        .background(Color(UIColor.systemBackground))
        #endif
        .cornerRadius(12)
        .shadow(radius: 8)
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch self.viewModel.currentStep {
        case 0:
            self.antennaSelectionStepCompact
        case 1:
            self.tagPositionSetupStepCompact
        case 2:
            self.dataCollectionStepCompact
        case 3:
            self.calibrationResultStepCompact
        default:
            EmptyView()
        }
    }

    // MARK: - Step 0: アンテナ選択（コンパクト版）

    private var antennaSelectionStepCompact: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("アンテナ選択")
                .font(.subheadline)
                .fontWeight(.medium)

            if self.viewModel.availableAntennas.isEmpty {
                Text("利用可能なアンテナがありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(self.viewModel.availableAntennas) { antenna in
                        let isSelected = self.viewModel.currentAntennaId == antenna.id
                        let isCompleted = self.viewModel.completedAntennaIds.contains(antenna.id)

                        Button(action: {
                            self.viewModel.selectAntennaForCalibration(antenna.id)
                        }) {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isCompleted ? .green : (isSelected ? .blue : .gray))

                                Text(antenna.name)
                                    .font(.caption)
                                    .foregroundColor(.primary)

                                if isCompleted {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                        .font(.caption2)
                                }

                                Spacer()
                            }
                            .padding(8)
                            .background(
                                isCompleted ? Color.green.opacity(0.1) :
                                    isSelected ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05)
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            if !self.viewModel.completedAntennaIds.isEmpty {
                Text("完了: \(self.viewModel.completedAntennaIds.count) / \(self.viewModel.availableAntennas.count)")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    // MARK: - Step 1: タグ位置設定（コンパクト版）

    private var tagPositionSetupStepCompact: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("タグ位置設定")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("マップをタップして既知のタグ位置を3つ以上設定してください")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("設定済み: \(self.viewModel.trueTagPositions.count)個")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                if !self.viewModel.trueTagPositions.isEmpty {
                    Button("全てクリア") {
                        self.viewModel.clearTagPositions()
                    }
                    .font(.caption2)
                    .foregroundColor(.red)
                }
            }

            if !self.viewModel.trueTagPositions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(self.viewModel.trueTagPositions.enumerated()), id: \.offset) {
                        index, tagPos in
                        HStack {
                            Circle()
                                .fill(tagPos.isCollected ? Color.green : Color.blue)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Text("\(index + 1)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )

                            Text("X: \(String(format: "%.2f", tagPos.position.x))m, Y: \(String(format: "%.2f", tagPos.position.y))m")
                                .font(.caption2)

                            Spacer()

                            Button(action: {
                                self.viewModel.removeTagPosition(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .font(.caption2)
                            }
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - Step 2: データ収集（コンパクト版）

    private var dataCollectionStepCompact: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("データ収集")
                .font(.subheadline)
                .fontWeight(.medium)

            // 進行状況
            let completedCount = self.viewModel.trueTagPositions.filter { $0.isCollected }.count
            VStack(alignment: .leading, spacing: 6) {
                Text("進行状況: \(completedCount) / \(self.viewModel.trueTagPositions.count)")
                    .font(.caption)
                    .fontWeight(.medium)

                ProgressView(value: self.viewModel.collectionProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            }

            // 現在のタグ位置
            if let currentTag = self.viewModel.currentTagPosition {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("測定位置: \(currentTag.tagId)")
                                .font(.caption)
                                .fontWeight(.bold)

                            Text("X: \(String(format: "%.2f", currentTag.position.x))m, Y: \(String(format: "%.2f", currentTag.position.y))m")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if currentTag.isCollected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(8)
                    .background(currentTag.isCollected ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                    .cornerRadius(6)

                    // センシング中のインジケーター
                    if self.viewModel.isCollecting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("センシング中...")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }

                    // センシング開始ボタン
                    if !currentTag.isCollected && !self.viewModel.isCollecting {
                        Button(action: {
                            self.viewModel.startCurrentTagPositionCollection()
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("センシング開始")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .foregroundColor(.white)
                            .background(Color.green)
                            .cornerRadius(8)
                        }
                    }
                    // 次の位置へ & 前のタグに戻る
                    else if self.viewModel.hasMoreTagPositions {
                        HStack(spacing: 8) {
                            // 前のタグに戻るボタン
                            if self.viewModel.canGoToPreviousTag {
                                Button(action: {
                                    self.viewModel.goToPreviousTagPosition()
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.left.circle.fill")
                                        Text("前のタグへ")
                                    }
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .foregroundColor(.white)
                                    .background(Color.orange)
                                    .cornerRadius(8)
                                }
                            }

                            // 次のタグ位置へボタン
                            Button(action: {
                                self.viewModel.proceedToNextTagPosition()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.right.circle.fill")
                                    Text("次のタグ位置へ")
                                }
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                        }
                    }
                    // 最後のタグで「前のタグに戻る」のみ表示
                    else if self.viewModel.canGoToPreviousTag {
                        Button(action: {
                            self.viewModel.goToPreviousTagPosition()
                        }) {
                            HStack {
                                Image(systemName: "arrow.left.circle.fill")
                                Text("前のタグへ")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .foregroundColor(.white)
                            .background(Color.orange)
                            .cornerRadius(8)
                        }
                    }
                }
            }

            // データ統計（コンパクト版）
            if !self.viewModel.dataStatistics.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("収集データ")
                        .font(.caption)
                        .fontWeight(.medium)

                    ForEach(Array(self.viewModel.dataStatistics.keys.sorted()), id: \.self) { antennaId in
                        if let tagData = viewModel.dataStatistics[antennaId] {
                            let totalCount = tagData.values.reduce(0, +)
                            Text("\(antennaId): \(totalCount)件")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Step 3: キャリブレーション結果（コンパクト版）

    private var calibrationResultStepCompact: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("キャリブレーション結果")
                .font(.subheadline)
                .fontWeight(.medium)

            if let result = self.viewModel.currentAntennaResult {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)

                        Text("\(self.viewModel.currentAntennaName) 完了")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("位置:")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("X: \(String(format: "%.3f", result.position.x))m, Y: \(String(format: "%.3f", result.position.y))m")
                                .font(.caption2)
                        }

                        HStack {
                            Text("角度:")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("\(String(format: "%.2f", result.angleDegrees))°")
                                .font(.caption2)
                        }

                        HStack {
                            Text("RMSE:")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("\(String(format: "%.4f", result.rmse))m")
                                .font(.caption2)
                                .foregroundColor(
                                    result.rmse < 0.1 ? .green : (result.rmse < 0.3 ? .orange : .red)
                                )
                        }
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)

                    // 次のアンテナへ進むボタン
                    if self.viewModel.hasMoreAntennas {
                        Button(action: {
                            self.viewModel.proceedToNextAntenna()
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("次のアンテナへ")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text("全てのアンテナ完了")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)

                            Button(action: {
                                self.viewModel.resetCalibration()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("新しいキャリブレーション")
                                }
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .foregroundColor(.blue)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            } else if self.viewModel.isCalibrating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("キャリブレーション実行中...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            } else {
                Button(action: {
                    self.viewModel.startCalibration()
                }) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                        Text("キャリブレーション実行")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .foregroundColor(.white)
                    .background(self.viewModel.canStartCalibration ? Color.blue : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(!self.viewModel.canStartCalibration)
            }
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if self.viewModel.canGoBack {
                Button("戻る") {
                    self.viewModel.goBack()
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(8)
                .foregroundColor(.blue)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            if self.viewModel.canProceedToNext {
                Button("次へ") {
                    self.viewModel.proceedToNext()
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(8)
                .foregroundColor(.white)
                .background(Color.blue)
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Preview

struct AutoAntennaCalibrationView_Previews: PreviewProvider {
    static var previews: some View {
        AutoAntennaCalibrationView()
    }
}
