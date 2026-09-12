import SwiftUI

struct DayExceptionsView: View {
    @ObservedObject var vm: HomeViewModel
    var body: some View {
        Text("Nothing planned.").pwScreen()
            .navigationTitle("Days off & quiet days")
            .navigationBarTitleDisplayMode(.inline)
    }
}
