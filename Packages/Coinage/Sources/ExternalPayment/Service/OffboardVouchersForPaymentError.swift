import Foundation

enum OffboardVouchersForPaymentError: Error {
    case emptyVouchers
    case missingRecyclerInfo
    case unexpectedEmptyRevision(RecyclerKey)
    case submissionFailed([Error])
}
