import SwiftUI

/// カードスタイルのコンテナビュー
struct CardView<Content: View>: View {
    let content: Content
    let padding: CGFloat

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        self.content
            .padding(self.padding)
        #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #else
            .background(Color(UIColor.systemBackground))
        #endif
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

/// セクションヘッダー付きカード
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String?
    let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ヘッダー
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                Text(self.title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            // コンテンツ
            self.content
        }
        .padding()
        #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #else
            .background(Color(UIColor.systemBackground))
        #endif
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview("Cards") {
    VStack(spacing: 16) {
        CardView {
            Text("シンプルなカードビュー")
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        SectionCard(title: "セクションタイトル", systemImage: "star.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("コンテンツ1")
                Text("コンテンツ2")
                Text("コンテンツ3")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
