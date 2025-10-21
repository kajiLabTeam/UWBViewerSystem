import SwiftUI

#if os(iOS)
    import UIKit

    extension View {
        func imagePickerSheet(
            isPresented: Binding<Bool>,
            selectedImage: Binding<UIImage?>,
            sourceType: UIImagePickerController.SourceType = .photoLibrary,
            onImagePicked: @escaping (UIImage) -> Void
        ) -> some View {
            sheet(isPresented: isPresented) {
                ImagePicker(
                    selectedImage: selectedImage,
                    sourceType: sourceType,
                    onImagePicked: onImagePicked
                )
            }
        }
    }

    struct ImagePicker: UIViewControllerRepresentable {
        @Binding var selectedImage: UIImage?
        var sourceType: UIImagePickerController.SourceType = .photoLibrary
        var onImagePicked: (UIImage) -> Void
        @Environment(\.presentationMode) private var presentationMode

        func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController
        {
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = self.sourceType
            imagePicker.delegate = context.coordinator
            return imagePicker
        }

        func updateUIViewController(
            _ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>
        ) {
            // No update needed
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            var parent: ImagePicker

            init(_ parent: ImagePicker) {
                self.parent = parent
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                if let uiImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                    self.parent.selectedImage = uiImage
                    self.parent.onImagePicked(uiImage)
                }
                self.parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }

#elseif os(macOS)
    import AppKit

    extension View {
        func imagePickerSheet(
            isPresented: Binding<Bool>,
            selectedImage: Binding<NSImage?>,
            sourceType: Any? = nil,
            onImagePicked: @escaping (NSImage) -> Void
        ) -> some View {
            fileImporter(
                isPresented: isPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                print("🔄 ImagePickerSheet (macOS): fileImporter result received")
                do {
                    guard let selectedFile: URL = try result.get().first else {
                        print("❌ ImagePickerSheet (macOS): No file selected")
                        return
                    }
                    print("📁 ImagePickerSheet (macOS): Selected file: \(selectedFile.path)")

                    // セキュリティスコープ付きリソースアクセスを開始
                    let accessGranted = selectedFile.startAccessingSecurityScopedResource()
                    print("🔐 ImagePickerSheet (macOS): Security scoped access granted: \(accessGranted)")

                    defer {
                        if accessGranted {
                            selectedFile.stopAccessingSecurityScopedResource()
                            print("🔐 ImagePickerSheet (macOS): Security scoped access stopped")
                        }
                    }

                    // まずファイルが存在するか確認
                    if !FileManager.default.fileExists(atPath: selectedFile.path) {
                        print("❌ ImagePickerSheet (macOS): File does not exist at path")
                        return
                    }

                    // NSDataを使って画像データを読み込む
                    if let imageData = NSData(contentsOf: selectedFile),
                       let nsImage = NSImage(data: imageData as Data)
                    {
                        print(
                            "🖼️ ImagePickerSheet (macOS): Image loaded successfully via NSData - size: \(nsImage.size)")
                        DispatchQueue.main.async {
                            print("🔄 ImagePickerSheet (macOS): Calling onImagePicked")
                            onImagePicked(nsImage)
                        }
                    } else {
                        print("❌ ImagePickerSheet (macOS): Failed to load image via NSData")

                        // フォールバック: NSImage(contentsOf:)を試す
                        if let nsImage = NSImage(contentsOf: selectedFile) {
                            print(
                                "🖼️ ImagePickerSheet (macOS): Image loaded successfully via NSImage(contentsOf:) - size: \(nsImage.size)"
                            )
                            DispatchQueue.main.async {
                                print("🔄 ImagePickerSheet (macOS): Calling onImagePicked")
                                onImagePicked(nsImage)
                            }
                        } else {
                            print("❌ ImagePickerSheet (macOS): All image loading methods failed")
                        }
                    }
                } catch {
                    print("❌ ImagePickerSheet (macOS): Failed to read file: \(error.localizedDescription)")
                }
            }
        }
    }
#endif
