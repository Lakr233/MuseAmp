//
//  AmImageView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Kingfisher
import SnapKit
import Then
import UIKit

/// Reusable artwork view with centered SF Symbol placeholder.
class AmImageView: UIView {
    // MARK: - Subviews

    let imageView = UIImageView().then {
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

    // MARK: - State

    var currentURL: URL?
    var loadID: UInt = 0
    let previewCoordinator = PreviewCoordinator()
    private var isShimmerActive = false
    private static let shimmerAnimationKey = "amImageView.shimmer"

    var allowsPreviewOnTap = false {
        didSet {
            tapGestureRecognizer.isEnabled = allowsPreviewOnTap
            imageView.isUserInteractionEnabled = allowsPreviewOnTap
        }
    }

    var onImageLoaded: (URL, UIImage) -> Void = { _, _ in } {
        didSet {
            guard let currentURL, let image = imageView.image else { return }
            onImageLoaded(currentURL, image)
        }
    }

    private var placeholderSymbol: String = "music.note"
    private let tapGestureRecognizer = UITapGestureRecognizer()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePlaceholderSize()
    }

    // MARK: - Public API

    func configure(placeholder: String, cornerRadius: CGFloat) {
        placeholderSymbol = placeholder
        layer.cornerRadius = cornerRadius
        imageView.layer.cornerRadius = cornerRadius
        updatePlaceholderSize()
        if imageView.image == nil, currentURL == nil {
            showPlaceholderState()
        }
    }

    func setImage(_ image: UIImage) {
        invalidateCurrentLoad()
        currentURL = nil
        imageView.image = image
        showImageState()
    }

    func reset() {
        invalidateCurrentLoad()
        currentURL = nil
        imageView.image = nil
        showPlaceholderState()
        previewCoordinator.clear()
    }

    // MARK: - Display State

    func showImageState() {
        stopLoadingShimmer()
        imageView.layer.removeAllAnimations()
        blurView.layer.removeAllAnimations()
        placeholderView.layer.removeAllAnimations()
        imageView.alpha = 1
        blurView.alpha = 0
        placeholderView.alpha = 0
    }

    func showPlaceholderState() {
        stopLoadingShimmer()
        imageView.alpha = 0
        blurView.alpha = 0
        placeholderView.alpha = 1
    }

    func invalidateCurrentLoad() {
        loadID &+= 1
        imageView.kf.cancelDownloadTask()
    }

    // MARK: - Loading Shimmer

    func startLoadingShimmer() {
        guard !isShimmerActive else { return }
        isShimmerActive = true
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = UIColor.secondarySystemFill.cgColor
        anim.toValue = UIColor.tertiarySystemFill.cgColor
        anim.duration = 0.8
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: Self.shimmerAnimationKey)
    }

    func stopLoadingShimmer() {
        guard isShimmerActive else { return }
        isShimmerActive = false
        layer.removeAnimation(forKey: Self.shimmerAnimationKey)
    }

    // MARK: - Private

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

    private func updatePlaceholderSize() {
        let containerSize = bounds.size.width
        guard containerSize > 0 else { return }
        let symbolSize = min(max(containerSize - 16, 12), 64)
        let config = UIImage.SymbolConfiguration(pointSize: symbolSize * 0.45, weight: .light)
        placeholderView.image = UIImage(systemName: placeholderSymbol, withConfiguration: config)
    }
}
