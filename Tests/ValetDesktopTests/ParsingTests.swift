import XCTest
@testable import ValetDesktop

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

    func testSlug() {
        XCTAssertEqual(ValetModel.slug("Mon Projet_2"), "mon-projet-2")
    }
}
