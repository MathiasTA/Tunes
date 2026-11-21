import Foundation

/// Music metadata, artwork and 30-second previews from Deezer's free public API (no key needed).
enum Catalog {
    struct SearchResults {
        var artists: [Artist] = []
        var songs: [Song] = []
        var albums: [Album] = []
        var isEmpty: Bool { artists.isEmpty && songs.isEmpty && albums.isEmpty }
    }

    struct PlaylistInfo: Identifiable, Hashable {
        let id: Int
        let title: String
        let owner: String
        let pictureURL: URL?
        let trackCount: Int?
    }

    struct Genre: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    enum CatalogError: LocalizedError {
        case http(Int), api(String)
        var errorDescription: String? {
            switch self {
            case .http(let code): "Couldn't reach the music catalog (error \(code))."
            case .api(let msg): "Music catalog: \(msg)"
            }
        }
    }

    // MARK: Search

    static func search(_ query: String) async throws -> SearchResults {
        async let artists: DZList<DZArtist> = get("search/artist", ["q": query, "limit": "10"])
        async let songs: DZList<DZTrack> = get("search/track", ["q": query, "limit": "25"])
        async let albums: DZList<DZAlbum> = get("search/album", ["q": query, "limit": "12"])
        let (a, s, al) = try await (artists, songs, albums)
        return SearchResults(artists: a.items.map(\.model), songs: s.items.map { $0.model() }, albums: al.items.map { $0.model() })
    }

    static func searchArtists(_ query: String, limit: Int = 15) async throws -> [Artist] {
        let l: DZList<DZArtist> = try await get("search/artist", ["q": query, "limit": "\(limit)"])
        return l.items.map(\.model)
    }

    static func searchSongs(_ query: String, limit: Int = 15) async throws -> [Song] {
        let l: DZList<DZTrack> = try await get("search/track", ["q": query, "limit": "\(limit)"])
        return l.items.map { $0.model() }
    }

    static func searchAlbums(_ query: String, limit: Int = 12) async throws -> [Album] {
        let l: DZList<DZAlbum> = try await get("search/album", ["q": query, "limit": "\(limit)"])
        return l.items.map { $0.model() }
    }

    static func searchPlaylists(_ query: String, limit: Int = 10) async throws -> [PlaylistInfo] {
        let l: DZList<DZPlaylist> = try await get("search/playlist", ["q": query, "limit": "\(limit)"])
        return l.items.map(\.info)
    }

    // MARK: Artists, albums, tracks

    static func artist(_ id: Int) async throws -> Artist {
        let dz: DZArtist = try await get("artist/\(id)")
        return dz.model
    }

    static func topSongs(artistID: Int, limit: Int = 20) async throws -> [Song] {
        let l: DZList<DZTrack> = try await get("artist/\(artistID)/top", ["limit": "\(limit)"])
        return l.items.map { $0.model() }
    }

    static func albums(artist: Artist, limit: Int = 100) async throws -> [Album] {
        let l: DZList<DZAlbum> = try await get("artist/\(artist.id)/albums", ["limit": "\(limit)"])
        return l.items.map { $0.model(fallbackArtist: artist) }.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }

    static func related(artistID: Int, limit: Int = 12) async throws -> [Artist] {
        let l: DZList<DZArtist> = try await get("artist/\(artistID)/related", ["limit": "\(limit)"])
        return l.items.map(\.model)
    }

    static func album(_ id: Int) async throws -> (Album, [Song]) {
        let dz: DZAlbum = try await get("album/\(id)")
        let album = dz.model()
        return (album, (dz.tracks?.items ?? []).map { $0.model(fallbackAlbum: album) })
    }

    static func track(_ id: Int) async throws -> Song {
        let dz: DZTrack = try await get("track/\(id)")
        return dz.model()
    }

    // MARK: Charts & editorial

    static func chartTracks(genreID: Int = 0, limit: Int = 50) async throws -> [Song] {
        let l: DZList<DZTrack> = try await get("chart/\(genreID)/tracks", ["limit": "\(limit)"])
        return l.items.map { $0.model() }
    }

    static func chartPlaylists(limit: Int = 30) async throws -> [PlaylistInfo] {
        let l: DZList<DZPlaylist> = try await get("chart/0/playlists", ["limit": "\(limit)"])
        return l.items.map(\.info)
    }

    static func chartArtists(limit: Int = 20) async throws -> [Artist] {
        let l: DZList<DZArtist> = try await get("chart/0/artists", ["limit": "\(limit)"])
        return l.items.map(\.model)
    }

