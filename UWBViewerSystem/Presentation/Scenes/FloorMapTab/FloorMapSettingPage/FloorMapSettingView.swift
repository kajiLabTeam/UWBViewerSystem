import SwiftData
import SwiftUI

/// フロアマップ設定画面
/// 新しいセンシングフローの最初のステップ
struct FloorMapSettingView: View {
    @StateObject private var viewModel = FloorMapSettingViewModel()
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var flowNavigator = SensingFlowNavigator()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // フロープログレス表示
                SensingFlowProgressView(navigator: flowNavigator)

                ScrollView {
                    VStack(spacing: 24) {
                        // ヘッダー
                        headerSection

                        // フロアマップ設定セクション
                        floorMapSection

                        // 基本情報設定セクション
                        basicInfoSection

                        // プリセット選択セクション
                        presetSection

                        Spacer(minLength: 80)
                    }
                    .padding()
                }

                // ナビゲーションボタン
                navigationButtons
            }
        }
        .onAppear {
            print("🏁 FloorMapSettingView: onAppear called")
            viewModel.setModelContext(modelContext)
            viewModel.setupInitialData()
            flowNavigator.currentStep = .floorMapSetting
            // 共有のRouterをSensingFlowNavigatorに設定
            flowNavigator.setRouter(router)
            print("🏁 FloorMapSettingView: setup completed")
        }
        .alert("エラー", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        #if os(iOS)
        .imagePickerSheet(
            isPresented: $viewModel.isImagePickerPresented,
            selectedImage: $viewModel.selectedFloorMapImage,
            sourceType: viewModel.imagePickerSourceType,
            onImagePicked: viewModel.onImageSelected
        )
        #elseif os(macOS)
        .imagePickerSheet(
            isPresented: $viewModel.isImagePickerPresented,
            selectedImage: $viewModel.selectedFloorMapImage,
            onImagePicked: viewModel.onImageSelected
        )
        #endif
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundColor(.blue)
                    .font(.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text("フロアマップ設定")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("センシングを実行するフロアの情報を設定してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Floor Map Section

    private var floorMapSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("フロアマップ")
                .font(.headline)
                .foregroundColor(.primary)

            // マップ画像表示・選択エリア
            VStack(spacing: 12) {
                if let selectedImage = viewModel.selectedFloorMapImage {
                    #if os(iOS)
                        Image(uiImage: selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                            .clipped()
                    #elseif os(macOS)
                        Image(nsImage: selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                            .clipped()
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 200)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)

                                Text("フロアマップをアップロード")
                                    .font(.headline)
                                    .foregroundColor(.secondary)

                                Text("タップして画像を選択してください")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                }

                // 画像選択ボタン
                HStack(spacing: 12) {
                    Button(action: {
                        print("🔘 FloorMapSettingView: 写真から選択ボタンがクリックされました")
                        viewModel.selectImageFromLibrary()
                    }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("写真から選択")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }

                    Button(action: {
                        print("🔘 FloorMapSettingView: カメラで撮影ボタンがクリックされました")
                        viewModel.captureImageFromCamera()
                    }) {
                        HStack {
                            Image(systemName: "camera")
                            Text("カメラで撮影")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                    }
                    .disabled(!viewModel.isCameraAvailable)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("基本情報")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 16) {
                // フロア名
                VStack(alignment: .leading, spacing: 8) {
                    Text("フロア名")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("例: 1階オフィス", text: $viewModel.floorName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                // 建物名
                VStack(alignment: .leading, spacing: 8) {
                    Text("建物名")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("例: Aビル", text: $viewModel.buildingName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                // フロア寸法
                VStack(alignment: .leading, spacing: 8) {
                    Text("フロア寸法（メートル）")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("幅")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("10.0", value: $viewModel.floorWidth, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                        }

                        Text("×")
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .padding(.top, 16)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("奥行き")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("15.0", value: $viewModel.floorDepth, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Preset Section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("プリセット")
                .font(.headline)
                .foregroundColor(.primary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(viewModel.floorPresets, id: \.id) { preset in
                    FloorPresetCard(
                        preset: preset,
                        isSelected: viewModel.selectedPreset?.id == preset.id,
                        onTap: {
                            viewModel.selectPreset(preset)
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 16) {
                Button("キャンセル") {
                    viewModel.cancelSetup()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.red)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)

                Button("次へ") {
                    if viewModel.saveFloorMapSettings() {
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
    }
}

// MARK: - Floor Preset Card

struct FloorPresetCard: View {
    let preset: FloorMapPreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: preset.iconName)
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .font(.title2)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
                }

                Text(preset.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Text(preset.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)

                HStack {
                    Text("\(preset.width, specifier: "%.1f")m")
                    Text("×")
                    Text("\(preset.depth, specifier: "%.1f")m")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct FloorMapSettingView_Previews: PreviewProvider {
    static var previews: some View {
        FloorMapSettingView()
    }
}
