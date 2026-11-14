import XCTest
@testable import PulseCore

/// Not a test of PULSE: the tool that builds the shipped study list from saved YouTube search pages, with
/// the app's own parser and filter. Runs only when asked (PULSE_SEED_DIR).
final class StudySeedGatherTests: XCTestCase {
    func testPrintTheSearchesToRun() throws {
        guard ProcessInfo.processInfo.environment["PULSE_SEED_QUERIES"] == "1" else { throw XCTSkip("prints the searches when asked") }
        for genre in VideoGenre.allCases {
            for (index, query) in StudyFinder.queries(for: genre).enumerated() {
                for (kind, filter) in [("r", YouTubeSearchParser.videosFilter), ("v", YouTubeSearchParser.videosByViewsFilter)] {
                    print("SEEDQ\t\(genre.rawValue)-\(index)-\(kind)\t\(YouTubeSearchParser.searchURL(query: query, filter: filter).absoluteString)")
                }
            }
        }
    }

    func testBuildTheListFromSavedPages() throws {
        guard let folder = ProcessInfo.processInfo.environment["PULSE_SEED_DIR"] else { throw XCTSkip("builds the list when given saved pages") }
        var taken = Set<String>()
        for genre in VideoGenre.allCases {
            var results: [VideoSearchResult] = []
            var pages = 0
            for index in StudyFinder.queries(for: genre).indices {
                for kind in ["r", "v"] {
                    let url = URL(fileURLWithPath: folder).appendingPathComponent("\(genre.rawValue)-\(index)-\(kind).html")
                    guard let data = try? Data(contentsOf: url) else { continue }
                    pages += 1
                    results += YouTubeSearchParser.results(fromHTML: String(decoding: data, as: UTF8.self))
                }
            }
            let ranked = StudyFinder.rank(results, for: genre, excluding: taken)
            ranked.forEach { taken.insert($0.videoID) }
            print("SEEDSTAT\t\(genre.rawValue)\tpages \(pages)\traw \(results.count)\tdistinct \(Set(results.map(\.videoID)).count)\taccepted \(ranked.count)")
            for result in ranked {
                let clean = { (text: String) in text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
                print("SEED\t\(genre.rawValue)\t\(result.videoID)\t\(result.views.map(String.init) ?? "")\t\(result.duration.map { String(Int($0)) } ?? "")\t\(clean(result.channel))\t\(clean(result.title))")
            }
        }
    }
}
