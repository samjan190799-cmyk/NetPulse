import SwiftUI
import MapKit

// Вариант А: заливка, потом обводка (так написан слой зон)
struct ProbePolygonA: View {
    @State private var camera: MapCameraPosition = .automatic
    let corners: [CLLocationCoordinate2D] = []

    var body: some View {
        Map(position: $camera) {
            ForEach(0..<2, id: \.self) { _ in
                MapPolygon(coordinates: corners)
                    .foregroundStyle(Color.red.opacity(0.28))
                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
            }
        }
    }
}
