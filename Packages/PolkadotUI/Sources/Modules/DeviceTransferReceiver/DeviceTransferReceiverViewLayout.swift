import SwiftUI

public struct DeviceTransferReceiverViewLayout: View {
    @State var viewModel = DeviceTransferReceiverViewModel()

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
    DeviceTransferReceiverViewLayout()
}
