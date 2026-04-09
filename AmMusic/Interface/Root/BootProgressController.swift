import AmMusicDatabaseKit
import UIKit

final class BootProgressController: UIViewController {
    var onBootComplete: ((AppEnvironment) -> Void)?

    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var bootTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        beginBootSequence()
    }

    deinit {
        bootTask?.cancel()
    }
}

private extension BootProgressController {
    func setupLayout() {
        view.backgroundColor = .systemBackground

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        view.addSubview(statusLabel)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    func beginBootSequence() {
        bootTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let manager = try await AppEnvironment.initializeDatabaseManager()
                let environment = AppEnvironment(databaseManager: manager)
                await MainActor.run {
                    self.onBootComplete?(environment)
                }
            } catch {
                AppLog.error(self, "Boot sequence failed: \(error)")
                await MainActor.run {
                    self.showFailureState()
                }
            }
        }
    }

    func showFailureState() {
        activityIndicator.stopAnimating()
        statusLabel.text = "Boot Failed"
        statusLabel.isHidden = false
    }
}
