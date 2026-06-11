import Testing
@testable import Luma

@Test
func finderLocalizedNameTakesPriorityOverBundleMetadata() {
    let name = ApplicationDisplayNameResolver.resolve(
        resourceLocalizedName: "微信.app",
        fileManagerDisplayName: "WeChat.app",
        localizedInfo: ["CFBundleDisplayName": "WeChat"],
        info: ["CFBundleName": "WeChat"],
        fallbackName: "WeChat.app"
    )

    #expect(name == "微信")
}

@Test
func fileManagerNamePrecedesBundleMetadataAndRemovesAppSuffix() {
    let name = ApplicationDisplayNameResolver.resolve(
        resourceLocalizedName: nil,
        fileManagerDisplayName: "腾讯会议.app",
        localizedInfo: ["CFBundleDisplayName": "Tencent Meeting"],
        info: nil,
        fallbackName: "TencentMeeting.app"
    )

    #expect(name == "腾讯会议")
}

@Test
func bundleMetadataIsUsedWhenFileNamesAreUnavailable() {
    let name = ApplicationDisplayNameResolver.resolve(
        resourceLocalizedName: " ",
        fileManagerDisplayName: nil,
        localizedInfo: ["CFBundleName": "Localized Name.app"],
        info: ["CFBundleDisplayName": "Fallback"],
        fallbackName: "Fallback.app"
    )

    #expect(name == "Localized Name")
}
