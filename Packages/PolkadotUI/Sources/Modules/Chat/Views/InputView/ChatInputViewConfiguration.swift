import UIKit

public struct ChatInputViewConfiguration: ChatInputViewConfigurationProtocol, Equatable {
    let placeholder: String
    let maxNumberOfLines: Int
    let maxCharacterCount: Int
    let canPay: Bool
    let canAttachFile: Bool
    let canSendWithoutText: Bool

    public init(
        placeholder: String,
        maxNumberOfLines: Int,
        maxCharacterCount: Int,
        canPay: Bool,
        canAttachFile: Bool,
        canSendWithoutText: Bool
    ) {
        self.placeholder = placeholder
        self.maxNumberOfLines = maxNumberOfLines
        self.maxCharacterCount = maxCharacterCount
        self.canPay = canPay
        self.canAttachFile = canAttachFile
        self.canSendWithoutText = canSendWithoutText
    }

    public var activateOnAppear: Bool {
        false
    }

    public func makeContentView(
        for handler: ChatInputHandling?
    ) -> UIView {
        DSChatInputView(configuration: self, handler: handler)
    }

    public func equalsTo(
        configuration: any ChatInputViewConfigurationProtocol
    ) -> Bool {
        guard
            let otherChatInputConfig = configuration as? ChatInputViewConfiguration else {
            return false
        }

        return self == otherChatInputConfig
    }

    public static func chat(canPay: Bool, canAttachFile: Bool, canSendWithoutText: Bool = false) -> Self {
        .init(
            placeholder: String(localized: .chatInputPlaceholder),
            maxNumberOfLines: 7,
            maxCharacterCount: 500,
            canPay: canPay,
            canAttachFile: canAttachFile,
            canSendWithoutText: canSendWithoutText
        )
    }
}
