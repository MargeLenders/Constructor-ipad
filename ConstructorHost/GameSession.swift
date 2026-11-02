//
//  GameSession.swift
//  ConstructorHost
//
//  Created for Constructor (1997) Native macOS Apple Silicon Wrapper.
//  Orquestador principal: coordina el ciclo de vida, el bucle de emulación a 60 fps
//  en hilo dedicado, y la interconexión entre Core, Metal, Audio e Input.
//

import Cocoa
import Metal
import Combine

public final class GameSession: ObservableObject, @unchecked Sendable {

    // MARK: - Componentes del Sistema
    public let core: LibretroCore
    public let renderer: MetalRenderer
    public let audioManager: AudioEngineManager
    public let inputManager: InputManager

    // MARK: - Estado del Bucle de Emulación
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isPaused: Bool = false

    private let emulationQueue = DispatchQueue(label: "com.constructormac.emulation", qos: .userInteractive)
    private var shouldStopEmulation: Bool = false
    private let stateLock = NSLock()

    // MARK: - Inicialización

    public init(dylibURL: URL, gameZipURL: URL) throws {
        // 1. Instanciar dispositivo Metal y Renderizador
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Apple Silicon Metal device no disponible.")
        }
        self.renderer = try MetalRenderer(device: defaultDevice)

        // 2. Instanciar Gestor de Entrada
        self.inputManager = InputManager()

        // 3. Instanciar Gestor de Audio
        self.audioManager = AudioEngineManager(sampleRate: 44100.0)

        // 4. Instanciar Núcleo Libretro
        self.core = try LibretroCore(dylibPath: dylibURL.path)

        // 5. Interconectar Subsistemas
        setupSubsystemBindings()

        // 6. Montar el juego Constructor.zip
        try core.loadGame(at: gameZipURL)
    }

    /// Conveniencia para inicializar buscando recursos en el Bundle principal
    public convenience init() throws {
        guard let dylibURL = Bundle.main.url(forResource: "dosbox_pure_libretro", withExtension: "dylib") ??
              Bundle.main.url(forResource: "dosbox_pure_libretro", withExtension: "dylib", subdirectory: "Frameworks") else {
            throw LibretroError.libraryNotFound(path: "dosbox_pure_libretro.dylib en Bundle.main")
        }

        guard let gameZipURL = Bundle.main.url(forResource: "Constructor", withExtension: "zip") else {
            throw LibretroError.gameFileNotFound(name: "Constructor.zip en Bundle.main")
        }

        try self.init(dylibURL: dylibURL, gameZipURL: gameZipURL)
    }

    // MARK: - Enlace de Subsistemas

    private func setupSubsystemBindings() {
        // Vídeo: Volcar los fotogramas de CPU a MetalRenderer
        let metalRenderer = self.renderer
        core.onVideoFrame = { data, width, height, pitch in
            metalRenderer.updateFrame(data: data, width: width, height: height, pitch: pitch)
        }

        // Geometría: Adaptar aspect ratio si cambia dinámicamente
        core.onGeometryChanged = { geom in
            if geom.aspect_ratio > 0 {
                metalRenderer.targetAspectRatio = Float(geom.aspect_ratio)
            }
        }

        // Audio: Enlazar lotes de muestras con el RingBuffer
        audioManager.attach(to: core)

        // Entrada: Enlazar teclado y ratón
        inputManager.attach(to: core)

        // Apagado
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

        // Iniciar el motor de audio CoreAudio
        try audioManager.start()

        // Lanzar bucle de emulación sincronizado en tiempo real
        emulationQueue.async { [weak self] in
            self?.runEmulationLoop()
        }
    }

    public func pause() {
        stateLock.lock()
        defer { stateLock.unlock() }
        isPaused = true
        audioManager.pause()
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
        inputManager.releaseMouse()
    }

    // MARK: - Bucle de Tiempo Preciso a 60 FPS

    private func runEmulationLoop() {
        // Duración objetivo de 1 frame: 1 / 60.0 segundos = 16,666,666 nanosegundos
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
                // Ejecución síncrona del fotograma de emulación
                core.runFrame()
            }

            // Cálculo de tiempo para el siguiente fotograma
            nextFrameTime += nanosToMach(targetFrameDurationNs)
            let currentTime = mach_absolute_time()

            if nextFrameTime > currentTime {
                let waitNanos = machToNanos(nextFrameTime - currentTime)
                // Dormir con precisión de microsegundos si hay tiempo suficiente
                if waitNanos > 1_000_000 { // más de 1 ms
                    usleep(useconds_t((waitNanos - 500_000) / 1000))
                }
                // Espera activa (spin) los últimos microsegundos para precisión absoluta
                while mach_absolute_time() < nextFrameTime {
                    // spin lock corto
                }
            } else {
                // Si el emulador se retrasa más de 2 frames (por ejemplo por suspensión de pantalla),
                // resincronizar el tiempo base para no acelerar de golpe
                if currentTime - nextFrameTime > nanosToMach(targetFrameDurationNs * 2) {
                    nextFrameTime = currentTime
                }
            }
        }
    }
}
