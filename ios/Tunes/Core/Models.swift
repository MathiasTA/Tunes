import Foundation

// IDs are Deezer catalog IDs. Songs imported from files that aren't linked to a catalog
// song get a negative ID, so they can never collide with catalog songs.

struct Artist: Codable, Hashable, Identifiable {
    let id: Int
    var name: String
    var pictureURL: URL?
    var fans: Int?

    init(id: Int, name: String, pictureURL: URL? = nil, fans: Int? = nil) {
        self.id = id
        self.name = name
        self.pictureURL = pictureURL
        self.fans = fans
    }

    var localPictureURL: URL { Paths.artistImage(id) }
}

struct Album: Codable, Hashable, Identifiable {
    let id: Int
    var title: String
    var coverURL: URL?
    var artist: Artist?
    var releaseDate: String?
    var trackCount: Int?
    var recordType: String?
    var genre: String?

    init(id: Int, title: String, coverURL: URL? = nil, artist: Artist? = nil, releaseDate: String? = nil,
         trackCount: Int? = nil, recordType: String? = nil, genre: String? = nil) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.artist = artist
        self.releaseDate = releaseDate
        self.trackCount = trackCount
        self.recordType = recordType
        self.genre = genre
    }

    var year: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }

    var releaseDay: Date? {
        guard let releaseDate else { return nil }
        return Fmt.isoDay.date(from: releaseDate)
    }
}

struct Song: Codable, Hashable, Identifiable {
    let id: Int
    var title: String
    var artist: Artist
    var featured: [Artist]
    var album: Album?
    var duration: Double
    var previewURL: URL?
    var explicit: Bool
    var rank: Int?

    init(id: Int, title: String, artist: Artist, featured: [Artist] = [], album: Album? = nil,
         duration: Double, previewURL: URL? = nil, explicit: Bool = false, rank: Int? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.featured = featured
        self.album = album
        self.duration = duration
        self.previewURL = previewURL
        self.explicit = explicit
        self.rank = rank
    }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, featured, album, duration, previewURL, explicit, rank
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decode(Artist.self, forKey: .artist)
        featured = (try? c.decodeIfPresent([Artist].self, forKey: .featured)) ?? []
        album = try? c.decodeIfPresent(Album.self, forKey: .album)
        duration = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? 0
        previewURL = try? c.decodeIfPresent(URL.self, forKey: .previewURL)
        explicit = (try? c.decodeIfPresent(Bool.self, forKey: .explicit)) ?? false
        rank = try? c.decodeIfPresent(Int.self, forKey: .rank)
    }

    var allArtists: [Artist] { [artist] + featured.filter { $0.id != artist.id } }
    var artistLine: String { allArtists.map(\.name).joined(separator: ", ") }
    var artworkURL: URL? { album?.coverURL ?? artist.pictureURL }
    var localArtworkURL: URL { Paths.songArtwork(id) }
    var isLocalOnly: Bool { id < 0 }
}

/// A song that lives on the phone (downloaded from YouTube or imported from a file).
struct LibraryEntry: Codable, Hashable, Identifiable {
    enum Source: Codable, Hashable {
        case youtube(videoID: String, title: String)
        case file(originalName: String)
    }

    var song: Song
    var source: Source
    var fileName: String
    var addedAt: Date
    var liked: Bool
    var trimStart: Double
    var trimEnd: Double?
    var fadeIn: Double
    var fadeOut: Double
    var loudnessDB: Double?
    var highlightStart: Double?
    var lyricsOffset: Double
    var genre: String?
    var hasCustomArtwork: Bool
    var needsReview: Bool

    var id: Int { song.id }
    var fileURL: URL { Paths.audioDir.appending(path: fileName) }

    init(song: Song, source: Source, fileName: String, addedAt: Date = .now) {
        self.song = song
        self.source = source
        self.fileName = fileName
        self.addedAt = addedAt
        liked = false
        trimStart = 0
        trimEnd = nil
        fadeIn = 0
        fadeOut = 0
        loudnessDB = nil
        highlightStart = nil
        lyricsOffset = 0
        genre = song.album?.genre
        hasCustomArtwork = false
        needsReview = false
    }

