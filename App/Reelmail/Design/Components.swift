import SwiftUI

/// Rounded-square avatar with initials. Optional violet ring for "needs reply".
struct AvatarView: View {
    let person: Person
    var size: CGFloat = 40
    var needsReply: Bool = false

    private let ringGap: CGFloat = 3

    var body: some View {
        let radius = RM.Radius.avatar(size: size)
        Text(person.initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(person.color)
            .rmCorner(radius)
            .padding(needsReply ? ringGap : 0)
            .overlay {
                if needsReply {
                    RoundedRectangle(cornerRadius: RM.Radius.avatarRing(size: size, gap: ringGap), style: .continuous)
                        .strokeBorder(RM.Palette.violet, lineWidth: 2)
                }
            }
            .accessibilityLabel(person.name + (needsReply ? ", needs your reply" : ""))
    }
}

/// "Needs reply" tag. On light: white pill, violet dot, violet text. On dark: violet text.
struct NeedsReplyTag: View {
    var onLight: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(onLight ? RM.Palette.violetOnLight : RM.Palette.violet).frame(width: 6, height: 6)
            Text("Needs reply")
                .font(RM.Typo.micro)
                .foregroundStyle(onLight ? RM.Palette.violetOnLight : RM.Palette.violet)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(onLight ? Color.white : RM.Palette.surface)
        .rmCorner(RM.Radius.button)
    }
}

enum RMButtonStyleKind { case primary, ghostLight, ghostDark }

struct RMButtonStyle: ButtonStyle {
    var kind: RMButtonStyleKind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(foreground)
            .background(background)
            .rmCorner(RM.Radius.button)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .ghostLight: return RM.Palette.ink
        case .ghostDark: return .white
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return RM.Palette.ink
        case .ghostLight: return RM.Palette.ink.opacity(0.07)
        case .ghostDark: return RM.Palette.surface
        }
    }
}

/// White header with a large title, then the graphite sheet with 24pt top corners.
struct ScreenScaffold<Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(RM.Typo.display()).foregroundStyle(RM.Palette.ink)
                Spacer()
                trailing()
            }
            .padding(.horizontal, RM.Space.l)
            .padding(.top, RM.Space.s)
            .padding(.bottom, RM.Space.l)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(RM.Palette.sheet)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: RM.Radius.sheet,
                                                  topTrailingRadius: RM.Radius.sheet,
                                                  style: .continuous))
                .ignoresSafeArea(edges: .bottom)
        }
        .background(RM.Palette.header)
    }
}

extension ScreenScaffold where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = { EmptyView() }
        self.content = content
    }
}

/// Square icon button for the white header (bell, search).
struct HeaderIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void
    var size: CGFloat = 40

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RM.Palette.ink)
                .frame(width: size, height: size)
                .background(Color.white)
                .rmCorner(RM.Radius.avatar(size: size))
        }
        .accessibilityLabel(label)
    }
}
