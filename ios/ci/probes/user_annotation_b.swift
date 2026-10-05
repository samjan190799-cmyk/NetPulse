import SwiftUI
import MapKit

// Вариант Б: содержимое получает параметр (положение пользователя)
struct ProbeUserAnnotationB: View {
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $camera) {
            UserAnnotation { _ in
                Circle().fill(Color.blue).frame(width: 16, height: 16)
            }
        }
    }
}
