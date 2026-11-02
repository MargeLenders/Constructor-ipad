//
//  LibretroCore.swift
//  ConstructorHost
//
//  Created for Constructor (1997) Native macOS Apple Silicon Wrapper.
//  Implements Phase 1 (Core Loader & Bridging) and Phase 2 (Environment & Game Load).
//

import Foundation
import Darwin

// MARK: - Libretro Error Definitions

public enum LibretroError: LocalizedError {
    case libraryNotFound(path: String)
    case dynamicLoadingFailed(message: String)
    case symbolNotFound(name: String, error: String)
    case coreAlreadyRunning
    case coreNotInitialized
    case gameFileNotFound(name: String)
    case gameLoadFailed(path: String)
    case pixelFormatRejected
    case directoryCreationFailed(path: String, error: String)

    public var errorDescription: String? {
        switch self {
        case .libraryNotFound(let path):
            return "Dynamic library (.dylib) not found at path: \(path)"
        case .dynamicLoadingFailed(let msg):
            return "dlopen failed to load the core library: \(msg)"
        case .symbolNotFound(let name, let err):
            return "Required Libretro C symbol '\(name)' could not be resolved via dlsym: \(err)"
        case .coreAlreadyRunning:
            return "An active Libretro core is already running in this process."
        case .coreNotInitialized:
            return "The Libretro core has not been initialized."
        case .gameFileNotFound(let name):
            return "Game payload archive '\(name)' was not found in the application bundle or disk."
        case .gameLoadFailed(let path):
            return "retro_load_game failed: The core rejected loading the payload at '\(path)'."
        case .pixelFormatRejected:
            return "The core rejected the required RETRO_PIXEL_FORMAT_XRGB8888 video format."
        case .directoryCreationFailed(let path, let err):
            return "Failed to prepare storage directory at '\(path)': \(err)"
        }
    }
}

// MARK: - C Function Signatures (libretro.h C-ABI)

private typealias RetroInitFn = @convention(c) () -> Void
private typealias RetroDeinitFn = @convention(c) () -> Void
private typealias RetroAPIVersionFn = @convention(c) () -> UInt32
private typealias RetroGetSystemInfoFn = @convention(c) (UnsafeMutablePointer<retro_system_info>) -> Void
private typealias RetroGetSystemAVInfoFn = @convention(c) (UnsafeMutablePointer<retro_system_av_info>) -> Void
private typealias RetroSetEnvironmentFn = @convention(c) (retro_environment_t) -> Void
private typealias RetroSetVideoRefreshFn = @convention(c) (retro_video_refresh_t) -> Void
private typealias RetroSetAudioSampleFn = @convention(c) (retro_audio_sample_t) -> Void
private typealias RetroSetAudioSampleBatchFn = @convention(c) (retro_audio_sample_batch_t) -> Void
private typealias RetroSetInputPollFn = @convention(c) (retro_input_poll_t) -> Void
private typealias RetroSetInputStateFn = @convention(c) (retro_input_state_t) -> Void
private typealias RetroResetFn = @convention(c) () -> Void
private typealias RetroRunFn = @convention(c) () -> Void
private typealias RetroLoadGameFn = @convention(c) (UnsafePointer<retro_game_info>) -> Bool
private typealias RetroUnloadGameFn = @convention(c) () -> Void

// MARK: - Static C-ABI Trampolines
//
// libretro.h callbacks do NOT provide a `void *userdata` context pointer.
// Therefore, we route C function pointer calls to the active Swift instance
// through a global weak reference. In Swift 5.10 / Swift 6, `nonisolated(unsafe)`
// is used to bypass strict actor-isolation checks on the static pointer.

private func coreEnvironmentCallback(cmd: UInt32, data: UnsafeMutableRawPointer?) -> Bool {
    guard let core = LibretroCore.activeInstance else { return false }
    return core.handleEnvironment(cmd: cmd, data: data)
}

private func coreVideoRefreshCallback(data: UnsafeRawPointer?, width: UInt32, height: UInt32, pitch: Int) {
    guard let core = LibretroCore.activeInstance else { return }
    core.handleVideoRefresh(data: data, width: Int(width), height: Int(height), pitch: pitch)
}

private func coreAudioSampleCallback(left: Int16, right: Int16) {
    guard let core = LibretroCore.activeInstance else { return }
    core.handleAudioSample(left: left, right: right)
}

