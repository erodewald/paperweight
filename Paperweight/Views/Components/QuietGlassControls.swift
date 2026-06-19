import SwiftUI

// MARK: - Screen background

extension View {
    /// True-black screen background for the Quiet Glass language.
    func pwScreen() -> some View {
        self.background(PW.black.ignoresSafeArea())
    }
}

// MARK: - Section label

struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .pwSectionLabel()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }
}

// MARK: - Grouped card + rows

/// A `surface` rounded container that replaces an inset-grouped List section.
struct GroupedCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(PW.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(PW.hairline, lineWidth: 1))
    }
}

/// 1px in-card divider between rows.
struct CardDivider: View {
    var body: some View { Rectangle().fill(PW.separator).frame(height: 1) }
}

/// A tappable navigation row: optional leading icon · title · trailing value · chevron.
struct NavRow: View {
    var title: String
    var titleColor: Color = PW.textPrimary
    var systemImage: String? = nil
    var iconColor: Color = PW.sage
    var value: String? = nil
    var valueColor: Color = PW.textMuted
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
            }
            Text(title)
                .font(.grotesk(15))
                .foregroundStyle(titleColor)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.grotesk(13))
                    .foregroundStyle(valueColor)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PW.textFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Buttons

struct AccentButton: View {
    var title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .medium))
                }
                Text(title).font(.grotesk(15, weight: .semibold))
            }
            .foregroundStyle(PW.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(PW.sage)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: PW.sage.opacity(enabled ? 0.28 : 0), radius: 14)
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct GhostButton: View {
    var title: String
    var tint: Color = PW.textMuted
    var borderColor: Color = PW.hairline
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.grotesk(14))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented control

struct PWSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Text(option.label)
                    .font(.grotesk(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? PW.onAccent : PW.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? PW.sage : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option.value }
            }
        }
        .padding(4)
        .background(PW.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PW.hairline, lineWidth: 1))
    }
}

// MARK: - Toggle

struct PWToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(configuration.isOn ? PW.moss : Color.white.opacity(0.12))
                    .frame(width: 44, height: 26)
                    .shadow(color: configuration.isOn ? PW.sage.opacity(0.3) : .clear, radius: 8)
                Circle()
                    .fill(PW.textPrimary)
                    .frame(width: 20, height: 20)
                    .offset(x: configuration.isOn ? 9 : -9)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) { configuration.isOn.toggle() }
            }
        }
    }
}
