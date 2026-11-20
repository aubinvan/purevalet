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

    func testDetectsValetServicesFromProcessList() {
        let running = """
        /opt/homebrew/opt/dnsmasq/sbin/dnsmasq
        nginx: master process /opt/homebrew/opt/nginx/bin/nginx -g daemon off;
        nginx: worker process
        php-fpm: master process (/opt/homebrew/etc/php/8.5/php-fpm.conf)
        php-fpm: pool valet
        """
        XCTAssertTrue(ValetModel.valetServicesRunning(running))
        XCTAssertFalse(ValetModel.valetServicesRunning("/opt/homebrew/opt/dnsmasq/sbin/dnsmasq\nphp-fpm: pool www"))
        XCTAssertFalse(ValetModel.valetServicesRunning(""))
    }

    func testHidesValetInternalSitesFolder() {
        let paths = ["/Users/a/.config/valet/Sites", "/Users/a/Sites"]
        XCTAssertEqual(ValetModel.userParkedPaths(paths, configDir: "/Users/a/.config/valet"), ["/Users/a/Sites"])
    }

    func testSiteHealthFromStatusCode() {
        XCTAssertTrue(ValetModel.isHealthy(statusCode: 200))
        XCTAssertTrue(ValetModel.isHealthy(statusCode: 302))
        XCTAssertTrue(ValetModel.isHealthy(statusCode: 404))
        XCTAssertFalse(ValetModel.isHealthy(statusCode: 500))
        XCTAssertFalse(ValetModel.isHealthy(statusCode: 503))
    }

    func testParsesPhpMyAdminFeed() throws {
        let json = """
        {"version": "5.2.3", "releases": [
          {"version": "5.2.3", "php_versions": ">=7.2,<8.4"},
          {"version": "4.9.11", "php_versions": ">=5.5,<8.0"}]}
        """
        let release = try XCTUnwrap(PhpMyAdmin.parseRelease(Data(json.utf8)))
        XCTAssertEqual(release, PhpMyAdminRelease(version: "5.2.3", phpConstraint: ">=7.2,<8.4"))
    }

    func testPicksCompatiblePHPForPhpMyAdmin() {
        let installed = [PHPFormula(formula: "php", version: "8.5"), PHPFormula(formula: "php@8.4", version: "8.4"),
                         PHPFormula(formula: "php@8.3", version: "8.3")]
        XCTAssertEqual(PhpMyAdmin.compatiblePHP(constraint: ">=7.2,<8.4", installed: installed, global: "php"), "php@8.3")
        XCTAssertNil(PhpMyAdmin.compatiblePHP(constraint: ">=7.2,<8.4", installed: installed, global: "php@8.3"))
        XCTAssertNil(PhpMyAdmin.compatiblePHP(constraint: ">=8.1", installed: installed, global: "php"))
        XCTAssertNil(PhpMyAdmin.compatiblePHP(constraint: nil, installed: installed, global: "php"))
    }

    func testPhpMyAdminConfigUsesSocketAndRandomSecret() {
        let a = PhpMyAdmin.config(), b = PhpMyAdmin.config()
        XCTAssertTrue(a.contains("'socket'] = '/tmp/mysql.sock'"))
        XCTAssertTrue(a.contains("'auth_type'] = 'cookie'"))
        XCTAssertNotEqual(a, b)
    }

    func testSlug() {
        XCTAssertEqual(ValetModel.slug("Mon Projet_2"), "mon-projet-2")
    }
}
