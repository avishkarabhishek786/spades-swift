import Observation
import SwiftUI

// SwiftUI's `@Environment(Type.self)` needs a concrete observable object, but
// the services are behind protocols so tests can substitute silent versions.
// These boxes are the seam: one observable holder per protocol.

@MainActor
@Observable
final class AudioServiceBox {
    let service: any AudioPlaying
    init(_ service: any AudioPlaying) { self.service = service }
}

@MainActor
@Observable
final class HapticsBox {
    let service: any HapticsProviding
    init(_ service: any HapticsProviding) { self.service = service }
}

@MainActor
@Observable
final class PersistenceBox {
    let store: any Persisting
    init(_ store: any Persisting) { self.store = store }
}
