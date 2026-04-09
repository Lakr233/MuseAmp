@testable import AmMusic
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct SearchViewControllerTests {
    @Test("Search view configures title and search controller")
    func searchControllerConfiguration() throws {
        let sandbox = TestLibrarySandbox()
        let vc = SearchViewController(environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        #expect(vc.definesPresentationContext == true)
        #expect(vc.navigationItem.hidesSearchBarWhenScrolling == false)

        let searchController = try #require(vc.navigationItem.searchController)
        #expect(searchController.obscuresBackgroundDuringPresentation == false)
        #expect(searchController.searchBar.placeholder != nil)
        #expect(searchController.searchBar.accessibilityIdentifier == "search.bar")
    }

    @Test("Search results table exists with accessibility identifier")
    func resultsTableExists() throws {
        let sandbox = TestLibrarySandbox()
        let vc = SearchViewController(environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        let resultsTable = try #require(findResultsTable(in: vc.view))
        #expect(resultsTable.accessibilityIdentifier == "search.results")
    }

    @Test("Search results table is hidden before entering query")
    func initialVisibility() throws {
        let sandbox = TestLibrarySandbox()
        let vc = SearchViewController(environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        let resultsTable = try #require(findResultsTable(in: vc.view))
        #expect(resultsTable.isHidden == true)
    }
}

private extension SearchViewControllerTests {
    func findResultsTable(in view: UIView) -> UITableView? {
        if let tableView = view as? UITableView,
           tableView.accessibilityIdentifier == "search.results"
        {
            return tableView
        }

        for subview in view.subviews {
            if let tableView = findResultsTable(in: subview) {
                return tableView
            }
        }

        return nil
    }
}
