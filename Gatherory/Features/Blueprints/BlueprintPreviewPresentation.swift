import SwiftUI

extension EnvironmentValues {
    /// Root-owned presentation state lets preview/setup dismiss before the
    /// installed workspace opens, including setup resumed from the library.
    @Entry var blueprintPreviewPresented: Binding<Bool> = .constant(false)
}
