import SwiftUI

struct ArtistView: View {
    let artist: Artist
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var full: Artist?
    @State private var top: [Song] = []
    @State private var albums: [Album] = []
    @State private var loadError: String?
    @State private var showAllTop = false

    private var shown: Artist { full ?? artist }
    private var offline: Bool { app.prefs.data.offline || !app.network.isOnline }

    var body: some View {
        let local = app.library.songs(byArtist: artist.id)
        List {
            Section { header(local: local) }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if !local.isEmpty {
                Section {
                    ForEach(local) { SongRow(song: $0, queue: local, context: shown.name) }
                } header: { SectionLabel(text: "Downloaded") }
            }
            if !offline && !top.isEmpty {
                Section {
                    ForEach(showAllTop ? top : Array(top.prefix(5))) { SongRow(song: $0, queue: top, context: "\(shown.name) · Popular") }
                    if top.count > 5 {
                        Button(showAllTop ? "Show less" : "Show all \(top.count)") { withAnimation { showAllTop.toggle() } }
                            .font(.subheadline.weight(.semibold))
                    }
                } header: { SectionLabel(text: "Popular") }
            }
            if !offline && !albums.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(albums) { a in
                                NavigationLink(value: Route.album(a)) { AlbumTile(album: a, size: 130) }.buttonStyle(PressStyle())
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: { SectionLabel(text: "Discography") }
            }
            if !offline {
                Section {
                    NavigationLink(value: Route.artistMore(shown)) {
                        Label("Similar artists, shows & about", systemImage: "person.2.wave.2")
                    }
                }
            }
            if let loadError, local.isEmpty {
                Text(loadError).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Surface.background(look))
        .navigationTitle(shown.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func header(local: [Song]) -> some View {
        VStack(spacing: 10) {
            shown.picture(170).shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            Text(shown.name).font(.title.bold()).multilineTextAlignment(.center)
            if let fans = shown.fans { Text("\(Fmt.count(fans)) fans").font(.subheadline).foregroundStyle(.secondary) }
            let listened = app.stats.seconds(forArtist: artist.id)
            if listened > 0 {
                Label("You've listened \(Fmt.listening(listened))", systemImage: "headphones")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(look.accent)
            }
            HStack(spacing: 10) {
                let following = app.library.isFollowing(artist.id)
                PillButton(title: following ? "Following" : "Follow", icon: following ? "checkmark" : "plus") {
                    withAnimation(.spring(duration: 0.3)) { app.library.toggleFollow(shown) }
                }
                if !local.isEmpty {
                    PillButton(title: "Play", icon: "play.fill", prominent: true) { app.player.play(local, context: shown.name, shuffled: false) }
                    Button { app.player.play(local, context: shown.name, shuffled: true) } label: {
                        Image(systemName: "shuffle").frame(width: 40, height: 40).background(Color.secondary.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Shuffle")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func load() async {
        guard full == nil, !offline, artist.id > 0 else { return }
        do {
            async let a = Catalog.artist(artist.id)
            async let t = Catalog.topSongs(artistID: artist.id)
            async let al = Catalog.albums(artist: artist)
            let (fa, ft, fal) = try await (a, t, al)
            withAnimation(.easeOut(duration: 0.25)) {
                full = fa
                top = ft.map { s in var s = s; if s.artist.id == fa.id { s.artist = fa }; return s }
                albums = fal
            }
        } catch {
            loadError = "Couldn't load artist info. Your downloads are still here."
        }
    }
}

/// Similar artists, upcoming shows and bio. Extras ask before using mobile data.
struct ArtistMoreView: View {
    let artist: Artist
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var similar: [Artist] = []
    @State private var shows: [Concert]?
    @State private var showsError: String?
    @State private var bio: String?
    @State private var bioLoaded = false
    @State private var extrasAllowed = false

    private var mustAsk: Bool { app.network.onMobileData && app.prefs.data.askBeforeExtras && !extrasAllowed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !similar.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fans also like").font(.title2.bold()).padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(similar) { a in
                                    NavigationLink(value: Route.artist(a)) { ArtistCircle(artist: a, size: 84) }.buttonStyle(PressStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                        Button {
                            let p = app.playlists.createAuto(name: "Like \(artist.name)", rule: AutoRule(source: .similar, maxSongs: 40, artists: [artist]))
                            app.navigate(.playlist(p.id))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles").font(.title3).frame(width: 44, height: 44)
                                    .background(Color(hex: "#3730A3"), in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Make a \"Like \(artist.name)\" playlist").font(.subheadline.weight(.semibold))
                                    Text("Auto playlist of artists like this, updates itself").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus").foregroundStyle(look.accent)
                            }
                            .padding(12)
                            .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(14)))
                        }
                        .buttonStyle(PressStyle())
                        .padding(.horizontal)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Upcoming shows").font(.title2.bold())
                    gated { showsContent }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Text("About").font(.title2.bold())
                    gated {
                        if let bio {
                            Text(bio).font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                        } else {
                            Text(bioLoaded ? "No bio found." : "Loading…").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Surface.background(look))
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { similar = (try? await Catalog.related(artistID: artist.id, limit: 12)) ?? [] }
        .task(id: mustAsk) { if !mustAsk { await loadExtras() } }
    }

    @ViewBuilder
    private func gated<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if mustAsk {
            ZStack {
                content().blur(radius: 6).allowsHitTesting(false)
                VStack(spacing: 8) {
                    Text("You're on mobile data").font(.footnote)
                    Button("Load") { withAnimation { extrasAllowed = true } }.buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Surface.card(look), in: RoundedRectangle(cornerRadius: look.radius(14)))
        } else {
            content()
        }
    }

    @ViewBuilder private var showsContent: some View {
        if app.prefs.data.ticketmasterKey.isEmpty {
            Text("Add your free Ticketmaster key in Settings › Connections to see shows near \(app.prefs.data.concertCity.name).")
                .font(.footnote).foregroundStyle(.secondary)
        } else if let showsError {
            Text(showsError).font(.footnote).foregroundStyle(.secondary)
        } else if let shows {
            if shows.isEmpty {
                Text("No upcoming shows within \(app.prefs.data.concertRadiusKm) km of \(app.prefs.data.concertCity.name).").font(.footnote).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(shows) { c in
                        HStack(spacing: 14) {
                            VStack(spacing: 0) {
                                Text(c.date.map { $0.formatted(.dateTime.month(.abbreviated)) }?.uppercased() ?? "TBA").font(.caption2.weight(.heavy)).foregroundStyle(look.accent)
                                Text(c.date.map { $0.formatted(.dateTime.day()) } ?? "").font(.title3.weight(.heavy))
                            }
                            .frame(width: 48, height: 48)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.venue.isEmpty ? c.name : c.venue).font(.subheadline.weight(.semibold))
                                Text([c.city, c.distanceKm.map { "\(Int($0)) km away" }, c.priceFrom].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = c.url { Link("Tickets", destination: url).font(.caption.bold()).buttonStyle(.bordered) }
                        }
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func loadExtras() async {
        let p = app.prefs.data
        async let b = ArtistBio.fetch(artist.name)
        if !p.ticketmasterKey.isEmpty {
            do { shows = try await Concerts.upcoming(artistName: artist.name, key: p.ticketmasterKey, city: p.concertCity, radiusKm: p.concertRadiusKm) }
            catch { showsError = error.localizedDescription }
        }
        bio = await b
        bioLoaded = true
    }
}

struct AlbumView: View {
    let album: Album
    @Environment(AppModel.self) private var app
    @Environment(\.look) private var look
    @State private var full: Album?
    @State private var songs: [Song] = []
    @State private var error: String?

    private var shown: Album { full ?? album }

    var body: some View {
        let missing = songs.filter { !app.library.isDownloaded($0.id) }
        let downloaded = songs.filter { app.library.isDownloaded($0.id) }
        List {
            Section {
                VStack(spacing: 10) {
                    shown.cover(220).shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    Text(shown.title).font(.title2.bold()).multilineTextAlignment(.center)
                    if let a = shown.artist {
                        Button { app.navigate(.artist(a)) } label: { Text(a.name).font(.headline).foregroundStyle(look.accent) }
                            .buttonStyle(.plain)
                    }
                    Text([shown.recordType?.capitalized, shown.year, songs.isEmpty ? nil : "\(songs.count) songs", shown.genre]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if !missing.isEmpty {
                            PillButton(title: downloaded.isEmpty ? "Download album" : "Download \(missing.count) more", icon: "arrow.down.circle") {
                                app.library.downloadAll(missing)
                            }
                        }
                        if !downloaded.isEmpty {
                            PillButton(title: "Play", icon: "play.fill", prominent: true) { app.player.play(downloaded, context: shown.title, shuffled: false) }
                        }
                        if songs.count > 1 {
                            Button { app.sheet = .addToPlaylist(songs) } label: {
                                Image(systemName: "plus").frame(width: 40, height: 40).background(Color.secondary.opacity(0.18), in: Circle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Add album to playlist")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                    SongRow(song: s, queue: songs, context: shown.title, trackNumber: i + 1)
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Surface.background(look))
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard songs.isEmpty else { return }
            if app.prefs.data.offline || !app.network.isOnline {
                songs = app.library.songs.filter { $0.album?.id == album.id }
                return
            }
            do {
                let (a, s) = try await Catalog.album(album.id)
                withAnimation(.easeOut(duration: 0.25)) { full = a; songs = s }
            } catch {
                songs = app.library.songs.filter { $0.album?.id == album.id }
                self.error = songs.isEmpty ? error.localizedDescription : nil
            }
        }
    }
}