    static func newReleases(limit: Int = 20) async throws -> [Album] {
        let l: DZList<DZAlbum> = try await get("editorial/0/releases", ["limit": "\(limit)"])
        return l.items.map { $0.model() }
    }

    static func genres() async throws -> [Genre] {
        let l: DZList<DZGenre> = try await get("genre")
        return l.items.filter { $0.id != 0 }.map { Genre(id: $0.id, name: $0.name) }
    }

    static func playlistTracks(_ id: Int, limit: Int = 100) async throws -> [Song] {
        let l: DZList<DZTrack> = try await get("playlist/\(id)/tracks", ["limit": "\(limit)"])
        return l.items.map { $0.model() }
    }

    // MARK: Networking

    private static let limiter = RateLimiter(perSecond: 8)

    private static func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(string: "https://api.deezer.com/\(path)")!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = comps.url else { throw CatalogError.api("Bad request") }
        await limiter.wait()
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.http(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let wrap = try? decoder.decode(DZErrorWrap.self, from: data), let err = wrap.error {
            // Deezer's quota error: wait and try once more.
            if err.code == 4 {
                try await Task.sleep(for: .seconds(2))
                return try await get(path, query)
            }
            throw CatalogError.api(err.message ?? "Unknown error")
        }
        return try decoder.decode(T.self, from: data)
    }
}

/// Keeps requests under a per-second budget.
actor RateLimiter {
    private let interval: Double
    private var next = Date.distantPast

    init(perSecond: Double) { interval = 1 / perSecond }

    func wait() async {
        let now = Date()
        let start = max(now, next)
        next = start.addingTimeInterval(interval)
        let delay = start.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
    }
}

// MARK: - Deezer JSON shapes

private func url(_ s: String?) -> URL? {
    guard let s, !s.isEmpty else { return nil }
    return URL(string: s)
}

private struct DZList<T: Decodable>: Decodable {
    let data: [T]?
    var items: [T] { data ?? [] }
}

private struct DZErrorWrap: Decodable { let error: DZError? }
private struct DZError: Decodable { let message: String?; let code: Int? }
private struct DZGenre: Decodable { let id: Int; let name: String }
private struct DZGenreList: Decodable { let data: [DZGenre]? }
private struct DZUser: Decodable { let name: String? }

private struct DZPlaylist: Decodable {
    let id: Int
    let title: String
    let pictureBig: String?
    let pictureMedium: String?
    let nbTracks: Int?
    let user: DZUser?
    var info: Catalog.PlaylistInfo {
        Catalog.PlaylistInfo(id: id, title: title, owner: user?.name ?? "", pictureURL: url(pictureBig ?? pictureMedium), trackCount: nbTracks)
    }
}

private struct DZArtist: Decodable {
    let id: Int
    let name: String
    let pictureBig: String?
    let pictureMedium: String?
    let nbFan: Int?
    var model: Artist { Artist(id: id, name: name, pictureURL: url(pictureBig ?? pictureMedium), fans: nbFan) }
}

private struct DZContributor: Decodable {
    let id: Int
    let name: String
    let pictureBig: String?
    let role: String?
}

private struct DZAlbum: Decodable {
    let id: Int
    let title: String
    let coverBig: String?
    let coverMedium: String?
    let releaseDate: String?
    let nbTracks: Int?
    let recordType: String?
    let artist: DZArtist?
    let tracks: DZList<DZTrack>?
    let genres: DZGenreList?

    func model(fallbackArtist: Artist? = nil) -> Album {
        Album(id: id, title: title, coverURL: url(coverBig ?? coverMedium), artist: artist?.model ?? fallbackArtist,
              releaseDate: releaseDate, trackCount: nbTracks, recordType: recordType, genre: genres?.data?.first?.name)
    }
}

private struct DZTrack: Decodable {
    let id: Int
    let title: String
    let duration: Int?
    let preview: String?
    let explicitLyrics: Bool?
    let rank: Int?
    let artist: DZArtist
    let album: DZAlbum?
    let contributors: [DZContributor]?

    func model(fallbackAlbum: Album? = nil) -> Song {
        var main = artist.model
        if main.pictureURL == nil, let a = fallbackAlbum?.artist, a.id == main.id { main.pictureURL = a.pictureURL }
        let feats = (contributors ?? []).filter { $0.id != main.id }.map { Artist(id: $0.id, name: $0.name, pictureURL: url($0.pictureBig)) }
        return Song(id: id, title: title, artist: main, featured: feats,
                    album: album?.model(fallbackArtist: main) ?? fallbackAlbum,
                    duration: Double(duration ?? 0), previewURL: url(preview),
                    explicit: explicitLyrics ?? false, rank: rank)
    }
}
