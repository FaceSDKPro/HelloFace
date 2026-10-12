import SwiftUI

struct DemoCameraButton: View {
    let icon: String
    let label: String
    var onDark = false
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var symbolSize = 20

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: symbolSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: max(44, symbolSize + 24), height: max(44, symbolSize + 24))
                .foregroundStyle(onDark ? Color.white : Color.primary)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(
                        onDark ? Color.white.opacity(0.2) : Color.black.opacity(0.08),
                        lineWidth: 0.5
                    )
                }
                .contentShape(Circle())
        }
        .buttonStyle(CameraIconButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct CameraIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
