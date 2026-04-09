import Kingfisher
import LRUCache
import QuickLook
import SnapKit
import Then
import UIKit

/// Reusable artwork view with centered SF Symbol placeholder.
class AmImageView: UIView {
    private static let previewFileCache = LRUCache<URL, URL>(countLimit: 100)
    private let imageView = UIImageView().then {
        $0.contentMode = .scaleAspectFill
        $0.clipsToBounds = true
        $0.alpha = 0
    }

    private let placeholderView = UIImageView().then {
        $0.contentMode = .center
        $0.tintColor = .tertiaryLabel
    }

    private let blurView: UIVisualEffectView = {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        v.alpha = 0
        return v
    }()

    var allowsPreviewOnTap = false {
        didSet {
            tapGestureRecognizer.isEnabled = allowsPreviewOnTap
            imageView.isUserInteractionEnabled = allowsPreviewOnTap
        }
    }

    private var placeholderSymbol: String = "music.note"
    private var currentURL: URL?
    private let tapGestureRecognizer = UITapGestureRecognizer()
    private let previewCoordinator = PreviewCoordinator()
    var onImageLoaded: ((URL, UIImage) -> Void)? {
        didSet {
            guard let currentURL,
                  let image = imageView.image
            else {
                return
            }
            onImageLoaded?(currentURL, image)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func setup() {
        backgroundColor = .secondarySystemFill
        clipsToBounds = true

        addSubview(imageView)
        addSubview(blurView)
        addSubview(placeholderView)

        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }
        blurView.snp.makeConstraints { $0.edges.equalToSuperview() }
        placeholderView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.lessThanOrEqualTo(64)
            make.edges.equalToSuperview().inset(InterfaceStyle.Spacing.xSmall).priority(.medium)
        }

        tapGestureRecognizer.addTarget(self, action: #selector(handleTap))
        tapGestureRecognizer.isEnabled = false
        imageView.isUserInteractionEnabled = false
        imageView.addGestureRecognizer(tapGestureRecognizer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePlaceholderSize()
    }

    // MARK: - Public API

    /// Configure the placeholder symbol and corner radius.
    func configure(placeholder: String, cornerRadius: CGFloat) {
        placeholderSymbol = placeholder
        layer.cornerRadius = cornerRadius
        imageView.layer.cornerRadius = cornerRadius
        updatePlaceholderSize()
        if imageView.image == nil, currentURL == nil {
            showPlaceholder()
        }
    }

    /// Load artwork from a URL.
    func loadImage(url: URL?) {
        guard let url else {
            currentURL = nil
            previewCoordinator.previewItemURL = nil
            cancelLoading()
            showPlaceholder()
            return
        }

        guard url != currentURL else {
            if let image = imageView.image {
                onImageLoaded?(url, image)
            }
            return
        }
        cancelLoading()
        currentURL = url

        if loadCachedFromMemory(for: url) {
            return
        }

        if loadCachedFromDisk(for: url) {
            return
        }

        imageView.kf.setImage(with: url, options: [.transition(.none)]) { [weak self] result in
            guard let self else { return }
            guard currentURL == url else {
                return
            }
            switch result {
            case let .success(value):
                applyLoadedImage(
                    value.image,
                    from: url
                )
            case let .failure(error):
                AppLog.error(
                    self,
                    "loadImage failure url=\(Self.redactedURLDescription(for: url)) error=\(error.localizedDescription)"
                )
                showPlaceholder()
            }
        }
    }

    func setImage(_ image: UIImage) {
        currentURL = nil
        cancelLoading()
        imageView.image = image
        imageView.alpha = 1
        blurView.alpha = 0
        placeholderView.alpha = 0
    }

    /// Cancel any pending download and reset to placeholder state.
    func reset() {
        currentURL = nil
        cancelLoading()
        imageView.image = nil
        imageView.alpha = 0
        blurView.alpha = 0
        placeholderView.alpha = 1
        previewCoordinator.previewItemURL = nil
    }

    // MARK: - Private

    private func cancelLoading() {
        imageView.kf.cancelDownloadTask()
    }

    private func loadCachedFromMemory(for url: URL) -> Bool {
        let cache = KingfisherManager.shared.cache
        let key = url.cacheKey
        guard let cachedImage = cache.retrieveImageInMemoryCache(forKey: key) else {
            return false
        }
        applyLoadedImage(cachedImage, from: url)
        return true
    }

    private func loadCachedFromDisk(for url: URL) -> Bool {
        let cache = KingfisherManager.shared.cache
        let key = url.cacheKey
        guard cache.imageCachedType(forKey: key) == .disk else {
            return false
        }
        let redactedURL = Self.redactedURLDescription(for: url)
        cache.retrieveImageInDiskCache(forKey: key) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.currentURL == url else { return }
                switch result {
                case let .success(image):
                    guard let image else { return }
                    self.applyLoadedImage(image, from: url)
                case let .failure(error):
                    AppLog.warning(
                        self,
                        "loadCachedFromDisk failed url=\(redactedURL) error=\(error.localizedDescription)"
                    )
                }
            }
        }
        return true
    }

