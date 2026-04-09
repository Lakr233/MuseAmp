import UIKit

enum InterfaceAnimation {
    // MARK: - Spring Animations

    static func springAnimate(
        duration: TimeInterval = 0.5,
        dampingRatio: CGFloat = 1.0,
        initialVelocity: CGFloat = 1.0,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: dampingRatio,
            initialSpringVelocity: initialVelocity,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }

    static func smoothSpringAnimate(
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: 1.0,
            delay: 0,
            usingSpringWithDamping: 1.05,
            initialSpringVelocity: 0.75,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }

    static func bounceAnimate(
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 1.0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }

    // MARK: - Standard Animations

    static func animate(
        duration: TimeInterval,
        delay: TimeInterval = 0,
        options: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: options,
            animations: animations,
            completion: completion
        )
    }

    static func quickAnimate(
        duration: TimeInterval = 0.2,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }

    // MARK: - Keyframe Animation

    static func keyframeAnimate(
        duration: TimeInterval,
        options: UIView.KeyframeAnimationOptions = [.beginFromCurrentState, .calculationModeCubic],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0,
            options: options,
            animations: animations,
            completion: completion
        )
    }
}
