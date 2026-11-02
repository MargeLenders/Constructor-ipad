//
//  ConstructorApp_iOS.swift
//  ConstructorIOS
//
//  Created for Constructor (1997) Native iPadOS Apple Silicon Wrapper.
//  Punto de entrada nativo de la aplicación iPadOS en SwiftUI.
//  Experiencia inmersiva a pantalla completa con toque directo puro.
//

import SwiftUI

@main
struct ConstructorApp_iOS: App {

    @StateObject private var session: GameSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let gameSession = try GameSession()
            _session = StateObject(wrappedValue: gameSession)
        } catch {
            fatalError("Error crítico al inicializar la sesión de juego de Constructor en iPadOS: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .ignoresSafeArea()
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        session.resume()
                    case .inactive, .background:
                        session.pause()
                    @unknown default:
                        break
                    }
                }
        }
    }
}

struct ContentView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GameView_iOS(renderer: session.renderer, inputManager: session.inputManager)
                .ignoresSafeArea()
        }
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
