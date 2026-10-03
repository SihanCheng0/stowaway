import Foundation

struct ReleaseInfo: Equatable {
    let version: String
    let url: URL
}

/// Compares dotted release versions such as "v1.2.10". Pre-release and build suffixes are ignored.
enum VersionComparator {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = components(candidate), let current = components(current) else { return false }
        for index in 0..<max(candidate.count, current.count) {
            let new = index < candidate.count ? candidate[index] : 0
            let old = index < current.count ? current[index] : 0
            if new != old { return new > old }
        }
        return false
    }

    private static func components(_ version: String) -> [Int]? {
        let core = stripped(version).prefix { $0 != "-" && $0 != "+" }
        var numbers: [Int] = []
        for part in core.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    /// "v1.2.0" → "1.2.0"
    static func stripped(_ version: String) -> Substring {
        version.first == "v" || version.first == "V" ? version.dropFirst() : Substring(version)
    }
}

protocol ReleaseFetching {
    func latestRelease() async throws -> ReleaseInfo?
}

struct GitHubReleaseFetcher: ReleaseFetching {
    static let repository = "SihanCheng0/stowaway"

    /// In-memory only, so update checks leave no cookies or cache behind. Checks often fire
    /// right after wake, before Wi-Fi is back, so wait for a connection instead of failing.
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 15 * 60
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession

    init(session: URLSession = Self.defaultSession) {
        self.session = session
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: String
        let draft: Bool
        let prerelease: Bool
    }

    func latestRelease() async throws -> ReleaseInfo? {
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Stowaway/\(Bundle.main.shortVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 404 until the first release is published.
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> ReleaseInfo? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              let url = URL(string: release.htmlUrl), url.scheme == "https", url.host() == "github.com"
        else { return nil }
        return ReleaseInfo(version: String(VersionComparator.stripped(release.tagName)), url: url)
    }
}

/// Notify-only: looks for a newer GitHub release once a day and never downloads anything.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var available: ReleaseInfo?
    /// Homebrew installs should update with `brew upgrade`, or brew loses track of the version.
    let isHomebrewInstall: Bool
    static let brewUpgradeCommand = "brew upgrade --cask stowaway"

    private static let initialDelay: TimeInterval = 3

    private let fetcher: ReleaseFetching
    private let currentVersion: String
    private let interval: TimeInterval
    private var task: Task<Void, Never>?
    private var loggedFailure = false

    init(
        fetcher: ReleaseFetching = GitHubReleaseFetcher(),
        currentVersion: String = Bundle.main.shortVersion,
        interval: TimeInterval = 24 * 60 * 60,
        isHomebrewInstall: Bool = UpdateChecker.detectHomebrewInstall()
    ) {
        self.fetcher = fetcher
        self.currentVersion = currentVersion
        self.interval = interval
        self.isHomebrewInstall = isHomebrewInstall
    }

    nonisolated static func detectHomebrewInstall() -> Bool {
        ["/opt/homebrew/Caskroom/stowaway", "/usr/local/Caskroom/stowaway"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    func start() {
        guard task == nil else { return }
        let interval = interval
        task = Task { [weak self] in
            var delay = Self.initialDelay
            // The continuous clock keeps counting while the Mac sleeps, so a daily check stays daily.
            while (try? await Task.sleep(for: .seconds(delay))) != nil {
                guard let self else { return }
                await self.check()
                delay = interval
            }
        }
    }

    func check() async {
        do {
            let release = try await fetcher.latestRelease()
            loggedFailure = false
            if let release, VersionComparator.isNewer(release.version, than: currentVersion) {
                available = release
            } else {
                available = nil
            }
        } catch {
            guard !loggedFailure else { return }
            loggedFailure = true
            NSLog("Stowaway: update check failed: %@", String(describing: error))
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