    private func applyLoadedImage(_ image: UIImage, from url: URL) {
        imageView.layer.removeAllAnimations()
        blurView.layer.removeAllAnimations()
        placeholderView.layer.removeAllAnimations()

        imageView.image = image
        previewCoordinator.previewItemURL = makePreviewFileURL(from: image, sourceURL: url)
        onImageLoaded?(url, image)
        imageView.alpha = 1
        blurView.alpha = 0
        placeholderView.alpha = 0
    }

    private func showPlaceholder() {
        imageView.alpha = 0
        blurView.alpha = 0
        placeholderView.alpha = 1
    }

    private func updatePlaceholderSize() {
        let containerSize = bounds.size.width
        guard containerSize > 0 else { return }
        // Symbol point size: container minus padding, capped at 64
        let symbolSize = min(max(containerSize - 16, 12), 64)
        let config = UIImage.SymbolConfiguration(pointSize: symbolSize * 0.45, weight: .light)
        placeholderView.image = UIImage(systemName: placeholderSymbol, withConfiguration: config)
    }

    @objc private func handleTap() {
        guard allowsPreviewOnTap,
              previewCoordinator.previewItemURL != nil,
              let viewController = nearestViewController()
        else {
            return
        }

        let previewController = QLPreviewController()
        previewController.dataSource = previewCoordinator
        viewController.present(previewController, animated: true)
    }

    private func makePreviewFileURL(from image: UIImage?, sourceURL: URL) -> URL? {
        guard let image else {
            return nil
        }

        if let cached = Self.previewFileCache.value(forKey: sourceURL) {
            return cached
        }

        let fileExtension = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let fileName = "am-preview-\(UUID().uuidString).\(fileExtension)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let data: Data? = if fileExtension.lowercased() == "png" {
            image.pngData()
        } else {
            image.jpegData(compressionQuality: 0.98)
        }

        guard let data else {
            AppLog.warning(self, "makePreviewFileURL no data generated")
            return nil
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            Self.previewFileCache.setValue(fileURL, forKey: sourceURL)
            return fileURL
        } catch {
            AppLog.error(self, "makePreviewFileURL write failed error=\(error.localizedDescription)")
            return nil
        }
    }

    private func nearestViewController() -> UIViewController? {
        sequence(first: next) { $0?.next }
            .first { $0 is UIViewController } as? UIViewController
    }

    private static func redactedURLDescription(for url: URL) -> String {
        let host = url.host ?? "local"
        let pathComponent = url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
        return "\(host)/\(pathComponent)"
    }
}

private final class PreviewCoordinator: NSObject, QLPreviewControllerDataSource {
    var previewItemURL: URL?

    func numberOfPreviewItems(in _: QLPreviewController) -> Int {
        previewItemURL == nil ? 0 : 1
    }

    func previewController(_: QLPreviewController, previewItemAt _: Int) -> QLPreviewItem {
        previewItemURL! as NSURL
    }
}
