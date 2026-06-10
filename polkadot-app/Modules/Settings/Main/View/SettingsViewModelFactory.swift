import Foundation
import SwiftUI
import PolkadotUI

protocol SettingsViewModelMaking {
    func makeContent(
        visibleCells: Set<SettingsViewModel.CellType>,
        attentionItems: Set<SettingsViewModel.CellType>,
        selectedCurrencyCode: String?,
        selectedThemeName: String?,
        appVersion: String?,
        onSelect: @escaping (SettingsViewModel.CellType) -> Void
    ) -> SettingsViewModel.Content
}

final class SettingsViewModelFactory: SettingsViewModelMaking {
    func makeContent(
        visibleCells: Set<SettingsViewModel.CellType>,
        attentionItems: Set<SettingsViewModel.CellType>,
        selectedCurrencyCode: String?,
        selectedThemeName: String?,
        appVersion: String?,
        onSelect: @escaping (SettingsViewModel.CellType) -> Void
    ) -> SettingsViewModel.Content {
        let sections: [SettingsViewLayout.Section] = SettingsViewModel.Section.allCases
            .compactMap { section -> SettingsViewLayout.Section? in
                let cells = section.cells.filter(visibleCells.contains)
                guard !cells.isEmpty else { return nil }
                return SettingsViewLayout.Section(
                    id: section.rawValue,
                    header: section.header,
                    items: cells.map { cellType in
                        makeItem(
                            cellType: cellType,
                            attentionItems: attentionItems,
                            selectedCurrencyCode: selectedCurrencyCode,
                            selectedThemeName: selectedThemeName,
                            onSelect: onSelect
                        )
                    }
                )
            }
        return SettingsViewModel.Content(sections: sections, appVersion: appVersion)
    }
}

private extension SettingsViewModelFactory {
    func makeItem(
        cellType: SettingsViewModel.CellType,
        attentionItems: Set<SettingsViewModel.CellType>,
        selectedCurrencyCode: String?,
        selectedThemeName: String?,
        onSelect: @escaping (SettingsViewModel.CellType) -> Void
    ) -> DSMenuListItem {
        let needsAttention = attentionItems.contains(cellType)
        return DSMenuListItem(
            id: cellType,
            title: cellType.title,
            description: needsAttention ? cellType.attentionDetails?.message : nil,
            style: needsAttention ? .attention : .default,
            icon: icon(for: cellType),
            rightSlot: rightSlot(
                for: cellType,
                selectedCurrencyCode: selectedCurrencyCode,
                selectedThemeName: selectedThemeName
            ),
            action: { onSelect(cellType) }
        )
    }

    func icon(for cellType: SettingsViewModel.CellType) -> ImageResource? {
        switch cellType {
        case .backup: .iconCloud
        case .theme: .iconPalette
        case .currency: .iconDollar
        case .revoke: .iconRevoke
        case .linkedDevices: .iconLaptopMinimal
        case .apps: .iconGrid
        case .blockedUsers: .iconBlock
        case .termsOfUse,
             .privacy: .iconFile
        case .contactUs: .iconCircleHelp
        }
    }

    func rightSlot(
        for cellType: SettingsViewModel.CellType,
        selectedCurrencyCode: String?,
        selectedThemeName: String?
    ) -> DSMenuListItemRightSlot.Style? {
        switch cellType {
        case .theme:
            selectedThemeName.map(DSMenuListItemRightSlot.Style.labelChevron)
        case .currency:
            if let selectedCurrencyCode {
                .labelChevron(selectedCurrencyCode)
            } else {
                .chevron
            }
        case .backup,
             .revoke,
             .linkedDevices,
             .apps,
             .blockedUsers,
             .termsOfUse,
             .privacy,
             .contactUs:
            .chevron
        }
    }
}
