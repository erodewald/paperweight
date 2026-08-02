import SwiftUI

/// The "Simple" locked-Home style: the words carry the weight.
///
/// `lock` is the 0…1 lock amount from the motion grammar. PR 2 adds the Diorama
/// and Overgrown styles with the same leading parameter, so this call site is
/// stable.
struct SimpleScene: View {
    var lock: Double = 1

    var body: some View {
        Text("Somewhere, a forest is filling in.")
            .font(.spectral(16, italic: true))
            .foregroundStyle(PW.encourage)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(lock)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 30)
    }
}

#Preview("Simple") {
    SimpleScene(lock: 1)
        .frame(height: 260)
        .background(PW.black)
}
