import AppKit
import SwiftUI

enum SunnyLeafVideoKind {
    case fallingLeaves
    case windowShadows

    var resourceName: String {
        switch self {
        case .fallingLeaves: "leaves"
        case .windowShadows: "window-leaves"
        }
    }

    var opacity: Double {
        switch self {
        case .fallingLeaves: 1
        case .windowShadows: 0.60
        }
    }
}

struct SunnyLeafBackdropPlan: Equatable {
    let showsPoster: Bool
    let showsVideo: Bool
    let showsFallback: Bool

    static func make(animated: Bool, hasVideo: Bool, hasPoster: Bool) -> Self {
        Self(
            showsPoster: hasPoster,
            showsVideo: animated && hasVideo,
            showsFallback: !hasPoster
        )
    }
}

struct SunnyLeafVideoBackdrop: View {
    let kind: SunnyLeafVideoKind
    let animated: Bool
    let fallbackTime: TimeInterval

    var body: some View {
        let videoURL = AtmosphereVideoAssets.videoURL(named: kind.resourceName, extension: "mp4")
        let poster = AtmosphereVideoAssets.poster(named: kind.resourceName)
        let plan = SunnyLeafBackdropPlan.make(
            animated: animated,
            hasVideo: videoURL != nil,
            hasPoster: poster != nil
        )

        ZStack {
            if plan.showsPoster, let poster {
                Image(nsImage: poster)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else if plan.showsFallback {
                SunnyAtmosphereFallback(time: fallbackTime)
            }

            if plan.showsVideo, let videoURL {
                LoopingAtmosphereVideo(url: videoURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .blendMode(.multiply)
        .opacity(kind.opacity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
