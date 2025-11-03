import SwiftUI

enum SheetType: Identifiable {
    case addAntenna
    case editAntenna(AntennaInfo)

    var id: String {
        switch self {
        case .addAntenna:
            return "addAntenna"
        case .editAntenna(let antenna):
            return "editAntenna_\(antenna.id)"
        }
    }
}

struct FieldSettingView: View {
    @StateObject private var viewModel = FieldSettingViewModel()
    @State private var presentedSheet: SheetType?
    @State private var showAddDialog = false
    @State private var dragOffset = CGSize.zero
    @State private var fieldSize = CGSize(width: 500, height: 400)

    var body: some View {
        VStack(spacing: 20) {
            self.headerSection

            HStack(spacing: 20) {
                self.fieldMapSection
                self.antennaListSection
            }
            .padding()

            self.controlSection
        }
        .padding()
        .sheet(isPresented: self.$showAddDialog) {
            SimpleAddAntennaSheet(viewModel: self.viewModel, isPresented: self.$showAddDialog)
        }
        .sheet(item: self.$presentedSheet) { sheetType in
            switch sheetType {
            case .addAntenna:
                EmptyView()  // 使用しない
            case .editAntenna(let antenna):
                EditAntennaSheet(
                    antenna: antenna, viewModel: self.viewModel,
                    showDialog: Binding(
                        get: { self.presentedSheet != nil },
                        set: { if !$0 { self.presentedSheet = nil } }
                    ))
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Label("アンテナ配置設定", systemImage: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("UWBアンテナの配置場所を設定してください")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var fieldMapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.fieldMapHeader
            self.fieldMapCanvas
            self.fieldMapFooter
        }
        .frame(maxWidth: .infinity)
    }

    private var fieldMapHeader: some View {
        HStack {
            Label("フィールドマップ", systemImage: "map")
                .font(.headline)

            Spacer()

            Button(action: { self.viewModel.resetField() }) {
                Label("リセット", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.bordered)
        }
    }

    private var fieldMapCanvas: some View {
        ZStack {
            GeometryReader { geometry in
                self.gridBackground(for: geometry.size)
                self.antennaOverlay(for: geometry)
            }
        }
        .frame(height: 400)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    private func gridBackground(for size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let gridSize: CGFloat = 20
            let columns = Int(canvasSize.width / gridSize)
            let rows = Int(canvasSize.height / gridSize)

            context.stroke(
                Path { path in
                    for i in 0...columns {
                        let x = CGFloat(i) * gridSize
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    }
                    for i in 0...rows {
                        let y = CGFloat(i) * gridSize
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    }
                },
                with: .color(.gray.opacity(0.2)),
                lineWidth: 0.5
            )
        }
    }

    private func antennaOverlay(for geometry: GeometryProxy) -> some View {
        ForEach(self.viewModel.antennas) { antenna in
            FieldAntennaMarker(antenna: antenna)
                .position(
                    x: antenna.position.x * geometry.size.width,
                    y: antenna.position.y * geometry.size.height
                )
                .onTapGesture {
                    self.presentedSheet = .editAntenna(antenna.toDomainEntity())
                }
                .onDrag {
                    NSItemProvider(object: antenna.id as NSString)
                }
        }
        .onDrop(of: [.text], isTargeted: nil) { providers, location in
            self.handleDrop(providers: providers, location: location, in: geometry.size)
            return true
        }
    }

    private var fieldMapFooter: some View {
        HStack {
            Text("フィールドサイズ: \(Int(self.fieldSize.width)) x \(Int(self.fieldSize.height)) m")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text("アンテナ数: \(self.viewModel.antennas.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var antennaListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("アンテナ一覧", systemImage: "list.bullet")
                    .font(.headline)

                Spacer()

                Button(action: { self.showAddDialog = true }) {
                    Label("追加", systemImage: "plus.circle.fill")
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(self.viewModel.antennas) { antenna in
                        AntennaListItem(antenna: antenna) {
                            self.presentedSheet = .editAntenna(antenna.toDomainEntity())
                        } onDelete: {
                            self.viewModel.removeAntenna(antenna)
                        }
                    }

                    if self.viewModel.antennas.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.3))

                            Text("アンテナが配置されていません")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Button("アンテナを追加") {
                                self.showAddDialog = true
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.gray.opacity(0.02))
            .cornerRadius(8)
        }
        .frame(width: 350)
    }

    private var controlSection: some View {
        HStack(spacing: 16) {
            Button(action: self.viewModel.loadConfiguration) {
                Label("設定を読み込む", systemImage: "doc.badge.arrow.up")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.bordered)

            Button(action: self.viewModel.saveConfiguration) {
                Label("設定を保存", systemImage: "square.and.arrow.down")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: {
                // Navigate to next screen
                self.viewModel.proceedToNextStep()
            }) {
                Label("次へ", systemImage: "arrow.right.circle.fill")
                    .padding(.horizontal, 20)
                    .foregroundColor(.white)
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.viewModel.antennas.isEmpty)
        }
        .padding()
    }

    private func handleDrop(providers: [NSItemProvider], location: CGPoint, in size: CGSize) {
        // Handle antenna repositioning via drag and drop
        guard let provider = providers.first else { return }

        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let antennaId = item as? String else { return }

            Task { @MainActor in
                guard let antenna = viewModel.antennas.first(where: { $0.id == antennaId }) else { return }

                self.viewModel.updateAntennaPosition(
                    antenna,
                    position: CGPoint(
                        x: location.x / size.width,
                        y: location.y / size.height
                    )
                )
            }
        }
    }
}

struct FieldAntennaMarker: View {
    let antenna: FieldAntennaInfo

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(self.antenna.color.gradient)
                    .frame(width: 40, height: 40)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
            }

            Text(self.antenna.name)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(4)
        }
    }
}

