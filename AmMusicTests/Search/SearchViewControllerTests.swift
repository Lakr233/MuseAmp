@testable import AmMusic
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct SearchViewControllerTests {
    @Test
    func `Search view configures title and search controller`() throws {
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

    @Test
    func `Search results table exists with accessibility identifier`() throws {
        let sandbox = TestLibrarySandbox()
        let vc = SearchViewController(environment: sandbox.makeEnvironment())
        vc.loadViewIfNeeded()

        let resultsTable = try #require(findResultsTable(in: vc.view))
        #expect(resultsTable.accessibilityIdentifier == "search.results")
    }

    @Test
    func `Search results table is hidden before entering query`() throws {
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
