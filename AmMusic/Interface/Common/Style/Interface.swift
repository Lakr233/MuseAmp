//
//  Interface.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

enum Interface {
    static let interruptibleOptions: UIView.AnimationOptions = [
        .beginFromCurrentState, .allowUserInteraction,
    ]

    static let interruptibleKeyframeOptions: UIView.KeyframeAnimationOptions = [
        .beginFromCurrentState, .allowUserInteraction, .calculationModeCubic,
    ]

    // MARK: - Spring Animations

    static func springAnimate(
        duration: TimeInterval = 0.5,
        dampingRatio: CGFloat = 1.0,
        initialVelocity: CGFloat = 1.0,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil,
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: dampingRatio,
            initialSpringVelocity: initialVelocity,
            options: interruptibleOptions.union(.curveEaseInOut),
            animations: animations,
            completion: completion,
        )
    }

    static func smoothSpringAnimate(
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil,
    ) {
        UIView.animate(
            withDuration: 1.0,
            delay: 0,
            usingSpringWithDamping: 1.05,
            initialSpringVelocity: 0.75,
            options: interruptibleOptions.union(.curveEaseInOut),
            animations: animations,
            completion: completion,
        )
    }

    static func bounceAnimate(
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil,
    ) {
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 1.0,
            options: interruptibleOptions,
            animations: animations,
            completion: completion,
        )
    }

    // MARK: - Standard Animations

    static func animate(
        duration: TimeInterval,
        delay: TimeInterval = 0,
        options: UIView.AnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil,
    ) {
        UIView.animate(
            withDuration: duration,
            delay: delay,
            options: interruptibleOptions.union(options),
            animations: animations,
            completion: completion,
        )
    }

    static func quickAnimate(
        duration: TimeInterval = 0.2,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil,
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: interruptibleOptions,
            animations: animations,
            completion: completion,
        )
    }

    // MARK: - Transition Animation

    static func transition(
        with view: UIView,
        duration: TimeInterval,
        options: UIView.AnimationOptions = .transitionCrossDissolve,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil,
    ) {
        UIView.transition(
            with: view,
            duration: duration,
            options: interruptibleOptions.union(options),
            animations: animations,
            completion: completion,
        )
    }

    // MARK: - Keyframe Animation

    static func keyframeAnimate(
        duration: TimeInterval,
        options: UIView.KeyframeAnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil,
    ) {
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0,
            options: interruptibleKeyframeOptions.union(options),
            animations: animations,
            completion: completion,
        )
    }
}
