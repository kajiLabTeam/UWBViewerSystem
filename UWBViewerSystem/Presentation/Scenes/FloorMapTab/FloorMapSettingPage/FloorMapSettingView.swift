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
        VStack(spacing: 0) {
            // フロープログレス表示
            SensingFlowProgressView(navigator: self.flowNavigator)

            ScrollView {
                VStack(spacing: 24) {
                    // ヘッダー
                    self.headerSection

                    // フロアマップ設定セクション
                    self.floorMapSection

                    // 基本情報設定セクション
                    self.basicInfoSection

                    Spacer(minLength: 80)
                }
                .padding()
            }

            // ナビゲーションボタン
            self.navigationButtons
        }
        .onAppear {
            print("🏁 FloorMapSettingView: onAppear called")
            self.viewModel.setModelContext(self.modelContext)
            self.viewModel.setupInitialData()
            self.flowNavigator.currentStep = .floorMapSetting
            // 共有のRouterをSensingFlowNavigatorに設定
            self.flowNavigator.setRouter(self.router)
            print("🏁 FloorMapSettingView: setup completed")
        }
        .alert("エラー", isPresented: self.$viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.viewModel.errorMessage)
        }
        #if os(iOS)
        .imagePickerSheet(
            isPresented: self.$viewModel.isImagePickerPresented,
            selectedImage: self.$viewModel.selectedFloorMapImage,
            sourceType: self.viewModel.imagePickerSourceType,
            onImagePicked: self.viewModel.onImageSelected
        )
        #elseif os(macOS)
        .imagePickerSheet(
            isPresented: self.$viewModel.isImagePickerPresented,
            selectedImage: self.$viewModel.selectedFloorMapImage,
            onImagePicked: self.viewModel.onImageSelected
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
                        self.viewModel.selectImageFromLibrary()
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
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
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

                    TextField("例: 1階オフィス", text: self.$viewModel.floorName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                // 建物名
                VStack(alignment: .leading, spacing: 8) {
                    Text("建物名")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("例: Aビル", text: self.$viewModel.buildingName)
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
                            TextField("10.0", value: self.$viewModel.floorWidth, format: .number)
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
                            TextField("15.0", value: self.$viewModel.floorDepth, format: .number)
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
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 16) {
                Button("キャンセル") {
                    self.viewModel.cancelSetup()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.red)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)

                Button("次へ") {
                    Task {
                        if await self.viewModel.saveFloorMapSettings() {
                            self.flowNavigator.proceedToNextStep()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(self.viewModel.canProceedToNext ? Color.blue : Color.gray)
                .cornerRadius(8)
                .disabled(!self.viewModel.canProceedToNext)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Preview

struct FloorMapSettingView_Previews: PreviewProvider {
    static var previews: some View {
        FloorMapSettingView()
    }
}
