import SwiftUI

#if os(iOS)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

/// マップ上での基準座標指定によるキャリブレーション画面
struct MapBasedCalibrationView: View {
    @StateObject private var viewModel: MapBasedCalibrationViewModel
    @Environment(\.dismiss) private var dismiss

    let antennaId: String
    let floorMapId: String

    init(antennaId: String, floorMapId: String) {
        self.antennaId = antennaId
        self.floorMapId = floorMapId
        self._viewModel = StateObject(wrappedValue: MapBasedCalibrationViewModel(
            antennaId: antennaId,
            floorMapId: floorMapId
        ))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ヘッダー情報
                headerSection

                // マップ表示エリア
                mapDisplaySection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // コントロールパネル
                controlPanelSection
            }
            .navigationTitle("マップキャリブレーション")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        Task {
                            await viewModel.saveCalibration()
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canComplete)
                }
            }
            .alert("エラー", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("キャリブレーション完了", isPresented: $viewModel.showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("アフィン変換による座標変換が設定されました。\n精度: \(String(format: "%.3f", viewModel.calibrationAccuracy ?? 0.0))m")
            }
        }
        .onAppear {
            viewModel.loadFloorMapImage()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("アンテナ: \(antennaId)")
                    .font(.headline)
                Spacer()
                Text("進捗: \(viewModel.currentPointIndex)/3")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text(viewModel.instructionText)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }

    // MARK: - Map Display Section

    private var mapDisplaySection: some View {
        ZStack {
            // 背景
            Color.gray.opacity(0.1)

            if let mapImage = viewModel.floorMapImage {
                // フロアマップ画像
                GeometryReader { geometry in
                    let imageSize = viewModel.calculateImageSize(for: geometry.size)
                    let imageOffset = viewModel.calculateImageOffset(for: geometry.size, imageSize: imageSize)

                    ZStack {
                        // マップ画像
                        #if os(iOS)
                        Image(uiImage: mapImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageSize.width, height: imageSize.height)
                            .offset(imageOffset)
                            .onTapGesture { location in
                                // タップ位置を画像座標系に変換
                                let imageLocation = viewModel.convertTapToImageCoordinates(
                                    tapLocation: location,
                                    containerSize: geometry.size,
                                    imageSize: imageSize,
                                    imageOffset: imageOffset
                                )

                                if let imageLocation = imageLocation {
                                    viewModel.handleMapTap(at: imageLocation)
                                }
                            }
                        #else
                        Image(nsImage: mapImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageSize.width, height: imageSize.height)
                            .offset(imageOffset)
                            .onTapGesture { location in
                                // タップ位置を画像座標系に変換
                                let imageLocation = viewModel.convertTapToImageCoordinates(
                                    tapLocation: location,
                                    containerSize: geometry.size,
                                    imageSize: imageSize,
                                    imageOffset: imageOffset
                                )

                                if let imageLocation = imageLocation {
                                    viewModel.handleMapTap(at: imageLocation)
                                }
                            }
                        #endif

                        // キャリブレーション点マーカー
                        ForEach(viewModel.calibrationPoints) { point in
                            CalibrationPointMarker(
                                point: point,
                                containerSize: geometry.size,
                                imageSize: imageSize,
                                imageOffset: imageOffset
                            ) {
                                viewModel.removeCalibrationPoint(point)
                            }
                        }

                        // 次に設定する点のプレビュー
                        if viewModel.showPreviewMarker, let previewLocation = viewModel.previewLocation {
                            PreviewMarker(
                                location: previewLocation,
                                pointIndex: viewModel.currentPointIndex + 1,
                                containerSize: geometry.size,
                                imageSize: imageSize,
                                imageOffset: imageOffset
                            )
                        }
                    }
                }
            } else {
                // 読み込み中表示
                VStack {
                    ProgressView()
                    Text("フロアマップを読み込み中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }

    // MARK: - Control Panel Section

    private var controlPanelSection: some View {
        VStack(spacing: 16) {
            // 現在設定中の座標入力
            currentCoordinateInput

            // 設定済み座標一覧
            if !viewModel.calibrationPoints.isEmpty {
                coordinatesList
            }

            // アクションボタン
            actionButtons
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }

    // MARK: - Current Coordinate Input

    private var currentCoordinateInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("基準座標 \(viewModel.currentPointIndex + 1) の実世界座標を入力")
                .font(.headline)

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("X (m)")
                    TextField("0.0", text: $viewModel.inputX)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                VStack(alignment: .leading) {
                    Text("Y (m)")
                    TextField("0.0", text: $viewModel.inputY)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                VStack(alignment: .leading) {
                    Text("Z (m)")
                    TextField("0.0", text: $viewModel.inputZ)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
            }
        }
    }

    // MARK: - Coordinates List

    private var coordinatesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("設定済み基準座標")
                .font(.headline)

            LazyVStack(spacing: 4) {
                ForEach(viewModel.calibrationPoints) { point in
                    MapCalibrationPointRow(point: point) {
                        viewModel.removeCalibrationPoint(point)
                    }
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // キャリブレーション実行ボタン
            if viewModel.calibrationPoints.count >= 3 {
                Button(action: {
                    Task {
                        await viewModel.performCalibration()
                    }
                }) {
                    HStack {
                        if viewModel.isCalculating {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "function")
                        }
                        Text(viewModel.isCalculating ? "計算中..." : "アフィン変換実行")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isCalculating)
            }

            // リセットボタン
            if !viewModel.calibrationPoints.isEmpty {
                Button("すべてクリア") {
                    viewModel.clearAllPoints()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Calibration Point Marker

struct CalibrationPointMarker: View {
    let point: MapCalibrationPoint
    let containerSize: CGSize
    let imageSize: CGSize
    let imageOffset: CGSize
    let onRemove: () -> Void

    var body: some View {
        let markerPosition = calculateMarkerPosition()

        Button(action: onRemove) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 24, height: 24)

                Text("\(point.pointIndex)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .position(x: markerPosition.x, y: markerPosition.y)
    }

    private func calculateMarkerPosition() -> CGPoint {
        let xRatio = point.mapCoordinate.x / imageSize.width
        let yRatio = point.mapCoordinate.y / imageSize.height

        let x = imageOffset.width + imageSize.width * xRatio
        let y = imageOffset.height + imageSize.height * yRatio

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Preview Marker

struct PreviewMarker: View {
    let location: CGPoint
    let pointIndex: Int
    let containerSize: CGSize
    let imageSize: CGSize
    let imageOffset: CGSize

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.blue, lineWidth: 2)
                .fill(Color.blue.opacity(0.3))
                .frame(width: 24, height: 24)

            Text("\(pointIndex)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.blue)
        }
        .position(x: location.x, y: location.y)
        .animation(.easeInOut(duration: 0.3), value: location)
    }
}

// MARK: - Map Calibration Point Row

struct MapCalibrationPointRow: View {
    let point: MapCalibrationPoint
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Text("基準点 \(point.pointIndex)")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("実座標: (\(String(format: "%.2f", point.realWorldCoordinate.x)), \(String(format: "%.2f", point.realWorldCoordinate.y)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("地図座標: (\(String(format: "%.0f", point.mapCoordinate.x)), \(String(format: "%.0f", point.mapCoordinate.y)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(6)
    }
}

// MARK: - Preview

#if DEBUG
struct MapBasedCalibrationView_Previews: PreviewProvider {
    static var previews: some View {
        MapBasedCalibrationView(antennaId: "antenna1", floorMapId: "floor1")
    }
}
#endif