import SwiftUI

struct AddDayExceptionSheet: View {
    @ObservedObject var vm: HomeViewModel
    let editing: DayException?
    var body: some View { Text("Add a day").pwScreen() }
}
