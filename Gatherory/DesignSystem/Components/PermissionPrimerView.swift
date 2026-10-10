import SwiftUI

enum PermissionPrimerArtworkKind {
    case notifications
    case location
    case music
    case contacts
}

/// A focused explanation shown immediately before a system permission request.
/// Keep each primer contextual: one benefit, one primary action, and a way to defer.
struct PermissionPrimerView: View {
    let artwork: PermissionPrimerArtworkKind
    let title: String
    let message: String
    var primaryTitle = "Continue"
    var secondaryTitle = "Not Now"
    var isWorking = false
    let onContinue: () -> Void
    let onNotNow: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    PermissionPrimerArtwork(kind: artwork)
                        .frame(maxWidth: .infinity)
                        .frame(height: artworkHeight(for: proxy.size.height))
                        .background(Color.black)

                    VStack(spacing: AppTheme.Spacing.section) {
                        VStack(spacing: AppTheme.Spacing.standard) {
                            Text(title)
                                .font(AppTheme.Typography.display)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(message)
                                .font(.title3)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: AppTheme.Spacing.standard)

                        VStack(spacing: AppTheme.Spacing.compact) {
                            Button(action: onContinue) {
                                Group {
                                    if isWorking {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text(primaryTitle)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isWorking)

                            Button(secondaryTitle, action: onNotNow)
                                .buttonStyle(.plain)
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
                                .disabled(isWorking)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.spacious)
                    .padding(.top, AppTheme.Spacing.section)
                    .padding(.bottom, AppTheme.Spacing.spacious)
                    .frame(maxWidth: .infinity, minHeight: contentHeight(for: proxy.size.height))
                    .background(AppTheme.ColorToken.surface)
                }
                .frame(maxWidth: 680)
                .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .stroke(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
                }
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.compact)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.black.ignoresSafeArea())
        .tint(AppTheme.ColorToken.accent)
    }

    private func artworkHeight(for availableHeight: CGFloat) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 250
        }
        return min(max(availableHeight * 0.45, 300), 430)
    }

    private func contentHeight(for availableHeight: CGFloat) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 420
        }
        return max(availableHeight * 0.53, 390)
    }
}

private struct PermissionPrimerArtwork: View {
    let kind: PermissionPrimerArtworkKind

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [accent.opacity(0.32), Color.black.opacity(0.96)],
                    center: .center,
                    startRadius: 12,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.7
                )

                devicePreview
                    .frame(
                        width: min(proxy.size.width * 0.66, 310),
                        height: min(proxy.size.height * 0.78, 330)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private var accent: Color {
        switch kind {
        case .notifications: AppTheme.ColorToken.accent
        case .location: .green
        case .music: .purple
        case .contacts: AppTheme.ColorToken.accent
        }
    }

    @ViewBuilder
    private var devicePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Color.white.opacity(0.09))
                .overlay {
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

            switch kind {
            case .notifications:
                notificationsArtwork
            case .location:
                locationArtwork
            case .music:
                musicArtwork
            case .contacts:
                contactsArtwork
            }

            VStack {
                Spacer()
                Capsule()
                    .fill(Color.white.opacity(0.62))
                    .frame(width: 88, height: 5)
                    .padding(.bottom, 14)
            }
        }
        .shadow(color: accent.opacity(0.24), radius: 34, y: 14)
    }

    private var notificationsArtwork: some View {
        VStack(spacing: 22) {
            Spacer()

            HStack(spacing: 12) {
                Image("GatheroryLaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(Color.white.opacity(0.46)).frame(width: 92, height: 9)
                    Capsule().fill(Color.white.opacity(0.28)).frame(maxWidth: .infinity).frame(height: 8)
                    Capsule().fill(Color.white.opacity(0.28)).frame(width: 136, height: 8)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 22)

            HStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "flashlight.off.fill").foregroundStyle(.white.opacity(0.62)))
                Spacer()
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "camera.fill").foregroundStyle(.white.opacity(0.62)))
            }
            .padding(.horizontal, 34)

            Spacer()
        }
    }

    private var locationArtwork: some View {
        ZStack {
            Canvas { context, size in
                let lineColor = Color.white.opacity(0.13)
                for index in 1..<5 {
                    let x = size.width * CGFloat(index) / 5
                    var vertical = Path()
                    vertical.move(to: CGPoint(x: x, y: 0))
                    vertical.addLine(to: CGPoint(x: x - 34, y: size.height))
                    context.stroke(vertical, with: .color(lineColor), lineWidth: 12)
                }
                for index in 1..<6 {
                    let y = size.height * CGFloat(index) / 6
                    var horizontal = Path()
                    horizontal.move(to: CGPoint(x: 0, y: y))
                    horizontal.addLine(to: CGPoint(x: size.width, y: y + 18))
                    context.stroke(horizontal, with: .color(lineColor), lineWidth: 9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))

            Circle()
                .fill(.green.opacity(0.18))
                .frame(width: 150, height: 150)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 78, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .shadow(color: .black.opacity(0.24), radius: 10, y: 8)

            VStack {
                Spacer()
                Label("Event location", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 34)
            }
        }
    }

    private var musicArtwork: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.purple, AppTheme.ColorToken.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 154, height: 154)

                Image(systemName: "music.note")
                    .font(.system(size: 66, weight: .medium))
                    .foregroundStyle(.white)
            }
            .shadow(color: .purple.opacity(0.35), radius: 24, y: 12)

            HStack(alignment: .center, spacing: 5) {
                ForEach([16, 30, 46, 26, 54, 38, 22, 42, 18], id: \.self) { height in
                    Capsule()
                        .fill(Color.white.opacity(0.62))
                        .frame(width: 5, height: CGFloat(height))
                }
            }

            Spacer()
        }
    }

    private var contactsArtwork: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 28)

            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 92, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, AppTheme.ColorToken.accent)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, AppTheme.ColorToken.accent)
                    .background(Color.black, in: Circle())
                    .offset(x: 4, y: 2)
            }

            VStack(spacing: 0) {
                contactRow(initials: "AJ", width: 126)
                Divider().overlay(Color.white.opacity(0.12))
                contactRow(initials: "M", width: 154)
                Divider().overlay(Color.white.opacity(0.12))
                contactRow(initials: "SK", width: 108)
            }
            .padding(.horizontal, 18)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 22)

            Spacer(minLength: 26)
        }
    }

    private func contactRow(initials: String, width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AppTheme.ColorToken.accent.opacity(0.82), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Capsule()
                    .fill(Color.white.opacity(0.52))
                    .frame(width: width, height: 8)
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: width * 0.68, height: 7)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}

