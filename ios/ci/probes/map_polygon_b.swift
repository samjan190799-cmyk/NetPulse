import SwiftUI
import MapKit

// Вариант Б: обводка, потом заливка
struct ProbePolygonB: View {
    @State private var camera: MapCameraPosition = .automatic
    let corners: [CLLocationCoordinate2D] = []

    var body: some View {
        Map(position: $camera) {
            ForEach(0..<2, id: \.self) { _ in
                MapPolygon(coordinates: corners)
                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
                    .foregroundStyle(Color.red.opacity(0.28))
            }
        }
    }
}
