import SwiftUI
import MapKit

// Вариант А: содержимое точки «вы здесь» без параметров
struct ProbeUserAnnotationA: View {
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $camera) {
            UserAnnotation {
                Circle().fill(Color.blue).frame(width: 16, height: 16)
            }
        }
    }
}
