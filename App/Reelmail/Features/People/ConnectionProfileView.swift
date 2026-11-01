import SwiftUI

/// A person's profile: who they are, what's waiting on you, and their recent posts.
struct ConnectionProfileView: View {
    @Environment(FeedStore.self) private var store
    @Environment(Router.self) private var router
    let person: Person

    var body: some View {
        let posts = store.posts(from: person)
        let waiting = posts.filter(\.summary.needsReply).count
        ScrollView {
            VStack(alignment: .leading, spacing: RM.Space.l) {
                HStack(spacing: RM.Space.l) {
                    AvatarView(person: person, size: 80, needsReply: waiting > 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name).font(RM.Typo.headline).foregroundStyle(.white)
                        Text(person.email).font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
                    }
                }
                HStack(spacing: RM.Space.s) {
                    StatTile(value: "\(posts.count)", label: "emails")
                    StatTile(value: "\(waiting)", label: "need you", highlight: waiting > 0)
                    StatTile(value: posts.first.map { $0.email.date.formatted(.relative(presentation: .named)) } ?? "–",
                             label: "last")
                }
                Button { router.open(.thread(person)) } label: {
                    Label("Open conversation", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RMButtonStyle(kind: .ghostLight))
                .background(Color.white)
                .rmCorner(RM.Radius.button)

                Text("Recent").font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary)
                ForEach(posts) { post in
                    PostRow(post: post).onTapGesture { router.open(.email(post.id)) }
                }
            }
            .padding(RM.Space.l)
        }
        .background(RM.Palette.sheet)
        .navigationTitle(person.firstName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(RM.Typo.title).foregroundStyle(highlight ? RM.Palette.violet : .white).lineLimit(1)
            Text(label).font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
        }
        .padding(RM.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RM.Palette.surface)
        .rmCorner(RM.Radius.card)
    }
}

/// List row: 8pt-radius thumbnail inside an 8pt-padded, 16pt-radius row.
struct PostRow: View {
    @Environment(FeedStore.self) private var store
    let post: Post

    var body: some View {
        let art = store.photos.art(for: post.summary, seed: post.id)
        HStack(spacing: RM.Space.m) {
            LinearGradient(colors: [art.top, art.bottom], startPoint: .top, endPoint: .bottom)
                .overlay { Image(systemName: art.symbol).foregroundStyle(.white) }
                .frame(width: 48, height: 48)
                .rmCorner(RM.Radius.thumb)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(post.email.from.name).font(RM.Typo.micro).foregroundStyle(RM.Palette.secondary)
                    if post.summary.needsReply {
                        Circle().fill(RM.Palette.violet).frame(width: 6, height: 6)
                            .accessibilityLabel("Needs reply")
                    }
                }
                Text(post.summary.headline).font(RM.Typo.callout.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text(post.summary.sensitive ? "Private details hidden" : post.summary.blurb)
                    .font(RM.Typo.caption).foregroundStyle(RM.Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RM.Palette.surface)
        .rmCorner(RM.Radius.nested(inner: RM.Radius.thumb, padding: 8))
        .contentShape(Rectangle())
    }
}
