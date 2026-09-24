import AppKit
import SwiftUI

struct RestOverlayBackgroundView: View {
    let background: RestOverlayBackground
    let style: RestOverlayStyle
    let translucent: Bool

    private static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for background in RestOverlayBackground.allCases {
            if let name = background.imageName,
               let image = NSImage(named: name) ?? bundledImage(named: name) {
                result[name] = image
            }
        }
        return result
    }()

    var body: some View {
        Group {
            if let imageName = background.imageName,
               let image = Self.images[imageName] {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay(style.imageOverlay)
                }
            } else {
                style.solidBackground(translucent: translucent)
            }
        }
        .ignoresSafeArea()
    }

    private static func bundledImage(named name: String) -> NSImage? {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle.main
        #endif

        guard let url = bundle.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Backgrounds"
        ) ?? bundle.url(forResource: name, withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

struct RestOverlayActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let style: RestOverlayStyle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(style.buttonText)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? style.buttonPressedBackground : style.buttonBackground)
                    .shadow(color: style.buttonShadow, radius: 8, y: 2)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RestOverlayStyle {
    let background: RestOverlayBackground
    let colorScheme: ColorScheme

    func solidBackground(translucent: Bool) -> Color {
        if background == .linen {
            return Color(red: 0.86, green: 0.83, blue: 0.76)
        }
        let base = colorScheme == .dark
            ? Color(red: 0.075, green: 0.082, blue: 0.09)
            : Color(red: 0.88, green: 0.89, blue: 0.90)

        return translucent ? base.opacity(colorScheme == .dark ? 0.88 : 0.90) : base
    }

    var primaryText: Color {
        switch background {
        case .solid:
            colorScheme == .dark ? .white : Color(red: 0.15, green: 0.16, blue: 0.17)
        case .linen:
            Color(red: 0.18, green: 0.17, blue: 0.15)
        case .moon:
            .white
        case .sun:
            Color(red: 0.18, green: 0.17, blue: 0.15)
        }
    }

    var buttonBackground: Color {
        switch background {
        case .solid:
            colorScheme == .dark
                ? Color.white.opacity(0.18)
                : Color.white.opacity(0.72)
        case .linen:
            Color(red: 0.96, green: 0.95, blue: 0.91).opacity(0.92)
        case .moon:
            Color.white.opacity(0.24)
        case .sun:
            Color(red: 0.96, green: 0.96, blue: 0.93).opacity(0.94)
        }
    }

    var buttonPressedBackground: Color {
        switch background {
        case .solid:
            colorScheme == .dark
                ? Color.white.opacity(0.24)
                : Color.white.opacity(0.86)
        case .linen:
            Color(red: 0.92, green: 0.90, blue: 0.84).opacity(0.96)
        case .moon:
            Color.white.opacity(0.32)
        case .sun:
            Color(red: 0.90, green: 0.90, blue: 0.87).opacity(0.96)
        }
    }

    var buttonText: Color {
        switch background {
        case .solid:
            colorScheme == .dark ? .white.opacity(0.94) : Color(red: 0.16, green: 0.17, blue: 0.18)
        case .linen:
            Color(red: 0.18, green: 0.17, blue: 0.15)
        case .moon:
            Color.white.opacity(0.94)
        case .sun:
            Color(red: 0.18, green: 0.17, blue: 0.15)
        }
    }

    var buttonShadow: Color {
        switch background {
        case .solid:
            colorScheme == .dark ? Color.black.opacity(0.18) : Color.black.opacity(0.10)
        case .linen:
            Color.black.opacity(0.09)
        case .moon:
            Color.black.opacity(0.34)
        case .sun:
            Color.black.opacity(0.08)
        }
    }

    var imageOverlay: Color {
        switch background {
        case .solid, .linen:
            .clear
        case .moon:
            Color.black.opacity(0.18)
        case .sun:
            Color.white.opacity(0.08)
        }
    }

    var textShadow: Color {
        switch background {
        case .solid:
            .clear
        case .linen:
            Color.white.opacity(0.30)
        case .moon:
            Color.black.opacity(0.52)
        case .sun:
            Color.white.opacity(0.34)
        }
    }
}
