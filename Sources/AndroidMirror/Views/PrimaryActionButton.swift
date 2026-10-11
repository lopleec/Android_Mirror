import SwiftUI

enum MirrorLayout {
    static let credentialWidth: CGFloat = 240
    static let fieldHeight: CGFloat = 30
    static let controlRadius: CGFloat = 6
}

struct PrimaryActionButton: View {
    let title: String
    var symbol: String? = nil
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1).minimumScaleFactor(0.85)
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: MirrorLayout.fieldHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: MirrorLayout.controlRadius))
        .disabled(disabled)
    }
}