private func coreAudioSampleBatchCallback(data: UnsafePointer<Int16>?, frames: Int) -> Int {
    guard let core = LibretroCore.activeInstance, let data = data else { return 0 }
    return core.handleAudioSampleBatch(data: data, frames: frames)
}

private func coreInputPollCallback() {
    guard let core = LibretroCore.activeInstance else { return }
    core.handleInputPoll()
}

private func coreInputStateCallback(port: UInt32, device: UInt32, index: UInt32, id: UInt32) -> Int16 {
    guard let core = LibretroCore.activeInstance else { return 0 }
    return core.handleInputState(port: port, device: device, index: index, id: id)
}

// MARK: - LibretroCore Implementation

public final class LibretroCore: @unchecked Sendable {

    /// Global weak pointer allowing @convention(c) static callbacks to route back to this instance.
    nonisolated(unsafe) fileprivate static weak var activeInstance: LibretroCore?

    // MARK: Dynamic Library & Resolved Symbols
    private var dylibHandle: UnsafeMutableRawPointer?

    private var retroInit: RetroInitFn!
    private var retroDeinit: RetroDeinitFn!
    private var retroAPIVersion: RetroAPIVersionFn!
    private var retroGetSystemInfo: RetroGetSystemInfoFn!
    private var retroGetSystemAVInfo: RetroGetSystemAVInfoFn!
    private var retroSetEnvironment: RetroSetEnvironmentFn!
    private var retroSetVideoRefresh: RetroSetVideoRefreshFn!
    private var retroSetAudioSample: RetroSetAudioSampleFn!
    private var retroSetAudioSampleBatch: RetroSetAudioSampleBatchFn!
    private var retroSetInputPoll: RetroSetInputPollFn!
    private var retroSetInputState: RetroSetInputStateFn!
    private var retroReset: RetroResetFn!
    private var retroRun: RetroRunFn!
    private var retroLoadGame: RetroLoadGameFn!
    private var retroUnloadGame: RetroUnloadGameFn!

    // MARK: Core State
    public private(set) var systemInfo = retro_system_info()
    public private(set) var systemAVInfo = retro_system_av_info()
    public private(set) var pixelFormat: retro_pixel_format = RETRO_PIXEL_FORMAT_0RGB1555
    public private(set) var isGameLoaded: Bool = false
    public private(set) var isInitialized: Bool = false

    // MARK: Persistent C-String Storage
    // libretro cores require pointer stability: C-strings returned to RETRO_ENVIRONMENT_GET_VARIABLE,
    // RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY, and RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY must remain valid
    // in memory permanently across calls. We pre-allocate them using POSIX strdup() and deallocate on deinit.
    private var cVariablePointers: [String: UnsafeMutablePointer<CChar>] = [:]
    private var systemDirectoryCString: UnsafeMutablePointer<CChar>?
    private var saveDirectoryCString: UnsafeMutablePointer<CChar>?

    // MARK: Keyboard Callback (para núcleos como DOSBox-Pure que registran retro_keyboard_callback)
    public private(set) var keyboardCallback: retro_keyboard_event_t?

    public func sendKeyEvent(down: Bool, keycode: UInt32, character: UInt32 = 0, keyModifiers: UInt16 = 0) {
        keyboardCallback?(down, keycode, character, keyModifiers)
    }

    // MARK: Consumer Hooks for Video, Audio, Input & Lifecycle
    public var onVideoFrame: ((_ data: UnsafeRawPointer?, _ width: Int, _ height: Int, _ pitch: Int) -> Void)?
    public var onAudioBatch: ((_ data: UnsafePointer<Int16>, _ frames: Int) -> Int)?
    public var onAudioSample: ((_ left: Int16, _ right: Int16) -> Void)?
    public var onInputPoll: (() -> Void)?
    public var onInputState: ((_ port: UInt32, _ device: UInt32, _ index: UInt32, _ id: UInt32) -> Int16)?
    public var onGeometryChanged: ((_ geometry: retro_game_geometry) -> Void)?
    public var onShutdown: (() -> Void)?

    // MARK: - Initialization & Lifecycle

