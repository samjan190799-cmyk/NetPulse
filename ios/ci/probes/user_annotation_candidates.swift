import SwiftUI
import MapKit

// Заведомо неверный вызов: компилятор перечислит в ответ все конструкторы UserAnnotation
struct ProbeUserAnnotationCandidates: View {
    var body: some View {
        Map {
            UserAnnotation(zzz: 1)
        }
    }
}
