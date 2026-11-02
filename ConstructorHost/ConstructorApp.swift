//
//  ConstructorApp.swift
//  ConstructorHost
//
//  Created for Constructor (1997) Native macOS Apple Silicon Wrapper.
//  Punto de entrada nativo de la aplicación macOS en SwiftUI.
//

import SwiftUI
import AppKit

@main
struct ConstructorApp: App {

    @StateObject private var session: GameSession

    init() {
        do {
            let gameSession = try GameSession()
            _session = StateObject(wrappedValue: gameSession)
        } catch {
            fatalError("Error crítico al inicializar la sesión de juego de Constructor: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Constructor (1997)") {
            ContentView(session: session)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Emulación") {
                Button(session.isPaused ? "Reanudar" : "Pausar") {
                    session.togglePause()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("Reiniciar Juego") {
                    session.reset()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Liberar Ratón (Cmd + Opt)") {
                    session.inputManager.releaseMouse()
                }

                Button(session.audioManager.volume == 0 ? "Activar Sonido" : "Silenciar") {
                    if session.audioManager.volume == 0 {
                        session.audioManager.volume = 1.0
                    } else {
                        session.audioManager.volume = 0.0
                    }
                }
                .keyboardShortcut("m", modifiers: [.command])
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GameView(renderer: session.renderer, inputManager: session.inputManager)
                .ignoresSafeArea()
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            do {
                try session.start()
            } catch {
                print("Error al iniciar el bucle de juego: \(error)")
            }
        }
        .onDisappear {
            session.stop()
        }
    }
}
