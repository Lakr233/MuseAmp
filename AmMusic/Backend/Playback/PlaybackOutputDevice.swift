//
//  PlaybackOutputDevice.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AVFoundation
import Foundation

nonisolated struct PlaybackOutputDevice: Equatable {
    enum Kind: Equatable {
        case builtInSpeaker
        case builtInReceiver
        case wiredHeadphones
        case bluetooth
        case airPlay
        case carAudio
        case television
        case external
        case unknown
    }

    let name: String
    let kind: Kind
}

extension PlaybackOutputDevice {
    #if os(iOS) || os(tvOS) || os(watchOS)
        init?(currentRoute route: AVAudioSessionRouteDescription) {
            guard let output = route.outputs.first else {
                return nil
            }
            self.init(port: output)
        }

        init(port: AVAudioSessionPortDescription) {
            let trimmedName = port.portName.trimmingCharacters(in: .whitespacesAndNewlines)
            name = trimmedName.isEmpty ? String(localized: "Audio Output") : trimmedName
            kind = Self.kind(for: port.portType)
        }

        private static func kind(for portType: AVAudioSession.Port) -> Kind {
            switch portType {
            case .builtInSpeaker:
                .builtInSpeaker
            case .builtInReceiver:
                .builtInReceiver
            case .headphones, .headsetMic:
                .wiredHeadphones
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                .bluetooth
            case .airPlay:
                .airPlay
            case .carAudio:
                .carAudio
            case .displayPort:
                .television
            case .lineOut, .usbAudio:
                .external
            default:
                portType.rawValue == "HDMI" ? .television : .unknown
            }
        }
    #endif
}