    enum CodingKeys: String, CodingKey {
        case song, source, fileName, addedAt, liked, trimStart, trimEnd, fadeIn, fadeOut,
             loudnessDB, highlightStart, lyricsOffset, genre, hasCustomArtwork, needsReview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        song = try c.decode(Song.self, forKey: .song)
        source = (try? c.decode(Source.self, forKey: .source)) ?? .file(originalName: "")
        fileName = try c.decode(String.self, forKey: .fileName)
        addedAt = (try? c.decode(Date.self, forKey: .addedAt)) ?? .now
        liked = (try? c.decodeIfPresent(Bool.self, forKey: .liked)) ?? false
        trimStart = (try? c.decodeIfPresent(Double.self, forKey: .trimStart)) ?? 0
        trimEnd = try? c.decodeIfPresent(Double.self, forKey: .trimEnd)
        fadeIn = (try? c.decodeIfPresent(Double.self, forKey: .fadeIn)) ?? 0
        fadeOut = (try? c.decodeIfPresent(Double.self, forKey: .fadeOut)) ?? 0
        loudnessDB = try? c.decodeIfPresent(Double.self, forKey: .loudnessDB)
        highlightStart = try? c.decodeIfPresent(Double.self, forKey: .highlightStart)
        lyricsOffset = (try? c.decodeIfPresent(Double.self, forKey: .lyricsOffset)) ?? 0
        genre = try? c.decodeIfPresent(String.self, forKey: .genre)
        hasCustomArtwork = (try? c.decodeIfPresent(Bool.self, forKey: .hasCustomArtwork)) ?? false
        needsReview = (try? c.decodeIfPresent(Bool.self, forKey: .needsReview)) ?? false
    }

    var sourceDescription: String {
        switch source {
        case .youtube(_, let title): return title
        case .file(let name): return name.isEmpty ? "Imported file" : name
        }
    }

    var youTubeID: String? {
        if case .youtube(let id, _) = source { return id }
        return nil
    }
}

// MARK: - Charts & playlists

struct ChartSource: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case deezerPlaylist, deezerGenre, appleCountry
    }

    var kind: Kind
    /// Deezer playlist id, Deezer genre id, or Apple country code.
    var ref: String
    var name: String
    var tag: String
    var colorHex: String
    var sourceLabel: String

    var id: String { "\(kind.rawValue):\(ref)" }
}

struct AutoRule: Codable, Hashable {
    enum Source: String, Codable, CaseIterable, Identifiable {
        case dailyMix, newReleases, mostPlayed, forgotten, similar, chart
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dailyMix: "Daily mix"
            case .newReleases: "New releases"
            case .mostPlayed: "Your most played"
            case .forgotten: "Forgotten favorites"
            case .similar: "Similar artists"
            case .chart: "A chart"
            }
        }
        var detail: String {
            switch self {
            case .dailyMix: "Your favorites mixed with new finds around one of your top artists. New every day"
            case .newReleases: "From artists you listen to and follow"
            case .mostPlayed: "Like \"On Repeat\""
            case .forgotten: "Played a lot, not lately"
            case .similar: "Artists like your top 10, or ones you pick"
            case .chart: "Top songs for a country or genre"
            }
        }
    }

    var source: Source
    var maxSongs: Int
    var artists: [Artist]
    var withinWeeks: Int
    var includeLiveAndRemixes: Bool
    var chart: ChartSource?
    /// Daily mixes: which of your top artists the mix is built around (1 = your most played).
    var mix: Int?

    init(source: Source, maxSongs: Int = 30, artists: [Artist] = [], withinWeeks: Int = 4,
         includeLiveAndRemixes: Bool = false, chart: ChartSource? = nil) {
        self.source = source
        self.maxSongs = maxSongs
        self.artists = artists
        self.withinWeeks = withinWeeks
        self.includeLiveAndRemixes = includeLiveAndRemixes
        self.chart = chart
    }
}

struct Playlist: Codable, Hashable, Identifiable {
    enum Kind: Codable, Hashable {
        case manual
        case auto(AutoRule)
        case chart(ChartSource)
    }

    var id: UUID
    var name: String
    var kind: Kind
    var songs: [Song]
    var pinned: Bool
    var keepDownloaded: Bool
    var wifiOnly: Bool
    var colorHex: String
    var createdAt: Date
    var refreshedAt: Date?
    var lastPlayedAt: Date?
    /// Set when the user picked their own cover photo; bumped on every change so cached images refresh.
    var coverVersion: Int?
    /// How the cover is drawn (nil = your photo if there is one, else the plain color).
    var cover: PlaylistCover?
    var coverEmoji: String?

    var effectiveCover: PlaylistCover {
        if let cover, cover != .photo || coverVersion != nil { return cover }
        return coverVersion != nil ? .photo : .color
    }

