//
//  GameMTKView.swift
//  ConstructorHost
//
//  Created for Constructor (1997) Native macOS Apple Silicon Wrapper.
//  Subclase de MTKView optimizada para emulación a baja latencia con AppKit,
//  integrada con MetalRenderer e InputManager para captura de ratón y teclado.
//

import Cocoa
import MetalKit

public final class GameMTKView: MTKView {

    public let renderer: MetalRenderer
    public var inputManager: InputManager?

    private var trackingArea: NSTrackingArea?

    public init(frame frameRect: CGRect, device: MTLDevice, renderer: MetalRenderer, inputManager: InputManager? = nil) {
        self.renderer = renderer
        self.inputManager = inputManager
        super.init(frame: frameRect, device: device)
        setupViewConfiguration()
    }

    public required init(coder: NSCoder) {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Apple Silicon Metal device no disponible.")
        }
        do {
            self.renderer = try MetalRenderer(device: defaultDevice)
        } catch {
            fatalError("Fallo al inicializar MetalRenderer: \(error)")
        }
        super.init(coder: coder)
        self.device = defaultDevice
        setupViewConfiguration()
    }

    private func setupViewConfiguration() {
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        self.delegate = renderer

        // Bucle continuo de renderizado a 60 Hz sincronizado con CVDisplayLink / ProMotion
        self.isPaused = false
        self.enableSetNeedsDisplay = false
        self.preferredFramesPerSecond = 60

        // Capa Metal opaca
        self.wantsLayer = true
        self.layer?.isOpaque = true
        self.focusRingType = .none

        setupWindowObservers()
    }

    private func setupWindowObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        // Al perder el foco de la ventana, liberar la captura del ratón inmediatamente hacia macOS
        inputManager?.releaseMouse()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseMoved,
            .enabledDuringMouseDrag
        ]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        self.trackingArea = newArea
    }

    // MARK: - Receptores de Primer Respondiente

    public override var acceptsFirstResponder: Bool {
        return true
    }

    public override func becomeFirstResponder() -> Bool {
        return true
    }

    public override func resignFirstResponder() -> Bool {
        inputManager?.releaseMouse()
        return super.resignFirstResponder()
    }

    // MARK: - Despacho de Eventos de Teclado hacia InputManager

    public override func keyDown(with event: NSEvent) {
        inputManager?.handleKeyDown(with: event)
    }

    public override func keyUp(with event: NSEvent) {
        inputManager?.handleKeyUp(with: event)
    }

    public override func flagsChanged(with event: NSEvent) {
        inputManager?.handleFlagsChanged(with: event)
    }

    // MARK: - Despacho de Eventos de Ratón hacia InputManager

    public override func mouseDown(with event: NSEvent) {
        inputManager?.handleMouseDown(with: event)
    }

    public override func mouseUp(with event: NSEvent) {
        inputManager?.handleMouseUp(with: event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        inputManager?.handleRightMouseDown(with: event)
    }

    public override func rightMouseUp(with event: NSEvent) {
        inputManager?.handleRightMouseUp(with: event)
    }

    public override func otherMouseDown(with event: NSEvent) {
        inputManager?.handleOtherMouseDown(with: event)
    }

    public override func otherMouseUp(with event: NSEvent) {
        inputManager?.handleOtherMouseUp(with: event)
    }

    public override func mouseMoved(with event: NSEvent) {
        inputManager?.handleMouseMoved(with: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        inputManager?.handleMouseMoved(with: event)
    }

    public override func rightMouseDragged(with event: NSEvent) {
        inputManager?.handleMouseMoved(with: event)
    }

    public override func otherMouseDragged(with event: NSEvent) {
        inputManager?.handleMouseMoved(with: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        inputManager?.handleScrollWheel(with: event)
    }
}
