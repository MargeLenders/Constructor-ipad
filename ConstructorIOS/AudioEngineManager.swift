//
//  AudioEngineManager.swift
//  ConstructorIOS
//
//  Created for Constructor (1997) Native iPadOS Apple Silicon Wrapper.
//  Integración con AVAudioEngine, AVAudioSourceNode y AVAudioSession en tiempo real.
//

import Foundation
import AVFoundation

public enum AudioEngineError: LocalizedError {
    case formatCreationFailed
    case engineStartFailed(error: String)

    public var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "No se pudo instanciar AVAudioFormat para el audio estéreo Float32 a 44.1 kHz."
        case .engineStartFailed(let err):
            return "Fallo al arrancar AVAudioEngine: \(err)"
        }
    }
}

public final class AudioEngineManager: @unchecked Sendable {

    public let engine: AVAudioEngine
    public let ringBuffer: AudioRingBuffer
    private var sourceNode: AVAudioSourceNode?
    public let sampleRate: Double

    // MARK: - Inicialización

    public init(sampleRate: Double = 44100.0, bufferCapacity: UInt32 = 16384) {
        self.sampleRate = sampleRate
        self.engine = AVAudioEngine()
        self.ringBuffer = AudioRingBuffer(capacityFrames: bufferCapacity)
        configureAudioSession()
        setupAudioPipeline()
    }

    // MARK: - Configuración de AVAudioSession para iPadOS

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(sampleRate)
            try session.setActive(true)
        } catch {
            print("⚠️ Advertencia: Error al configurar AVAudioSession: \(error)")
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            stop()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    try? start()
                }
            }
        @unknown default:
            break
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuración de AVAudioSourceNode y Conexiones

    private func setupAudioPipeline() {
        let ring = self.ringBuffer

        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)

            guard abl.count >= 2,
                  let leftBuffer = abl[0].mData?.assumingMemoryBound(to: Float32.self),
                  let rightBuffer = abl[1].mData?.assumingMemoryBound(to: Float32.self) else {
                return noErr
            }

            ring.read(intoLeft: leftBuffer, right: rightBuffer, frames: Int(frameCount))
            return noErr
        }
        self.sourceNode = node

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            fatalError("Error crítico al crear el formato de audio para AVAudioSourceNode.")
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: sourceFormat)
    }

    // MARK: - Enlace con LibretroCore

    public func attach(to core: LibretroCore) {
        let ring = self.ringBuffer

        core.onAudioBatch = { interleavedData, frames in
            ring.write(interleavedData: interleavedData, frames: frames)
            return frames
        }

        core.onAudioSample = { left, right in
            ring.writeSample(left: left, right: right)
        }
    }

    // MARK: - Control de Reproducción

    public func start() throws {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            throw AudioEngineError.engineStartFailed(error: error.localizedDescription)
        }
    }

    public func stop() {
        guard engine.isRunning else { return }
        engine.pause()
    }

    public func reset() {
        stop()
        ringBuffer.reset()
    }

    public var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0.0, min(1.0, newValue)) }
    }
}