struct AntennaListItem: View {
    let antenna: FieldAntennaInfo
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(self.antenna.color.gradient)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.antenna.name)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)

                Text(
                    "X: \(self.antenna.coordinates.x, specifier: "%.1f")m, Y: \(self.antenna.coordinates.y, specifier: "%.1f")m, Z: \(self.antenna.coordinates.z, specifier: "%.1f")m"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: self.onEdit) {
                Image(systemName: "pencil.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Button(action: self.onDelete) {
                Image(systemName: "trash.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct AddAntennaSheet: View {
    @ObservedObject var viewModel: FieldSettingViewModel
    @Binding var showDialog: Bool
    @Environment(\.dismiss) var dismiss

    @State private var antennaName = ""
    @State private var xCoordinate = ""
    @State private var yCoordinate = ""
    @State private var zCoordinate = "1.5"
    @State private var selectedColor = AntennaColor.blue

    var body: some View {
        NavigationStack {
            Form {
                self.antennaInfoSection
                self.coordinatesSection
            }
            .navigationTitle("アンテナを追加")
            .navigationBarTitleDisplayModeIfAvailable(.inline)
            .toolbar(content: self.toolbarContent)
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #else
        .frame(width: 400, height: 350)
        #endif
        .interactiveDismissDisabled(false)
    }

    private var antennaInfoSection: some View {
        Section("アンテナ情報") {
            TextField("アンテナ名", text: self.$antennaName)
            Picker("識別色", selection: self.$selectedColor) {
                ForEach(AntennaColor.allCases, id: \.self) { color in
                    HStack {
                        Circle()
                            .fill(color.color)
                            .frame(width: 16, height: 16)
                        Text(color.rawValue.capitalized)
                    }
                    .tag(color)
                }
            }
        }
    }

    private var coordinatesSection: some View {
        Section("座標 (メートル)") {
            HStack {
                Text("X:")
                TextField("0.0", text: self.$xCoordinate)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Y:")
                TextField("0.0", text: self.$yCoordinate)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Z:")
                TextField("1.5", text: self.$zCoordinate)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("キャンセル") {
                self.showDialog = false
                self.dismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("追加") {
                let antenna = FieldAntennaInfo(
                    name: antennaName.isEmpty ? "アンテナ\(self.viewModel.antennas.count + 1)" : self.antennaName,
                    coordinates: Point3D(
                        x: Double(self.xCoordinate) ?? 0,
                        y: Double(self.yCoordinate) ?? 0,
                        z: Double(self.zCoordinate) ?? 1.5
                    ),
                    antennaColor: self.selectedColor
                )

                print("アンテナ追加開始: \(antenna.name)")
                self.viewModel.addAntenna(antenna)
                print("アンテナ追加完了、ダイアログクローズ開始")

                // メインスレッドで確実に実行
                Task { @MainActor in
                    self.showDialog = false
                    print("showDialog = false 実行完了")
                    self.dismiss()
                    print("dismiss() 実行完了")
                }
            }
        }
    }
}

struct SimpleAddAntennaSheet: View {
    @ObservedObject var viewModel: FieldSettingViewModel
    @Binding var isPresented: Bool
    @Environment(\.dismiss) var dismiss

    @State private var antennaName = ""
    @State private var xCoordinate = ""
    @State private var yCoordinate = ""
    @State private var zCoordinate = "1.5"
    @State private var selectedColor = AntennaColor.blue

    var body: some View {
        NavigationStack {
            Form {
                Section("アンテナ情報") {
                    TextField("アンテナ名", text: self.$antennaName)
                    Picker("識別色", selection: self.$selectedColor) {
                        ForEach(AntennaColor.allCases, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 16, height: 16)
                                Text(color.rawValue.capitalized)
                            }
                            .tag(color)
                        }
                    }
                }

                Section("座標 (メートル)") {
                    HStack {
                        Text("X:")
                        TextField("0.0", text: self.$xCoordinate)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Y:")
                        TextField("0.0", text: self.$yCoordinate)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Z:")
                        TextField("1.5", text: self.$zCoordinate)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .navigationTitle("アンテナを追加")
            .navigationBarTitleDisplayModeIfAvailable(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        self.isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        let antenna = FieldAntennaInfo(
                            name: antennaName.isEmpty ? "アンテナ\(self.viewModel.antennas.count + 1)" : self.antennaName,
                            coordinates: Point3D(
                                x: Double(self.xCoordinate) ?? 0,
                                y: Double(self.yCoordinate) ?? 0,
                                z: Double(self.zCoordinate) ?? 1.5
                            ),
                            antennaColor: self.selectedColor
                        )

                        self.viewModel.addAntenna(antenna)
                        self.isPresented = false
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #else
        .frame(width: 400, height: 350)
        #endif
    }
}

struct EditAntennaSheet: View {
    let antenna: AntennaInfo
    @ObservedObject var viewModel: FieldSettingViewModel
    @Binding var showDialog: Bool
    @Environment(\.dismiss) var dismiss

    @State private var antennaName = ""
    @State private var xCoordinate = ""
    @State private var yCoordinate = ""
    @State private var zCoordinate = ""
    @State private var selectedColor = AntennaColor.blue

    var body: some View {
        NavigationStack {
            Form {
                self.editAntennaInfoSection
                self.editCoordinatesSection
            }
            .navigationTitle("アンテナを編集")
            .navigationBarTitleDisplayModeIfAvailable(.inline)
            .toolbar(content: self.editToolbarContent)
        }
        .frame(width: 400, height: 350)
        .onAppear {
            self.antennaName = self.antenna.name
            self.xCoordinate = String(self.antenna.coordinates.x)
            self.yCoordinate = String(self.antenna.coordinates.y)
            self.zCoordinate = String(self.antenna.coordinates.z)
            self.selectedColor = .blue  // デフォルト値
        }
    }

    private var editAntennaInfoSection: some View {
        Section("アンテナ情報") {
            TextField("アンテナ名", text: self.$antennaName)
            Picker("識別色", selection: self.$selectedColor) {
                ForEach(AntennaColor.allCases, id: \.self) { color in
                    HStack {
                        Circle()
                            .fill(color.color)
                            .frame(width: 16, height: 16)
                        Text(color.rawValue.capitalized)
                    }
                    .tag(color)
                }
            }
        }
    }

    private var editCoordinatesSection: some View {
        Section("座標 (メートル)") {
            HStack {
                Text("X:")
                TextField("0.0", text: self.$xCoordinate)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Y:")
                TextField("0.0", text: self.$yCoordinate)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Z:")
                TextField("1.5", text: self.$zCoordinate)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ToolbarContentBuilder
    private func editToolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("キャンセル") {
                self.showDialog = false
                self.dismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("保存") {
                let updatedAntenna = FieldAntennaInfo(
                    id: antenna.id,
                    name: self.antennaName,
                    coordinates: Point3D(
                        x: Double(self.xCoordinate) ?? self.antenna.coordinates.x,
                        y: Double(self.yCoordinate) ?? self.antenna.coordinates.y,
                        z: Double(self.zCoordinate) ?? self.antenna.coordinates.z
                    ),
                    antennaColor: self.selectedColor
                )
                self.viewModel.updateAntenna(updatedAntenna)
                self.showDialog = false
                self.dismiss()
            }
        }
    }
}

#Preview {
    FieldSettingView()
}
