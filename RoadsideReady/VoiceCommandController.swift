import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class VoiceCommandController: NSObject, ObservableObject {
    enum Command { case next, back, stop, repeatStep }
    
    @Published private(set) var isListening: Bool = false
    @Published private(set) var transcript: String = ""
    @Published private(set) var lastError: String? = nil
    
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    private var onCommand: ((Command) -> Void)?
    private var lastFireAt: Date = .distantPast
    
    func start(onCommand: @escaping (Command) -> Void) {
        self.onCommand = onCommand
        lastError = nil
        
        guard !isListening else { return }
        guard let recognizer else { lastError = "Speech recognizer unavailable"; return }
        guard recognizer.isAvailable else { lastError = "Speech recognizer not available right now"; return }
        
        requestPermissions { [weak self] ok in
            guard let self else { return }
            Task { @MainActor in
                guard ok else { self.lastError = "Speech or microphone permission denied"; return }
                do { try self.startSession() }
                catch { self.lastError = "Voice control failed to start"; self.stop() }
            }
        }
    }
    
    func stop() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        
        isListening = false
        transcript = ""
        
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { }
    }
    
    private func requestPermissions(_ completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { micOK in
            guard micOK else { DispatchQueue.main.async { completion(false) }; return }
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { completion(status == .authorized) }
            }
        }
    }
    
    private func startSession() throws {
        stop()
        
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        self.request = request
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
        
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in self.lastError = error.localizedDescription; self.stop() }
                return
            }
            guard let result else { return }
            
            Task { @MainActor in
                self.transcript = result.bestTranscription.formattedString
                self.maybeFireCommand(from: self.transcript, isFinal: result.isFinal)
            }
        }
    }
    
    private func maybeFireCommand(from raw: String, isFinal: Bool) {
        guard isFinal else { return }
        let now = Date()
        if now.timeIntervalSince(lastFireAt) < 1.0 { return } // debounce
        
        let t = raw.lowercased()
        
        if t.contains("stop voice") || t.contains("voice control off") || t.contains("stop listening") {
            lastFireAt = now; onCommand?(.stop); return
        }
        if t.contains("go back") || t.contains("back") || t.contains("previous") {
            lastFireAt = now; onCommand?(.back); return
        }
        if t.contains("next") || t.contains("continue") || t.contains("proceed") {
            lastFireAt = now; onCommand?(.next); return
        }
        if t.contains("repeat") || t.contains("say again") {
            lastFireAt = now; onCommand?(.repeatStep); return
        }
    }
}
//
//  VoiceCommandController.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/28/26.
//


