import XCTest
@testable import Stowaway

final class MockReleaseFetcher: ReleaseFetching {
    var result: Result<ReleaseInfo?, Error>
    private(set) var calls = 0

    init(_ result: Result<ReleaseInfo?, Error>) {
        self.result = result
    }

    convenience init(version: String) {
        self.init(.success(ReleaseInfo(version: version, url: URL(string: "https://github.com/SihanCheng0/stowaway/releases/tag/v\(version)")!)))
    }

    func latestRelease() async throws -> ReleaseInfo? {
        calls += 1
        return try result.get()
    }
}

final class VersionComparatorTests: XCTestCase {
    func testNewerPatch() {
        XCTAssertTrue(VersionComparator.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.0", than: "1.0.1"))
    }

    func testComparesNumericallyNotLexically() {
        XCTAssertTrue(VersionComparator.isNewer("1.10", than: "v1.2"))
        XCTAssertFalse(VersionComparator.isNewer("v1.2", than: "1.10"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(VersionComparator.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(VersionComparator.isNewer("v1.0.0", than: "1.0.0"))
        XCTAssertFalse(VersionComparator.isNewer("V2.3", than: "v2.3"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertFalse(VersionComparator.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.0", than: "1.0"))
        XCTAssertTrue(VersionComparator.isNewer("1.0.0.1", than: "1"))
    }

    func testSuffixesAreIgnored() {
        XCTAssertTrue(VersionComparator.isNewer("2.0.0-beta.1", than: "1.9.9"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.0-rc.2", than: "1.0.0"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.0+build.7", than: "1.0.0"))
    }

    func testJunkIsNeverNewer() {
        for junk in ["", "v", "latest", "1.x", "1..2", "1.0.", "+1.0", "1.0 beta", "１.0", "99999999999999999999"] {
            XCTAssertFalse(VersionComparator.isNewer(junk, than: "1.0.0"), junk)
            XCTAssertFalse(VersionComparator.isNewer("2.0.0", than: junk), junk)
        }
    }
}

final class ReleaseParsingTests: XCTestCase {
    private func json(
        tag: String? = "v1.2.0",
        url: String = "https://github.com/SihanCheng0/stowaway/releases/tag/v1.2.0",
        draft: Bool = false,
        prerelease: Bool = false
    ) -> Data {
        var fields = [
            #""html_url": "\#(url)""#,
            #""draft": \#(draft)"#,
            #""prerelease": \#(prerelease)"#,
            #""name": "Stowaway 1.2.0""#,
            #""assets": []"#,
        ]
        if let tag {
            fields.append(#""tag_name": "\#(tag)""#)
        }
        return Data("{\(fields.joined(separator: ", "))}".utf8)
    }

    func testParsesPublishedRelease() throws {
        let release = try GitHubReleaseFetcher.parse(json())
        XCTAssertEqual(release, ReleaseInfo(
            version: "1.2.0",
            url: URL(string: "https://github.com/SihanCheng0/stowaway/releases/tag/v1.2.0")!
        ))
    }

    func testSkipsDrafts() throws {
        XCTAssertNil(try GitHubReleaseFetcher.parse(json(draft: true)))
    }

    func testSkipsPrereleases() throws {
        XCTAssertNil(try GitHubReleaseFetcher.parse(json(tag: "v1.3.0-beta.1", prerelease: true)))
    }

    func testRejectsLinksOutsideGitHub() throws {
        for url in [
            "http://github.com/SihanCheng0/stowaway/releases/tag/v1.2.0",
            "https://github.com.evil.example/SihanCheng0/stowaway",
            "https://github.com@evil.example/SihanCheng0/stowaway",
            "https://evil.example/github.com",
            "file:///Applications/Stowaway.app",
        ] {
            XCTAssertNil(try GitHubReleaseFetcher.parse(json(url: url)), url)
        }
    }

    func testMissingTagThrows() {
        XCTAssertThrowsError(try GitHubReleaseFetcher.parse(json(tag: nil)))
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private func check(current: String, fetcher: MockReleaseFetcher) async -> UpdateChecker {
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: current)
        await checker.check()
        XCTAssertEqual(fetcher.calls, 1)
        return checker
    }

    func testNewerReleaseIsAvailable() async {
        let checker = await check(current: "1.0.0", fetcher: MockReleaseFetcher(version: "1.1.0"))
        XCTAssertEqual(checker.available?.version, "1.1.0")
    }

    func testSameOrOlderReleaseIsIgnored() async {
        for version in ["1.0.0", "1.0", "0.9.9"] {
            let checker = await check(current: "1.0.0", fetcher: MockReleaseFetcher(version: version))
            XCTAssertNil(checker.available, version)
        }
    }

    func testNoReleaseYet() async {
        let checker = await check(current: "1.0.0", fetcher: MockReleaseFetcher(.success(nil)))
        XCTAssertNil(checker.available)
    }

    func testFailureIsSwallowed() async {
        let checker = await check(current: "1.0.0", fetcher: MockReleaseFetcher(.failure(URLError(.notConnectedToInternet))))
        XCTAssertNil(checker.available)
    }

    func testFailureKeepsPreviousResult() async {
        let fetcher = MockReleaseFetcher(version: "1.1.0")
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.0.0")
        await checker.check()
        fetcher.result = .failure(URLError(.timedOut))
        await checker.check()
        XCTAssertEqual(checker.available?.version, "1.1.0")
    }

    func testWithdrawnReleaseClearsNotice() async {
        let fetcher = MockReleaseFetcher(version: "1.1.0")
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.0.0")
        await checker.check()
        fetcher.result = .success(nil)
        await checker.check()
        XCTAssertNil(checker.available)
    }
}

/// Serves canned responses to GitHubReleaseFetcher so the HTTP layer is tested without the network.
final class StubURLProtocol: URLProtocol {
    static var response: (status: Int, body: String) = (200, "")
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.response.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class GitHubReleaseFetcherHTTPTests: XCTestCase {
    private let fetcher: GitHubReleaseFetcher = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return GitHubReleaseFetcher(session: URLSession(configuration: configuration))
    }()

    func testLatestReleaseRequestAndParse() async throws {
        StubURLProtocol.response = (200, #"{"tag_name":"v1.2.0","html_url":"https://github.com/SihanCheng0/stowaway/releases/tag/v1.2.0","draft":false,"prerelease":false}"#)
        let release = try await fetcher.latestRelease()
        XCTAssertEqual(release?.version, "1.2.0")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/SihanCheng0/stowaway/releases/latest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Stowaway/") == true)
        XCTAssertNil(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"))
    }

    func testNotFoundMeansNoReleaseYet() async throws {
        StubURLProtocol.response = (404, #"{"message":"Not Found"}"#)
        let release = try await fetcher.latestRelease()
        XCTAssertNil(release)
    }

    func testRateLimitAndServerErrorsThrow() async {
        for status in [403, 429, 500] {
            StubURLProtocol.response = (status, "{}")
            do {
                _ = try await fetcher.latestRelease()
                XCTFail("Expected HTTP \(status) to throw")
            } catch {}
        }
    }
}
