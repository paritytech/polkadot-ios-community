import SwiftUI

public struct DeviceTransferSenderViewLayout: View {
    @State var viewModel = DeviceTransferSenderViewModel()

    public init() {}

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .center) {
                // Add your view content here
            }
        }
        .contentMargins(.horizontal, 16)
        .contentMargins(.top, 8)
    }
}

#Preview {
    DeviceTransferSenderViewLayout()
}
