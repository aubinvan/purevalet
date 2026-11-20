import XCTest
@testable import PureValet

final class ParsingTests: XCTestCase {
    func testParsesValetLinksTable() {
        let output = """
        +---------+-----+----------------------+-----------------------+-------------+
        | Site    | SSL | URL                  | Path                  | PHP Version |
        +---------+-----+----------------------+-----------------------+-------------+
        | shop | X   | https://shop.test | /Users/a/shop      | php@8.4     |
        | blog    |     | http://blog.test     | /Users/a/blog         | php         |
        +---------+-----+----------------------+-----------------------+-------------+
        """
        let sites = ValetModel.parseSites(output)
        XCTAssertEqual(sites.count, 2)
        XCTAssertEqual(sites[0], ValetSite(name: "shop", secured: true, url: "https://shop.test", path: "/Users/a/shop", php: "php@8.4"))
        XCTAssertFalse(sites[1].secured)
    }

    func testParsesProxiesAndEmptyOutput() {
        let output = """
        +------+-----+------------------+-----------------------+
        | Site | SSL | URL              | Host                  |
        +------+-----+------------------+-----------------------+
        | vite | X   | https://vite.test | http://127.0.0.1:5173 |
        +------+-----+------------------+-----------------------+
        """
        XCTAssertEqual(ValetModel.parseProxies(output).first?.host, "http://127.0.0.1:5173")
        XCTAssertTrue(ValetModel.parseSites("No links found.").isEmpty)
    }

    func testParkedSitesAreFlagged() {
        let output = """
        +------+-----+------------------+------------------+-------------+
        | Site | SSL | URL              | Path             | PHP Version |
        +------+-----+------------------+------------------+-------------+
        | api  |     | http://api.test  | /Users/a/Sites/api | php@8.3   |
        +------+-----+------------------+------------------+-------------+
        """
        XCTAssertEqual(ValetModel.parseSites(output, parked: true).first?.parked, true)
    }

    func testParsesParkedPathsJSON() {
        XCTAssertEqual(ValetModel.parsePaths("[\"/Users/a/Sites\",\"/Users/a/Code\"]\n"), ["/Users/a/Sites", "/Users/a/Code"])
        XCTAssertEqual(ValetModel.parsePaths("[]"), [])
        XCTAssertEqual(ValetModel.parsePaths("garbage"), [])
    }

    func testParsesValetVersion() {
        XCTAssertEqual(ValetModel.parseValetVersion("Laravel Valet 4.8.1\n"), "4.8.1")
        XCTAssertNil(ValetModel.parseValetVersion("command not found"))
    }

    func testVersionFromCellarPath() {
        XCTAssertEqual(ValetModel.versionFromCellarPath("../Cellar/php@8.4/8.4.27_1"), "8.4.27")
        XCTAssertEqual(ValetModel.versionFromCellarPath("../Cellar/nginx/1.29.3"), "1.29.3")
    }

    func testVersionComparison() {
        XCTAssertTrue(Updater.isVersion("0.10.0", newerThan: "0.9.2"))
        XCTAssertTrue(Updater.isVersion("1.0", newerThan: "0.9.9"))
        XCTAssertFalse(Updater.isVersion("0.5.0", newerThan: "0.5.0"))
        XCTAssertFalse(Updater.isVersion("0.4.9", newerThan: "0.5"))
    }

    func testParsesGitHubRelease() throws {
        let json = """
        {"tag_name": "v0.6.0", "html_url": "https://github.com/aubinvan/purevalet/releases/tag/v0.6.0",
         "assets": [{"browser_download_url": "https://example.com/PureValet-0.6.0.dmg.sha256"},
                    {"browser_download_url": "https://example.com/PureValet-0.6.0.dmg"}]}
        """
        let update = try XCTUnwrap(Updater.parseRelease(Data(json.utf8)))
        XCTAssertEqual(update.version, "0.6.0")
        XCTAssertEqual(update.downloadURL?.lastPathComponent, "PureValet-0.6.0.dmg")
        XCTAssertNil(Updater.parseRelease(Data("{}".utf8)))
    }

    func testSlug() {
        XCTAssertEqual(ValetModel.slug("Mon Projet_2"), "mon-projet-2")
    }
}
