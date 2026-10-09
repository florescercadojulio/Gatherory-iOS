import SwiftUI

enum LaunchExperienceTiming {
    static let standardMilliseconds = 1_400
    static let reducedMotionMilliseconds = 300
    static let exitAnimationSeconds = 0.22
}

struct GatheroryLaunchContainer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            AppRootView()

            if isShowingSplash {
                GatheroryAnimatedSplash(reduceMotion: reduceMotion)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            guard isShowingSplash else { return }

            let milliseconds = reduceMotion
                ? LaunchExperienceTiming.reducedMotionMilliseconds
                : LaunchExperienceTiming.standardMilliseconds
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: LaunchExperienceTiming.exitAnimationSeconds)) {
                isShowingSplash = false
            }
        }
    }
}

private struct GatheroryAnimatedSplash: View {
    @State private var animationTrigger = false
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            if reduceMotion {
                launchMark
            } else {
                animatedLaunchMark
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gatherory")
    }

    private var launchMark: some View {
        Image("GatheroryLaunchMark")
            .resizable()
            .scaledToFit()
            .frame(width: 184, height: 184)
    }

    private var animatedLaunchMark: some View {
        let accentColor = AppTheme.ColorToken.accent

        return launchMark
            .keyframeAnimator(
                initialValue: LaunchMarkMotion.initial,
                trigger: animationTrigger
            ) { content, value in
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(value.glowOpacity))
                        .frame(width: 146, height: 146)
                        .scaleEffect(value.glowScale)
                        .blur(radius: 30)

                    ZStack {
                        content

                        LinearGradient(
                            colors: [.clear, .white.opacity(0.72), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: 54, height: 230)
                        .rotationEffect(.degrees(20))
                        .offset(x: value.shineOffset)
                        .blendMode(.screen)
                        .mask { content }
                    }
                    .opacity(value.opacity)
                    .scaleEffect(value.scale)
                    .rotationEffect(.degrees(value.rotation))
                    .offset(y: value.offsetY)
                }
                .frame(width: 220, height: 220)
                .compositingGroup()
            } keyframes: { initial in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.2)
                }

                KeyframeTrack(\.scale) {
                    SpringKeyframe(
                        1.04,
                        duration: 0.55,
                        spring: Spring(duration: 0.55, bounce: 0.12)
                    )
                    CubicKeyframe(1, duration: 0.16)
                }

                KeyframeTrack(\.rotation) {
                    SpringKeyframe(
                        0,
                        duration: 0.65,
                        spring: Spring(duration: 0.65, bounce: 0.08)
                    )
                }

                KeyframeTrack(\.offsetY) {
                    SpringKeyframe(
                        0,
                        duration: 0.55,
                        spring: Spring(duration: 0.55, bounce: 0.08)
                    )
                }

                KeyframeTrack(\.glowScale) {
                    CubicKeyframe(1.18, duration: 0.5)
                    CubicKeyframe(1, duration: 0.2)
                }

                KeyframeTrack(\.glowOpacity) {
                    LinearKeyframe(0.14, duration: 0.22)
                    CubicKeyframe(0.07, duration: 0.48)
                }

                KeyframeTrack(\.shineOffset) {
                    LinearKeyframe(initial.shineOffset, duration: 0.32)
                    CubicKeyframe(190, duration: 0.52)
                }
            }
            .accessibilityHidden(true)
            .task {
                animationTrigger.toggle()
            }
    }
}

private struct LaunchMarkMotion {
    var opacity: Double
    var scale: CGFloat
    var rotation: Double
    var offsetY: CGFloat
    var glowScale: CGFloat
    var glowOpacity: Double
    var shineOffset: CGFloat

    static let initial = LaunchMarkMotion(
        opacity: 0,
        scale: 0.74,
        rotation: -14,
        offsetY: 18,
        glowScale: 0.72,
        glowOpacity: 0,
        shineOffset: -190
    )
}
