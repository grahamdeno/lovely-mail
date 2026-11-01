import SwiftUI

/// Swipeable lens cards above the reel. Tap one to filter the feed; tap × to clear.
struct LensCarousel: View {
    @Environment(FeedStore.self) private var store

    static let cardWidth: CGFloat = 220
    static let cardHeight: CGFloat = 120

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: RM.Space.s) {
                    ForEach(Lens.allCases) { lens in
                        LensCard(lens: lens, selected: store.lens == lens) {
                            withAnimation(.snappy) {
                                store.lens = store.lens == lens ? nil : lens
                                proxy.scrollTo(lens.id, anchor: .leading)
                            }
                        }
                        .id(lens.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, RM.Space.l)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
        .frame(height: Self.cardHeight)
    }
}

struct LensCard: View {
    @Environment(FeedStore.self) private var store
    let lens: Lens
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: lens.symbol).font(.system(size: 13, weight: .semibold))
                    Text(lens.title).font(RM.Typo.caption)
                    Spacer()
                    if selected {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .accessibilityLabel("Clear lens")
                    }
                }
                .foregroundStyle(selected ? RM.Palette.ink : RM.Palette.secondary)
                content
                Spacer(minLength: 0)
            }
            .padding(RM.Space.m)
            .frame(width: LensCarousel.cardWidth, height: LensCarousel.cardHeight, alignment: .topLeading)
            .background(selected ? Color.white : RM.Palette.surface)
            .rmCorner(RM.Radius.card)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var primary: Color { selected ? RM.Palette.ink : .white }

    @ViewBuilder private var content: some View {
        let posts = store.posts(for: lens)
        switch lens {
        case .brief:
            let waiting = store.needsReplyPosts
            let people = Set(waiting.map(\.email.from.id)).count
            Text("\(waiting.count) emails need you, from \(people) people")
                .font(RM.Typo.title).foregroundStyle(primary).lineLimit(2)
            if let next = store.posts(for: .comingUp).first, let date = next.summary.dates.first {
                Text("Next: \(date) · \(next.summary.headline)")
                    .font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary).lineLimit(1)
            }
        case .needsYou:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(posts.count)")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(selected ? RM.Palette.violetOnLight : RM.Palette.violet)
                Text("waiting on you").font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
            }
            Text(posts.prefix(3).map(\.email.from.firstName).joined(separator: ", "))
                .font(RM.Typo.caption).foregroundStyle(primary).lineLimit(1)
        case .comingUp:
            ForEach(posts.prefix(3)) { post in
                HStack(spacing: 6) {
                    Text(post.summary.dates.first ?? "").font(RM.Typo.micro).foregroundStyle(primary)
                        .frame(width: 44, alignment: .leading)
                    Text(post.summary.headline).font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary).lineLimit(1)
                }
            }
        case .people:
            HStack(spacing: -6) {
                ForEach(store.people.prefix(5)) { AvatarView(person: $0, size: 32) }
            }
            Text("\(store.people.count) people wrote to you").font(RM.Typo.caption).foregroundStyle(primary)
        case .money:
            Text("\(posts.count) receipts and bills").font(RM.Typo.title).foregroundStyle(primary)
            Text("Amounts stay hidden until you open them").font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary).lineLimit(2)
        case .catchUp:
            Text("\(posts.count) to read later").font(RM.Typo.title).foregroundStyle(primary)
            Text("Newsletters, kept out of your way").font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary).lineLimit(2)
        }
    }
}
