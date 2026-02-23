//
//  SpeechController.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/23/26.
//

import Foundation
import Combine
import AVFoundation

@MainActor
final class SpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking: Bool = false

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggle(_ text: String) {
        if synth.isSpeaking { stop() }
        else { speak(text) }
    }

    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0.05
        synth.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}

