//
//  SpeechController.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/23/26.
//

import Foundation
import Combine
import AVFoundation

final class SpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking: Bool = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    @MainActor
    func toggle(_ text: String) {
        if synth.isSpeaking { stop() }
        else { speak(text) }
    }

    @MainActor
    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0.05
        synth.speak(utterance)
        isSpeaking = true
    }

    @MainActor
    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // Delegate callbacks may arrive off-main; hop to main before touching @Published.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

