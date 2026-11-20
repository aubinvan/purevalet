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

    func testRootlessRewriteListensOnAllInterfacesWithUserLog() {
        let conf = """
        server {
            listen 127.0.0.1:80 default_server;
            listen [::1]:80 default_server;
            #listen 127.0.0.1:80; # valet loopback
            listen 127.0.0.1:443 ssl;
            error_log "/Users/a/.config/valet/Log/nginx-error.log";
        }
        """
        let out = RootlessRuntime.rootless(conf, errorLog: "/tmp/rt/nginx-error.log")
        XCTAssertTrue(out.contains("listen 80 default_server;"))
        XCTAssertTrue(out.contains("listen [::]:80 default_server;"))
        XCTAssertTrue(out.contains("listen 443 ssl;"))
        XCTAssertTrue(out.contains("#listen 127.0.0.1:80; # valet loopback"), "comments stay untouched")
        XCTAssertTrue(out.contains(#"error_log "/tmp/rt/nginx-error.log";"#))
        XCTAssertFalse(out.contains("listen 127.0.0.1:443"))
    }

    func testValetFilesParsesIsolationProxyAndSockets() {
        XCTAssertEqual(ValetFiles.isolatedVersion("# ISOLATED_PHP_VERSION=php@8.3\nserver {}"), "php@8.3")
        XCTAssertNil(ValetFiles.isolatedVersion("server {}"))
        XCTAssertEqual(ValetFiles.proxyHost("location / { proxy_pass http://127.0.0.1:5173; }"), "http://127.0.0.1:5173")
        XCTAssertEqual(ValetFiles.socketName("php@8.3"), "valet83.sock")
        let isolated = ValetFiles.withSocket("# ISOLATED_PHP_VERSION=php@8.4\nfastcgi_pass unix:/x/valet84.sock;", version: "php@8.3")
        XCTAssertTrue(isolated.hasPrefix("# ISOLATED_PHP_VERSION=php@8.3\n"))
        XCTAssertTrue(isolated.contains("valet83.sock"))
        XCTAssertEqual(isolated.components(separatedBy: "ISOLATED_PHP_VERSION").count, 2, "a single marker")
    }

    func testValetFilesReadsSitesFromDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pv-\(UUID().uuidString)")
        let home = root.appendingPathComponent("valet").path
        let projects = root.appendingPathComponent("projects").path
        let fm = FileManager.default
        for dir in ["\(home)/Sites", "\(home)/Nginx", "\(home)/Certificates", "\(projects)/shop", "\(projects)/blog"] {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }
        try #"{"tld":"test","paths":["\#(home)/Sites","\#(projects)"]}"#.write(toFile: "\(home)/config.json", atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: "\(home)/Sites/api", withDestinationPath: "/srv/api")
        try "".write(toFile: "\(home)/Certificates/api.test.crt", atomically: true, encoding: .utf8)
        try "# ISOLATED_PHP_VERSION=php@8.3\nserver {}".write(toFile: "\(home)/Nginx/api.test", atomically: true, encoding: .utf8)
        try "server { location / { proxy_pass http://127.0.0.1:3000; } }".write(toFile: "\(home)/Nginx/vite.test", atomically: true, encoding: .utf8)

        let files = ValetFiles(home: home, valetPackage: "/nowhere")
        let sites = files.sites(globalPHP: "php@8.5")
        XCTAssertEqual(sites.map(\.name), ["api", "blog", "shop"])
        XCTAssertEqual(sites[0], ValetSite(name: "api", secured: true, url: "https://api.test", path: "/srv/api", php: "php@8.3"))
        XCTAssertTrue(sites[1].parked)
        XCTAssertEqual(sites[1].php, "php@8.5")
        XCTAssertEqual(files.proxies().map(\.host), ["http://127.0.0.1:3000"])
        XCTAssertEqual(files.parkedPaths, [projects])
        XCTAssertEqual(files.isolatedVersions(), ["8.3"])
    }

    func testRootlessSetupCoversBothHomebrewServiceNames() {
        let labels = RootlessSetup.serviceLabels(formulas: [PHPFormula(formula: "php@8.3", version: "8.3")])
        XCTAssertTrue(labels.contains("sh.brew.dnsmasq"))
        XCTAssertTrue(labels.contains("homebrew.mxcl.nginx"))
        XCTAssertTrue(labels.contains("sh.brew.php@8.3"))
    }

    func testRootlessSetupScript() {
        let script = RootlessSetup.script(user: "ana", home: "/Users/ana", tld: "test",
                                          labels: ["homebrew.mxcl.nginx"], caPem: "/Users/ana/.config/valet/CA/ca.pem")
        XCTAssertTrue(script.contains("launchctl bootout system/\"$l\""))
        XCTAssertTrue(script.contains("port 1053"))
        XCTAssertTrue(script.contains("> /etc/resolver/'test'"))
        XCTAssertTrue(script.contains("chown -R 'ana':staff '/Users/ana/.config/valet'"))
        XCTAssertTrue(script.contains("add-trusted-cert -d -r trustRoot"))
        XCTAssertTrue(script.contains(#"pkill -f 'dnsmasq --keep-in-foreground -C /opt/homebrew/etc/dnsmasq\.conf'"#))
        XCTAssertTrue(script.contains(#"php-fpm: master process \(/opt/homebrew/etc/php/'"#), "regex-escaped parenthesis")
        let tricky = RootlessSetup.script(user: "o'neil", home: "/Users/o'neil", tld: "test", labels: [], caPem: "/x")
        XCTAssertTrue(tricky.contains("'o'\\''neil'"), "single quotes are escaped")
    }

    func testSetupFailureExplanations() {
        let cancelled = RootlessSetup.explain(CommandResult(status: 1, output: "execution error: User canceled. (-128)"))
        XCTAssertTrue(cancelled.output.hasPrefix(String(localized: "Setup cancelled.")))
        let refused = RootlessSetup.explain(CommandResult(status: 1, output: "execution error: The administrator user name or password was incorrect. (-60007)"))
        XCTAssertTrue(refused.output.contains("(-60007)"))
        XCTAssertFalse(refused.output.hasPrefix("execution error"))
    }

    func testSlug() {
        XCTAssertEqual(ValetModel.slug("Mon Projet_2"), "mon-projet-2")
    }
}
