//
//  GameSession.swift
//  ConstructorIOS
//
//  Created for Constructor (1997) Native iPadOS Apple Silicon Wrapper.
//  Orquestador principal: coordina el ciclo de vida, el bucle de emulación a 60 fps
//  en hilo dedicado, y la interconexión entre Core, Metal, Audio e Input táctil directo.
//

import UIKit
import Metal
import Combine

public final class GameSession: ObservableObject, @unchecked Sendable {

    // MARK: - Componentes del Sistema
    public let core: LibretroCore
    public let renderer: MetalRenderer
    public let audioManager: AudioEngineManager
    public let inputManager: InputManager_iOS

    // MARK: - Estado del Bucle de Emulación
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isPaused: Bool = false

    private let emulationQueue = DispatchQueue(label: "com.constructor.emulation", qos: .userInteractive)
    private var shouldStopEmulation: Bool = false
    private let stateLock = NSLock()

    // MARK: - Inicialización

    public init(dylibURL: URL, gameZipURL: URL) throws {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Apple Silicon Metal device no disponible.")
        }
        self.renderer = try MetalRenderer(device: defaultDevice)
        self.inputManager = InputManager_iOS()
        self.audioManager = AudioEngineManager(sampleRate: 44100.0)
        self.core = try LibretroCore(dylibPath: dylibURL.path)

        setupSubsystemBindings()
        try core.loadGame(at: gameZipURL)
    }

    public convenience init() throws {
        guard let dylibURL = Bundle.main.url(forResource: "dosbox_pure_libretro_ios", withExtension: "dylib") ??
              Bundle.main.url(forResource: "dosbox_pure_libretro_ios", withExtension: "dylib", subdirectory: "Frameworks") else {
            throw LibretroError.libraryNotFound(path: "dosbox_pure_libretro_ios.dylib en Bundle.main")
        }

        guard let gameZipURL = Bundle.main.url(forResource: "Constructor", withExtension: "zip") else {
            throw LibretroError.gameFileNotFound(name: "Constructor.zip en Bundle.main")
        }

        try self.init(dylibURL: dylibURL, gameZipURL: gameZipURL)
    }

    // MARK: - Enlace de Subsistemas

    private func setupSubsystemBindings() {
        let metalRenderer = self.renderer
        core.onVideoFrame = { data, width, height, pitch in
            metalRenderer.updateFrame(data: data, width: width, height: height, pitch: pitch)
        }

        let inputMgr = self.inputManager
        core.onGeometryChanged = { geom in
            if geom.aspect_ratio > 0 {
                let aspect = Float(geom.aspect_ratio)
                metalRenderer.targetAspectRatio = aspect
                inputMgr.updateViewport(targetAspect: aspect)
            }
        }

        audioManager.attach(to: core)
        inputManager.attach(to: core)

        core.onShutdown = { [weak self] in
            DispatchQueue.main.async {
                self?.stop()
            }
        }
    }

    // MARK: - Control de Ejecución (Bucle a 60 FPS)

    public func start() throws {
        stateLock.lock()
        guard !isRunning else {
            stateLock.unlock()
            return
        }
        isRunning = true
        isPaused = false
        shouldStopEmulation = false
        stateLock.unlock()

        try audioManager.start()

        emulationQueue.async { [weak self] in
            self?.runEmulationLoop()
        }
    }

    public func pause() {
        stateLock.lock()
        defer { stateLock.unlock() }
        isPaused = true
        audioManager.stop()
    }

    public func resume() {
        stateLock.lock()
        defer { stateLock.unlock() }
        isPaused = false
        try? audioManager.start()
    }

    public func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    public func reset() {
        core.reset()
        audioManager.ringBuffer.reset()
    }

    public func stop() {
        stateLock.lock()
        shouldStopEmulation = true
        isRunning = false
        isPaused = false
        stateLock.unlock()

        audioManager.stop()
    }

    // MARK: - Bucle de Tiempo Preciso a 60 FPS

    private func runEmulationLoop() {
        let targetFrameDurationNs: UInt64 = 1_000_000_000 / 60

        var timebaseInfo = mach_timebase_info()
        mach_timebase_info(&timebaseInfo)

        func machToNanos(_ machTime: UInt64) -> UInt64 {
            return machTime * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        }

        func nanosToMach(_ nanos: UInt64) -> UInt64 {
            return nanos * UInt64(timebaseInfo.denom) / UInt64(timebaseInfo.numer)
        }

        var nextFrameTime = mach_absolute_time()

        while true {
            stateLock.lock()
            let stop = shouldStopEmulation
            let paused = isPaused
            stateLock.unlock()

            if stop { break }

            if !paused {
                core.runFrame()
            }

            nextFrameTime += nanosToMach(targetFrameDurationNs)
            let currentTime = mach_absolute_time()

            if nextFrameTime > currentTime {
                let waitNanos = machToNanos(nextFrameTime - currentTime)
                if waitNanos > 1_000_000 {
                    usleep(useconds_t((waitNanos - 500_000) / 1000))
                }
                while mach_absolute_time() < nextFrameTime {
                    // spin lock corto
                }
            } else {
                if currentTime - nextFrameTime > nanosToMach(targetFrameDurationNs * 2) {
                    nextFrameTime = currentTime
                }
            }
        }
    }
}
