import Foundation

/// Upcoming shows from Ticketmaster's free Discovery API (needs the user's own key).
enum Concerts {
    enum ConcertError: LocalizedError {
        case noKey, badKey
        var errorDescription: String? {
            switch self {
            case .noKey: "Add your Ticketmaster key in Connections to see shows."
            case .badKey: "Ticketmaster didn't accept the key."
            }
        }
    }

    static func upcoming(artistName: String, key: String, city: ConcertCity, radiusKm: Int) async throws -> [Concert] {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ConcertError.noKey }
        // 1. Find the artist ("attraction").
        var a = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/attractions.json")!
        a.queryItems = [.init(name: "apikey", value: key), .init(name: "keyword", value: artistName),
                        .init(name: "classificationName", value: "music"), .init(name: "size", value: "5")]
        let attractions = try await json(a.url!)
        let list = ((attractions["_embedded"] as? [String: Any])?["attractions"] as? [[String: Any]]) ?? []
        let wanted = artistName.normalizedForMatching
        guard let attraction = list.first(where: { ($0["name"] as? String)?.normalizedForMatching == wanted }) ?? list.first,
              let attractionID = attraction["id"] as? String else { return [] }
        // 2. Events near the chosen city.
        var e = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events.json")!
        e.queryItems = [.init(name: "apikey", value: key), .init(name: "attractionId", value: attractionID),
                        .init(name: "geoPoint", value: geohash(lat: city.lat, lon: city.lon, precision: 7)),
                        .init(name: "radius", value: String(radiusKm)), .init(name: "unit", value: "km"),
                        .init(name: "sort", value: "date,asc"), .init(name: "size", value: "10")]
        let events = try await json(e.url!)
        let items = ((events["_embedded"] as? [String: Any])?["events"] as? [[String: Any]]) ?? []
        return items.compactMap { ev in
            guard let id = ev["id"] as? String else { return nil }
            let start = (ev["dates"] as? [String: Any])?["start"] as? [String: Any]
            let day = (start?["localDate"] as? String).flatMap { Fmt.isoDay.date(from: $0) }
            let venueDict = ((ev["_embedded"] as? [String: Any])?["venues"] as? [[String: Any]])?.first
            let venue = (venueDict?["name"] as? String) ?? ""
            let cityName = ((venueDict?["city"] as? [String: Any])?["name"] as? String) ?? ""
            var distance: Double?
            if let loc = venueDict?["location"] as? [String: Any],
               let lat = Double(loc["latitude"] as? String ?? ""), let lon = Double(loc["longitude"] as? String ?? "") {
                distance = haversineKm(city.lat, city.lon, lat, lon)
            }
            var price: String?
            if let pr = (ev["priceRanges"] as? [[String: Any]])?.first, let min = pr["min"] as? Double, let cur = pr["currency"] as? String {
                price = "from " + min.formatted(.currency(code: cur).precision(.fractionLength(0)))
            }
            return Concert(id: id, name: ev["name"] as? String ?? artistName, venue: venue, city: cityName, date: day,
                           url: (ev["url"] as? String).flatMap(URL.init(string:)), priceFrom: price, distanceKm: distance)
        }
    }

    private static func json(_ url: URL) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 { throw ConcertError.badKey }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func geohash(lat: Double, lon: Double, precision: Int) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latR = (-90.0, 90.0), lonR = (-180.0, 180.0)
        var hash = "", bit = 0, ch = 0, even = true
        while hash.count < precision {
            if even {
                let mid = (lonR.0 + lonR.1) / 2
                if lon > mid { ch |= 1 << (4 - bit); lonR.0 = mid } else { lonR.1 = mid }
            } else {
                let mid = (latR.0 + latR.1) / 2
                if lat > mid { ch |= 1 << (4 - bit); latR.0 = mid } else { latR.1 = mid }
            }
            even.toggle()
            if bit < 4 { bit += 1 } else { hash.append(base32[ch]); bit = 0; ch = 0 }
        }
        return hash
    }

    static func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0, dLat = (lat2 - lat1) * .pi / 180, dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Short artist bio from Wikipedia (no key needed).
enum ArtistBio {
    static func fetch(_ name: String) async -> String? {
        let musicWords = ["singer", "band", "musician", "rapper", "songwriter", "dj", "producer", "group", "duo", "composer", "artist"]
        for title in [name, "\(name) (band)", "\(name) (singer)", "\(name) (musician)", "\(name) (rapper)"] {
            let encoded = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)"),
                  let obj = try? await Net.getJSON(url) as? [String: Any],
                  obj["type"] as? String == "standard",
                  let extract = obj["extract"] as? String else { continue }
            let lower = extract.lowercased()
            if musicWords.contains(where: { lower.contains($0) }) { return extract }
        }
        return nil
    }
}
