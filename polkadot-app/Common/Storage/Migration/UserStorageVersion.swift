import Foundation

enum UserStorageVersion: String, CaseIterable {
    case version1 = "UserDataModel"
    case version2 = "UserDataModel2"
    case version3 = "UserDataModel3"
    case version4 = "UserDataModel4"
    case version5 = "UserDataModel5"
    case version6 = "UserDataModel6"
    case version7 = "UserDataModel7"
    case version8 = "UserDataModel8"
    case version9 = "UserDataModel9"
    case version10 = "UserDataModel10"
    case version11 = "UserDataModel11"
    case version12 = "UserDataModel12"
    case version13 = "UserDataModel13"
    case version14 = "UserDataModel14"
    case version15 = "UserDataModel15"
    case version16 = "UserDataModel16"
    case version17 = "UserDataModel17"
    case version18 = "UserDataModel18"
    case version19 = "UserDataModel19"
    case version20 = "UserDataModel20"
    case version21 = "UserDataModel21"
    case version22 = "UserDataModel22"
    case version23 = "UserDataModel23"
    case version24 = "UserDataModel24"
    case version25 = "UserDataModel25"
    case version26 = "UserDataModel26"
    case version27 = "UserDataModel27"
    case version28 = "UserDataModel28"
    case version29 = "UserDataModel29"
    case version30 = "UserDataModel30"
    case version31 = "UserDataModel31"
    case version32 = "UserDataModel32"
    case version33 = "UserDataModel33"
    case version34 = "UserDataModel34"
    case version35 = "UserDataModel35"
    case version36 = "UserDataModel36"

    // swiftlint:disable:next cyclomatic_complexity
    func nextVersion() -> UserStorageVersion? {
        switch self {
        case .version1:
            .version2
        case .version2:
            .version3
        case .version3:
            .version4
        case .version4:
            .version5
        case .version5:
            .version6
        case .version6:
            .version7
        case .version7:
            .version8
        case .version8:
            .version9
        case .version9:
            .version10
        case .version10:
            .version11
        case .version11:
            .version12
        case .version12:
            .version13
        case .version13:
            .version14
        case .version14:
            .version15
        case .version15:
            .version16
        case .version16:
            .version17
        case .version17:
            .version18
        case .version18:
            .version19
        case .version19:
            .version20
        case .version20:
            .version21
        case .version21:
            .version22
        case .version22:
            .version23
        case .version23:
            .version24
        case .version24:
            .version25
        case .version25:
            .version26
        case .version26:
            .version27
        case .version27:
            .version28
        case .version28:
            .version29
        case .version29:
            .version30
        case .version30:
            .version31
        case .version31:
            .version32
        case .version32:
            .version33
        case .version33:
            .version34
        case .version34:
            .version35
        case .version35:
            .version36
        case .version36:
            nil
        }
    }
}
