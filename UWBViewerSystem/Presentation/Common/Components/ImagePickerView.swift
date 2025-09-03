import SwiftUI
import UIKit

/// UIImagePickerControllerのSwiftUIラッパー
struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selectedImage: UIImage?
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: ((UIImage) -> Void)?

    init(
        isPresented: Binding<Bool>,
        selectedImage: Binding<UIImage?>,
        sourceType: UIImagePickerController.SourceType,
        onImagePicked: ((UIImage) -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self._selectedImage = selectedImage
        self.sourceType = sourceType
        self.onImagePicked = onImagePicked
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
                parent.onImagePicked?(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

/// ImagePickerViewを使用するためのView拡張
extension View {
    func imagePickerSheet(
        isPresented: Binding<Bool>,
        selectedImage: Binding<UIImage?>,
        sourceType: UIImagePickerController.SourceType,
        onImagePicked: ((UIImage) -> Void)? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ImagePickerView(
                isPresented: isPresented,
                selectedImage: selectedImage,
                sourceType: sourceType,
                onImagePicked: onImagePicked
            )
        }
    }
}
