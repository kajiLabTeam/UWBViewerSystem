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

        func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = sourceType
            imagePicker.delegate = context.coordinator
            return imagePicker
        }

        func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) {
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

            func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                if let uiImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                    parent.selectedImage = uiImage
                    parent.onImagePicked(uiImage)
                }
                parent.presentationMode.wrappedValue.dismiss()
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
                do {
                    guard let selectedFile: URL = try result.get().first else { return }
                    if let nsImage = NSImage(contentsOf: selectedFile) {
                        selectedImage.wrappedValue = nsImage
                        onImagePicked(nsImage)
                    }
                } catch {
                    print("Failed to read file: \(error.localizedDescription)")
                }
            }
        }
    }
#endif