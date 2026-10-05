import SwiftUI
import MapKit

// Вариант Г: обводка со стилем и заливка отдельным вызовом `.foregroundStyle` после неё
struct ProbePolygonD: View {
    @State private var camera: MapCameraPosition = .automatic
    let corners: [CLLocationCoordinate2D] = []

    var body: some View {
        Map(position: $camera) {
            ForEach(0..<2, id: \.self) { _ in
                MapPolygon(coordinates: corners)
                    .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.red.opacity(0.28))
            }
        }
    }
}