#Preview("Notification Primer") {
    PermissionPrimerView(
        artwork: .notifications,
        title: "Stay in step with your plans.",
        message: "Get reminders when an event changes or someone needs your decision.",
        onContinue: { },
        onNotNow: { }
    )
}

#Preview("Location Primer") {
    PermissionPrimerView(
        artwork: .location,
        title: "Set the place in one tap.",
        message: "Use your location once to find the event address. Gatherory doesn’t track where you go.",
        onContinue: { },
        onNotNow: { }
    )
}

#Preview("Music Primer") {
    PermissionPrimerView(
        artwork: .music,
        title: "Build the soundtrack together.",
        message: "Connect Apple Music to search for songs and add them to this event. Gatherory only saves the tracks you choose.",
        onContinue: { },
        onNotNow: { }
    )
}

#Preview("Contacts Primer") {
    PermissionPrimerView(
        artwork: .contacts,
        title: "Bring your people together.",
        message: "Choose contacts to invite as hosts, collaborators, or guests. Gatherory only uses the people you select.",
        onContinue: { },
        onNotNow: { }
    )
}

private struct PermissionPrimerPreviewGallery: View {
    var body: some View {
        TabView {
            PermissionPrimerView(
                artwork: .notifications,
                title: "Stay in step with your plans.",
                message: "Get reminders when an event changes or someone needs your decision.",
                onContinue: { },
                onNotNow: { }
            )

            PermissionPrimerView(
                artwork: .location,
                title: "Set the place in one tap.",
                message: "Use your location once to find the event address. Gatherory doesn’t track where you go.",
                onContinue: { },
                onNotNow: { }
            )

            PermissionPrimerView(
                artwork: .music,
                title: "Build the soundtrack together.",
                message: "Connect Apple Music to search for songs and add them to this event. Gatherory only saves the tracks you choose.",
                onContinue: { },
                onNotNow: { }
            )

            PermissionPrimerView(
                artwork: .contacts,
                title: "Bring your people together.",
                message: "Choose contacts to invite as hosts, collaborators, or guests. Gatherory only uses the people you select.",
                onContinue: { },
                onNotNow: { }
            )
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }
}

#Preview {
    PermissionPrimerPreviewGallery()
}