    init(name: String, kind: Kind, songs: [Song] = [], colorHex: String) {
        id = UUID()
        self.name = name
        self.kind = kind
        self.songs = songs
        pinned = false
        keepDownloaded = false
        wifiOnly = true
        self.colorHex = colorHex
        createdAt = .now
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, songs, pinned, keepDownloaded, wifiOnly, colorHex, createdAt, refreshedAt, lastPlayedAt, coverVersion
        case cover, coverEmoji
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .manual
        songs = (try? c.decodeIfPresent([Song].self, forKey: .songs)) ?? []
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        keepDownloaded = (try? c.decodeIfPresent(Bool.self, forKey: .keepDownloaded)) ?? false
        wifiOnly = (try? c.decodeIfPresent(Bool.self, forKey: .wifiOnly)) ?? true
        colorHex = (try? c.decodeIfPresent(String.self, forKey: .colorHex)) ?? "#334155"
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .now
        refreshedAt = try? c.decodeIfPresent(Date.self, forKey: .refreshedAt)
        lastPlayedAt = try? c.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        coverVersion = try? c.decodeIfPresent(Int.self, forKey: .coverVersion)
        cover = try? c.decodeIfPresent(PlaylistCover.self, forKey: .cover)
        coverEmoji = try? c.decodeIfPresent(String.self, forKey: .coverEmoji)
    }

    var isManual: Bool { if case .manual = kind { return true } else { return false } }
    var isChart: Bool { if case .chart = kind { return true } else { return false } }
    var isAuto: Bool { if case .auto = kind { return true } else { return false } }

    var badge: String? {
        switch kind {
        case .manual: nil
        case .auto: "AUTO"
        case .chart: "CHART"
        }
    }
}

// MARK: - Stats

struct PlayRecord: Codable, Identifiable, Hashable {
    enum Origin: String, Codable { case tunes, spotify }

    let id: UUID
    var songID: Int
    let title: String
    let artist: Artist
    /// Featured / linked artists besides the main one. Plays count for them too.
    let others: [Artist]
    let artworkURL: URL?
    let genre: String?
    let releaseYear: Int?
    let start: Date
    var seconds: Double
    let origin: Origin

    var allArtists: [Artist] { [artist] + others }

    init(songID: Int, title: String, artist: Artist, others: [Artist], artworkURL: URL?, genre: String?,
         releaseYear: Int?, start: Date, seconds: Double, origin: Origin) {
        id = UUID()
        self.songID = songID
        self.title = title
        self.artist = artist
        self.others = others
        self.artworkURL = artworkURL
        self.genre = genre
        self.releaseYear = releaseYear
        self.start = start
        self.seconds = seconds
        self.origin = origin
    }

    enum CodingKeys: String, CodingKey {
        case id, songID, title, artist, others, artworkURL, genre, releaseYear, start, seconds, origin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        songID = try c.decode(Int.self, forKey: .songID)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decode(Artist.self, forKey: .artist)
        others = (try? c.decodeIfPresent([Artist].self, forKey: .others)) ?? []
        artworkURL = try? c.decodeIfPresent(URL.self, forKey: .artworkURL)
        genre = try? c.decodeIfPresent(String.self, forKey: .genre)
        releaseYear = try? c.decodeIfPresent(Int.self, forKey: .releaseYear)
        start = try c.decode(Date.self, forKey: .start)
        seconds = (try? c.decode(Double.self, forKey: .seconds)) ?? 0
        origin = (try? c.decodeIfPresent(Origin.self, forKey: .origin)) ?? .tunes
    }
}

// MARK: - Concerts

struct Concert: Identifiable, Hashable {
    let id: String
    let name: String
    let venue: String
    let city: String
    let date: Date?
    let url: URL?
    let priceFrom: String?
    let distanceKm: Double?
}


/// Cover styles for playlists.
enum PlaylistCover: String, Codable, CaseIterable, Identifiable {
    case color, photo, collage, album, gradient, emoji
    var id: String { rawValue }
    var label: String {
        switch self {
        case .color: "Plain color"
        case .photo: "Your photo"
        case .collage: "Album collage"
        case .album: "First album cover"
        case .gradient: "Gradient"
        case .emoji: "Emoji"
        }
    }
    var icon: String {
        switch self {
        case .color: "square.fill"
        case .photo: "photo"
        case .collage: "square.grid.2x2.fill"
        case .album: "opticaldisc"
        case .gradient: "circle.lefthalf.filled"
        case .emoji: "face.smiling"
        }
    }
}
