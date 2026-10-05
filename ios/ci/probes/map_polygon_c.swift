import SwiftUI
import MapKit

// Вариант В: только заливка, без обводки
struct ProbePolygonC: View {
    @State private var camera: MapCameraPosition = .automatic
    let corners: [CLLocationCoordinate2D] = []

    var body: some View {
        Map(position: $camera) {
            ForEach(0..<2, id: \.self) { _ in
                MapPolygon(coordinates: corners)
                    .foregroundStyle(Color.red.opacity(0.28))
            }
        }
    }
}
