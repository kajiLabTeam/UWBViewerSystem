import Foundation

@MainActor
class BaseViewModel: ObservableObject {
    @Published var errorMessage: String = ""
    @Published var showErrorAlert: Bool = false
    @Published var isLoading: Bool = false

    func showError(_ message: String) {
        self.errorMessage = message
        self.showErrorAlert = true
    }

    func startLoading() {
        self.isLoading = true
    }

    func stopLoading() {
        self.isLoading = false
    }
}
