import SwiftUI
import SwiftData

@main
struct NutriCloneApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.brand)
        }
        .modelContainer(for: [
            UserProfile.self,
            Food.self,
            FoodLog.self,
            BodyEntry.self,
            WaterLog.self,
        ])
    }
}

/// Muestra el cuestionario inicial hasta que existe un perfil; después, las pestañas.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                MainTabView(profile: profile)
            } else {
                OnboardingView()
            }
        }
        // Se repite al volver al cuestionario tras "Borrar todos mis datos", que vacía el catálogo.
        .task(id: profiles.isEmpty) { await FoodCatalog.prepare(context) }
    }
}

struct MainTabView: View {
    let profile: UserProfile

    var body: some View {
        TabView {
            Tab("Hoy", systemImage: "fork.knife") {
                DiaryView(profile: profile)
            }
            Tab("Plan", systemImage: "calendar") {
                ComingSoonView(
                    title: "Plan de comidas",
                    symbol: "calendar",
                    message: "Aquí tendrás un menú semanal que cuadra con tus calorías, con recetas y lista de la compra."
                )
            }
            Tab("Progreso", systemImage: "chart.line.uptrend.xyaxis") {
                ProgressScreen(profile: profile)
            }
            Tab("Coach", systemImage: "bubble.left.and.text.bubble.right") {
                ComingSoonView(
                    title: "Coach",
                    symbol: "bubble.left.and.text.bubble.right",
                    message: "Un asistente que conoce tu día y te sugiere qué comer para llegar a tus metas."
                )
            }
            Tab("Perfil", systemImage: "person.crop.circle") {
                ProfileView(profile: profile)
            }
        }
    }
}

struct ComingSoonView: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Próximamente", systemImage: symbol)
            } description: {
                Text(message)
            }
            .navigationTitle(title)
        }
    }
}
