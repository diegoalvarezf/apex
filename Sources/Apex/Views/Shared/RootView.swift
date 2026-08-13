import SwiftUI

struct RootView: View {
    @EnvironmentObject var stravaAuth: StravaAuthManager
    @EnvironmentObject var healthKit: HealthKitManager

    // Antes la app entera dependía de tener cuenta de Strava: sin conectarla no se
    // pasaba del onboarding. Pero la mitad de lo que hace no la necesita
    // —recuperación, sueño, HRV, estrés, Body Battery y Edad Apex salen de HealthKit,
    // y las rutinas de gimnasio son locales—, así que se puede entrar sin ella y
    // conectarla más tarde desde Perfil.
    @AppStorage("apex_onboarding_done") private var onboardingDone = false

    var body: some View {
        Group {
            if stravaAuth.isAuthenticated || onboardingDone {
                MainTabView()
            } else {
                OnboardingView(onFinish: { onboardingDone = true })
            }
        }
        .animation(.easeInOut, value: stravaAuth.isAuthenticated)
    }
}