    /// Convenience initializer locating the dynamic library within the specified bundle.
    public convenience init(bundleDylibNamed name: String = "dosbox_pure_libretro", in bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: name, withExtension: "dylib") else {
            throw LibretroError.libraryNotFound(path: "\(name).dylib inside bundle \(bundle.bundlePath)")
        }
        try self.init(dylibPath: url.path)
    }

    /// Primary initializer: opens the dynamic library, binds symbols, configures directories and variables.
    public init(dylibPath: String) throws {
        // Enforce singleton constraint inherent to Libretro cores (which use C static variables internally)
        if LibretroCore.activeInstance != nil {
            throw LibretroError.coreAlreadyRunning
        }

        try setupStorageDirectories()
        setupDefaultCoreVariables()

        try loadDylib(at: dylibPath)
        try resolveLibretroSymbols()

        // Register this instance as the active receiver for C-ABI callbacks
        LibretroCore.activeInstance = self

        // Negotiate environment callback before retro_init
        retroSetEnvironment(coreEnvironmentCallback)

        // Initialize core internal state
        retroInit()
        self.isInitialized = true

        // Read core system metadata (name, version, supported extensions)
        var sysInfo = retro_system_info()
        retroGetSystemInfo(&sysInfo)
        self.systemInfo = sysInfo

        // Register remaining subsystem callbacks
        retroSetVideoRefresh(coreVideoRefreshCallback)
        retroSetAudioSample(coreAudioSampleCallback)
        retroSetAudioSampleBatch(coreAudioSampleBatchCallback)
        retroSetInputPoll(coreInputPollCallback)
        retroSetInputState(coreInputStateCallback)
    }

    deinit {
        if isGameLoaded {
            unloadGame()
        }
        if isInitialized {
            retroDeinit()
        }
        if LibretroCore.activeInstance === self {
            LibretroCore.activeInstance = nil
        }
        if let handle = dylibHandle {
            dlclose(handle)
        }

        // Free all heap-allocated C-strings
        for (_, ptr) in cVariablePointers {
            free(ptr)
        }
        cVariablePointers.removeAll()

        if let ptr = systemDirectoryCString {
            free(ptr)
            systemDirectoryCString = nil
        }
        if let ptr = saveDirectoryCString {
            free(ptr)
            saveDirectoryCString = nil
        }
    }

    // MARK: - Directory Setup (Application Support)

    private func setupStorageDirectories() throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LibretroError.directoryCreationFailed(path: "Application Support", error: "User directory unavailable")
        }

        let baseDir = appSupport.appendingPathComponent("ConstructorMac", isDirectory: true)
        let sysDir = baseDir.appendingPathComponent("system", isDirectory: true)
        let saveDir = baseDir.appendingPathComponent("saves", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: sysDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        } catch {
            throw LibretroError.directoryCreationFailed(path: baseDir.path, error: error.localizedDescription)
        }

        // Duplicate POSIX paths into stable C memory
        self.systemDirectoryCString = strdup(sysDir.path)
        self.saveDirectoryCString = strdup(saveDir.path)
    }

    // MARK: - DOSBox-Pure Variable Configuration
    // Injects required variables to guarantee zero emulator friction.
    // - dosbox_pure_menu_time = "disabled": suppresses the interactive boot menu entirely.
    // - dosbox_pure_force60fps = "true": forces standard 60 Hz timing, avoiding 70 Hz DOS VGA stutter on macOS.
    // - dosbox_pure_cycles = "max": emulates high-speed Pentium CPU for smooth 640x480 SVGA simulation.
    // - dosbox_pure_svga = "svga_s3": configures S3 Trio64 chipset used by Constructor.
    // - dosbox_pure_mouse_input = "direct": native relative/absolute mouse mode without synthetic smoothing.
    // - dosbox_pure_conf = "inside": keeps configuration encapsulated.

    private func setupDefaultCoreVariables() {
        let defaults: [String: String] = [
            "dosbox_pure_menu_time": "0",
            "dosbox_pure_force60fps": "true",
            "dosbox_pure_cycles": "max",
            "dosbox_pure_svga": "svga_s3",
            "dosbox_pure_mouse_input": "direct",
            "dosbox_pure_bootos": "disabled",
            "dosbox_pure_auto_mapping": "false",
            "dosbox_pure_aspect": "true",
            "dosbox_pure_conf": "inside"
        ]

        for (key, value) in defaults {
            setCoreVariable(key: key, value: value)
        }
    }

    /// Stores a core variable as a persistent, null-terminated C string in heap memory.
    public func setCoreVariable(key: String, value: String) {
        if let existing = cVariablePointers[key] {
            free(existing)
        }
        cVariablePointers[key] = strdup(value)
    }

    // MARK: - Dynamic Library Loading & Symbol Resolution

    private func loadDylib(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw LibretroError.libraryNotFound(path: path)
        }

        // Clear any previous dynamic linker error
        dlerror()

        // RTLD_NOW binds all symbols immediately; RTLD_LOCAL avoids polluting global process namespace
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let errorMsg = dlerror().flatMap { String(cString: $0) } ?? "Unknown dynamic linker error"
            throw LibretroError.dynamicLoadingFailed(message: errorMsg)
        }

        self.dylibHandle = handle
    }

    private func resolveSymbol<T>(_ name: String) throws -> T {
        guard let handle = dylibHandle else {
            throw LibretroError.dynamicLoadingFailed(message: "Library handle is null")
        }

        dlerror()
        guard let sym = dlsym(handle, name) else {
            let errorMsg = dlerror().flatMap { String(cString: $0) } ?? "Symbol not exported"
            throw LibretroError.symbolNotFound(name: name, error: errorMsg)
        }

        return unsafeBitCast(sym, to: T.self)
    }

    private func resolveLibretroSymbols() throws {
        self.retroInit = try resolveSymbol("retro_init")
        self.retroDeinit = try resolveSymbol("retro_deinit")
        self.retroAPIVersion = try resolveSymbol("retro_api_version")
        self.retroGetSystemInfo = try resolveSymbol("retro_get_system_info")
        self.retroGetSystemAVInfo = try resolveSymbol("retro_get_system_av_info")
        self.retroSetEnvironment = try resolveSymbol("retro_set_environment")
        self.retroSetVideoRefresh = try resolveSymbol("retro_set_video_refresh")
        self.retroSetAudioSample = try resolveSymbol("retro_set_audio_sample")
        self.retroSetAudioSampleBatch = try resolveSymbol("retro_set_audio_sample_batch")
        self.retroSetInputPoll = try resolveSymbol("retro_set_input_poll")
        self.retroSetInputState = try resolveSymbol("retro_set_input_state")
        self.retroReset = try resolveSymbol("retro_reset")
        self.retroRun = try resolveSymbol("retro_run")
        self.retroLoadGame = try resolveSymbol("retro_load_game")
        self.retroUnloadGame = try resolveSymbol("retro_unload_game")
    }

    // MARK: - Game Loading (Constructor.zip)

    /// Loads Constructor from the application bundle.
    public func loadGame(named resourceName: String = "Constructor", extension ext: String = "zip", in bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: resourceName, withExtension: ext) else {
            throw LibretroError.gameFileNotFound(name: "\(resourceName).\(ext)")
        }
        try loadGame(at: url)
    }

    /// Mounts and runs the game payload from an archive file URL.
    public func loadGame(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LibretroError.gameFileNotFound(name: url.lastPathComponent)
        }

        guard isInitialized else {
            throw LibretroError.coreNotInitialized
        }

        var gameInfo = retro_game_info()
        let pathString = url.path

        let success = pathString.withCString { cPath -> Bool in
            gameInfo.path = cPath
            gameInfo.data = nil
            gameInfo.size = 0
            gameInfo.meta = nil
            return retroLoadGame(&gameInfo)
        }

        guard success else {
            throw LibretroError.gameLoadFailed(path: url.path)
        }

        // Retrieve negotiated video geometry and audio timing parameters
        var avInfo = retro_system_av_info()
        retroGetSystemAVInfo(&avInfo)
        self.systemAVInfo = avInfo
        self.isGameLoaded = true
    }

    // MARK: - Emulation Step & Control

    /// Executes a single emulation frame (advances video, triggers audio batches, polls input).
    public func runFrame() {
        guard isGameLoaded else { return }
        retroRun()
    }

    /// Resets the virtual machine.
    public func reset() {
        guard isGameLoaded else { return }
        retroReset()
    }

    /// Unloads the current game and releases core internal resources.
    public func unloadGame() {
        guard isGameLoaded else { return }
        retroUnloadGame()
        isGameLoaded = false
    }

    // MARK: - Environment Negotiation (retro_environment_t)

    fileprivate func handleEnvironment(cmd: UInt32, data: UnsafeMutableRawPointer?) -> Bool {
        switch cmd {
        case UInt32(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT):
            guard let data = data else { return false }
            let requestedFormat = data.assumingMemoryBound(to: retro_pixel_format.self).pointee
            // We strictly accept RETRO_PIXEL_FORMAT_XRGB8888 (32-bit little-endian matches Metal .bgra8Unorm)
            if requestedFormat == RETRO_PIXEL_FORMAT_XRGB8888 {
                self.pixelFormat = requestedFormat
                return true
            }
            return false

        case UInt32(RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY):
            guard let data = data?.assumingMemoryBound(to: UnsafePointer<CChar>?.self),
                  let sysDir = systemDirectoryCString else { return false }
            data.pointee = UnsafePointer(sysDir)
            return true

        case UInt32(RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY):
            guard let data = data?.assumingMemoryBound(to: UnsafePointer<CChar>?.self),
                  let saveDir = saveDirectoryCString else { return false }
            data.pointee = UnsafePointer(saveDir)
            return true

        case UInt32(RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY):
            guard let data = data?.assumingMemoryBound(to: UnsafePointer<CChar>?.self),
                  let sysDir = systemDirectoryCString else { return false }
            data.pointee = UnsafePointer(sysDir)
            return true

        case UInt32(RETRO_ENVIRONMENT_GET_CAN_DUPE):
            guard let data = data?.assumingMemoryBound(to: CBool.self) else { return false }
            data.pointee = true
            return true

        case UInt32(RETRO_ENVIRONMENT_GET_VARIABLE):
            guard let data = data else { return false }
            let varPtr = data.assumingMemoryBound(to: retro_variable.self)
            guard let keyPtr = varPtr.pointee.key else { return false }
            let key = String(cString: keyPtr)

            if let cValue = cVariablePointers[key] {
                varPtr.pointee.value = UnsafePointer(cValue)
                return true
            }
            return false

        case UInt32(RETRO_ENVIRONMENT_SET_VARIABLES):
            // Core advertises its available variables list; host accepts
            return true

        case UInt32(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE):
            guard let data = data?.assumingMemoryBound(to: CBool.self) else { return false }
            data.pointee = false
            return true

        case UInt32(RETRO_ENVIRONMENT_SET_GEOMETRY):
            guard let data = data else { return false }
            let geom = data.assumingMemoryBound(to: retro_game_geometry.self).pointee
            self.systemAVInfo.geometry = geom
            self.onGeometryChanged?(geom)
            return true

        case UInt32(RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO):
            guard let data = data else { return false }
            let avInfo = data.assumingMemoryBound(to: retro_system_av_info.self).pointee
            self.systemAVInfo = avInfo
            self.onGeometryChanged?(avInfo.geometry)
            return true

        case UInt32(RETRO_ENVIRONMENT_SHUTDOWN):
            self.onShutdown?()
            return true

        case UInt32(RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE):
            guard let data = data?.assumingMemoryBound(to: Int32.self) else { return false }
            // Bit 0 = Video Enable (1), Bit 1 = Audio Enable (2)
            data.pointee = 1 | 2
            return true

        case UInt32(RETRO_ENVIRONMENT_GET_LANGUAGE):
            guard let data = data?.assumingMemoryBound(to: UInt32.self) else { return false }
            data.pointee = 0 // RETRO_LANGUAGE_ENGLISH
            return true

        case UInt32(RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK):
            guard let data = data else { return false }
            let kbcb = data.assumingMemoryBound(to: retro_keyboard_callback.self).pointee
            self.keyboardCallback = kbcb.callback
            print("🎹 [LibretroCore] Keyboard callback registered successfully!")
            return true

        default:
            return false
        }
    }

    // MARK: - Subsystem Dispatch Trampoline Targets

    fileprivate func handleVideoRefresh(data: UnsafeRawPointer?, width: Int, height: Int, pitch: Int) {
        onVideoFrame?(data, width, height, pitch)
    }

    fileprivate func handleAudioSample(left: Int16, right: Int16) {
        onAudioSample?(left, right)
    }

    fileprivate func handleAudioSampleBatch(data: UnsafePointer<Int16>, frames: Int) -> Int {
        return onAudioBatch?(data, frames) ?? frames
    }

    fileprivate func handleInputPoll() {
        onInputPoll?()
    }

    fileprivate func handleInputState(port: UInt32, device: UInt32, index: UInt32, id: UInt32) -> Int16 {
        return onInputState?(port, device, index, id) ?? 0
    }
}
