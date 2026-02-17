// MARK: - L10n — Localization Dictionary for CrossX
// English (en) + Simplified Chinese (zh-Hans)

import Foundation

enum L10n {

    // MARK: - Translation Keys

    enum Key: String {

        // MARK: Tabs
        case tabConvert
        case tabWallpaperX
        case tabFiles
        case tabHistory

        // MARK: MainView Alerts
        case sendQueuedFilesTitle
        case sendAllCount
        case later
        case sendQueuedFilesMessage

        // MARK: Convert View
        case enterWebpageURL
        case convertAndSend
        case convertToEPUB
        case saveToFiles
        case sendingPercent
        case recent
        case seeAll
        case resendToX4
        case reconvertAndShare
        case copyURL
        case untitled
        case sendQueue
        case sendAll
        case queueTotalSize
        case noItemsQueued
        case queueEmptyDescription
        case largeQueueWarningTitle
        case largeQueueWarningMessage
        case estimatedTimeMinSec
        case estimatedTimeSec
        case sendAnyway

        // MARK: History View
        case noActivityYet
        case noActivityDescription
        case clearAllHistoryTitle
        case deleteAll
        case cancel
        case clearAllHistoryMessage
        case delete
        case resend
        case clear
        case clearAll
        case clearConversions
        case clearFileActivity
        case noActivityRecorded
        case noConversionHistory
        case noFileActivity
        case noQueueActivity
        case noRSSActivity

        // MARK: History Filters
        case filterAll
        case filterConversions
        case filterFileActivity
        case filterQueue
        case filterRSS
        case filterNoItems

        // MARK: File Manager View
        case fileManager
        case newFolder
        case uploadFile
        case emptyFolder
        case emptyFolderDescription
        case itemCount
        case notConnected
        case connectToDeviceToManage
        case loadingFiles
        case uploading
        case couldNotAccessFile
        case failedToReadFile
        case fileSelectionFailed
        case deleteItemTitle
        case deleteFolderMustBeEmpty
        case deleteFilePermanent
        case deleteFolderWithContents
        case deleteFolderCountingContents
        case deletingProgress
        case deletingItem
        case deletedFolderRecursive
        case deletedFolderRecursivePartial
        case failedToDeleteFolderRecursive
        case stopDelete
        case deleteStopped
        case fileManagerDeviceNote
        case fileListSummary
        case fileListSummaryNoFiles

        // MARK: File Manager Row
        case renameComingSoon
        case moveTo
        case move

        // MARK: Move File Sheet
        case moveFileTitle
        case root
        case moveHere
        case noSubfolders
        case noSubfoldersDescription

        // MARK: Rename File Sheet
        case rename
        case name
        case renameFileTitle
        case extensionCannotChange

        // MARK: Create Folder Sheet
        case folderName
        case avoidSpecialCharacters
        case create

        // MARK: Settings Sheet
        case settings
        case done
        case device
        case firmware
        case deviceIPAddress
        case address
        case firmwareIPDescription
        case featureFolders
        case convertSectionLabel
        case wallpaperXSectionLabel
        case featureFoldersDescription
        case testConnection
        case connectedWithInfo
        case notReachable
        case feedbackAndSupport
        case sourceCode
        case featureRequests
        case reportABug
        case feedbackDescription
        case siriShortcut
        case siriShortcutDescription
        case openShortcutsApp
        case siriShortcutFooter
        case storage
        case database
        case webCache
        case tempFiles
        case queueEPUBCount
        case clearHistoryData
        case clearWebCache
        case clearQueue
        case resetTransferStats
        case transferStatsReset
        case estimateImprovesNotice
        case storageDescription
        case clearHistoryDataTitle
        case clearHistory
        case clearHistoryDataMessage
        case clearWebCacheTitle
        case clearCache
        case clearWebCacheMessage
        case clearEPUBQueueTitle
        case clearEPUBQueueMessage
        case about
        case version
        case epubFormat
        case showOnboarding
        case language

        // MARK: Settings - Siri Shortcut Steps
        case siriStep1
        case siriStep2
        case siriStep3
        case siriStep4
        case siriStep5
        case siriStep6
        case siriStep7
        case siriStep8
        case siriStep9

        // MARK: Firmware Type Display Names
        case firmwareStock
        case firmwareCrossPoint
        case firmwareCustom

        // MARK: Device Connection Accessory
        case scanningNetwork
        case epubsQueued
        case tapConnectToSearch
        case disconnect
        case connect
        case sendingFilePercent

        // MARK: Device Status Bar
        case accessPoint
        case stationMode

        // MARK: Onboarding
        case back
        case next
        case skip
        case welcomeTitle
        case welcomeDescription
        case pasteConvertRead
        case pasteConvertReadDescription
        case fetch
        case extract
        case epub
        case worksOffline
        case worksOfflineDescription
        case queueLabel
        case sendLabel
        case convertFromAnywhere
        case convertFromAnywhereDescription
        case youreAllSet
        case youreAllSetDescription
        case getStarted

        // MARK: WallpaperX View
        case selectAnImage
        case photos
        case fit
        case alignment
        case rotate
        case depth
        case fitMode
        case grayscale
        case invert
        case save
        case advanced
        case connected
        case refresh
        case scanning
        case processing

        // MARK: ConvertViewModel Phase Labels
        case phaseReady
        case phaseFetching
        case phaseExtracting
        case phaseBuilding
        case phaseSending
        case phaseSent
        case phaseSavedLocally
        case phaseFailed

        // MARK: Queue Duplicate Prevention
        case urlAlreadyQueued
        case intentAlreadyQueued

        // MARK: ConvertViewModel Messages
        case enterValidURL
        case uploadAlreadyInProgress
        case x4NotConnected
        case invalidArticleURL
        case sentArticleToX4
        case queuedArticle
        case epubCreated
        case resentArticleToX4

        // MARK: DeviceViewModel
        case x4NotFoundMessage

        // MARK: FileManagerViewModel
        case notConnectedToDevice
        case createdFolderIn
        case failedToCreateFolderIn
        case uploadedFileTo
        case failedToUploadFileTo
        case deletedFolderFrom
        case deletedFileFrom
        case failedToDeleteFolderFrom
        case failedToDeleteFileFrom
        case movedFileTo
        case failedToMoveFileTo

        // MARK: QueueViewModel
        case failedToQueueEPUB
        case sentItem
        case sentMultipleEPUBs
        case failedToSendItem
        case sentSingleItem
        case failedToSendSingleItem

        // MARK: Global Batch Progress
        case batchSendingProgress
        case batchConvertingProgress
        case batchSendingItem

        // MARK: WallpaperViewModel
        case couldNotLoadImage
        case failedToLoadImage
        case cannotAccessFile
        case unsupportedImageFormat
        case noImageLoaded
        case encodingBMP
        case sentImageToFolder
        case convertedImageSaveOrConnect
        case imageProcessingFailed

        // MARK: ActivityEvent Labels
        case activityFileUploaded
        case activityFolderCreated
        case activityFileMoved
        case activityFileDeleted
        case activityFolderDeleted
        case activityWallpaperSent
        case activityQueueSent
        case categoryFileManager
        case categoryWallpaper
        case categoryRSS
        case activityRSSConversion

        // MARK: BMPColorDepth Labels
        case depth24bit
        case depth8bit
        case depth4bit
        case depth1bit
        case depthNotRecommended

        // MARK: DeviceError Descriptions
        case errorCannotReachDevice
        case errorUploadFailed
        case errorCreateFolderFailed
        case errorUnexpectedResponse
        case errorTimeout
        case errorConnectionLostDuringUpload
        case errorDeleteFailed
        case errorMoveFailed
        case errorRenameFailed
        case errorBatchDeleteInProgress
        case errorFolderNotEmpty
        case errorNameAlreadyExists
        case errorItemProtected
        case errorOperationNotSupported

        // MARK: FileNameValidator Errors
        case validatorNameEmpty
        case validatorNameDotOrDotDot
        case validatorNameStartsWithDot
        case validatorNameInvalidCharacters

        // MARK: Share Extension
        case preparing
        case invalidURL
        case contentTooShort
        case couldNotExtractURL
        case couldNotExtractContent
        case connectingToX4
        case sentToX4
        case epubSaved
        case x4NotConnectedLocalEPUB

        // MARK: ConvertURLIntent
        case intentInvalidURL
        case intentNotWebPage
        case intentFetchFailed
        case intentExtractFailed
        case intentEPUBFailed
        case intentQueueFailed
        case intentProvideURL
        case intentQueued
        case intentItemsWaiting

        // MARK: Debug Logs
        case debugLogs
        case debugLogsClear
        case debugLogsClearTitle
        case debugLogsClearMessage
        case debugLogsCopyAll
        case debugLogsShare
        case debugLogsEmpty
        case debugLogsEmptyDescription
        case debugLogsEntryCount
        case clearDebugLogs
        case clearDebugLogsTitle
        case clearDebugLogsMessage
        case storageAndLogsDescription
        case reportBugTitle
        case reportBugMessage
        case copyLogsAndReport
        case reportWithoutLogs
        case debugFilterAll
        case debugFilterErrors
        case debugFilterQueue
        case debugFilterDevice
        case debugFilterConversion
        case debugFilterRSS
        case queueCircuitBreaker

        // MARK: RSS Feed
        case rssFeeds
        case rssNew
        case rssRefreshing
        case rssTapToSetup
        case rssManageFeeds
        case rssAllFeeds
        case rssFeedCount
        case rssAddNewFeed
        case rssEnterFeedURL
        case rssValidating
        case rssAddFeed
        case rssAddFeedFooter
        case rssYourFeeds
        case rssNoFeedsTitle
        case rssNoFeedsDescription
        case rssAddFirstFeed
        case rssNoArticles
        case rssSelectAllNew
        case rssDeselectAll
        case rssSelectedCount
        case rssConvertAndSend
        case rssConvertAndQueue
        case rssConverting
        case rssSent
        case rssQueued
        case rssFailed
        case rssSentArticles
        case rssQueuedArticles
        case rssSentAndQueued
        case rssFailedArticles
        case rssInvalidFeedURL
        case rssFeedAlreadyExists
        case rssInvalidURL

        // MARK: AppLanguage Display Names
        case languageSystemDefault
        case languageEnglish
        case languageChinese
    }

    // MARK: - Translation Tables

    private static let translations: [String: [Key: String]] = [
        "en": en,
        "zh-Hans": zhHans,
    ]

    // MARK: English

    private static let en: [Key: String] = [

        // Tabs
        .tabConvert: "Convert",
        .tabWallpaperX: "WallpaperX",
        .tabFiles: "Files",
        .tabHistory: "History",

        // MainView Alerts
        .sendQueuedFilesTitle: "Send Queued Files?",
        .sendAllCount: "Send All (%d)",
        .later: "Later",
        .sendQueuedFilesMessage: "You have %d EPUB(s) queued. Send them to X4 now?",

        // Convert View
        .enterWebpageURL: "Enter webpage URL",
        .convertAndSend: "Convert & Send",
        .convertToEPUB: "Convert to EPUB",
        .saveToFiles: "Save to Files",
        .sendingPercent: "Sending %d%%",
        .recent: "Recent",
        .seeAll: "See All",
        .resendToX4: "Resend to X4",
        .reconvertAndShare: "Reconvert & Share",
        .copyURL: "Copy URL",
        .untitled: "Untitled",
        .sendQueue: "Send Queue",
        .sendAll: "Send All",
        .queueTotalSize: "%@ total",
        .noItemsQueued: "No Items Queued",
        .queueEmptyDescription: "EPUBs converted while offline will appear here for sending later.",
        .largeQueueWarningTitle: "Large Queue",
        .largeQueueWarningMessage: "Sending %d articles may take approximately %@. Articles are transferred one at a time due to device hardware limitations.\n\nThe optimal range is 5–10 articles. Please wait for the transfer to complete.",
        .estimatedTimeMinSec: "%d min %d sec",
        .estimatedTimeSec: "%d sec",
        .sendAnyway: "Send Anyway",

        // History View
        .noActivityYet: "No Activity Yet",
        .noActivityDescription: "Convert a web page or manage files on your device to see your activity here.",
        .clearAllHistoryTitle: "Clear All History?",
        .deleteAll: "Delete All",
        .cancel: "Cancel",
        .clearAllHistoryMessage: "This will permanently delete all conversion history and file activity.",
        .delete: "Delete",
        .resend: "Resend",
        .clear: "Clear",
        .clearAll: "Clear All",
        .clearConversions: "Clear Conversions",
        .clearFileActivity: "Clear File Activity",
        .noActivityRecorded: "No activity recorded yet.",
        .noConversionHistory: "No conversion history. Convert a web page to EPUB to see it here.",
        .noFileActivity: "No file activity. Upload, move, or delete files to see activity here.",
        .noQueueActivity: "No queue activity. Queued EPUBs sent to the device will appear here.",
        .noRSSActivity: "No RSS activity. RSS feed conversions will appear here.",

        // History Filters
        .filterAll: "All",
        .filterConversions: "Conversions",
        .filterFileActivity: "File Activity",
        .filterQueue: "Queue",
        .filterRSS: "RSS",
        .filterNoItems: "No %@",

        // File Manager View
        .fileManager: "File Manager",
        .newFolder: "New Folder",
        .uploadFile: "Upload File",
        .emptyFolder: "Empty Folder",
        .emptyFolderDescription: "This directory is empty. Tap + to add files or create folders.",
        .itemCount: "%d item(s)",
        .notConnected: "Not Connected",
        .connectToDeviceToManage: "Connect to your X4 device to browse and manage files.",
        .loadingFiles: "Loading files...",
        .uploading: "Uploading...",
        .couldNotAccessFile: "Could not access the selected file.",
        .failedToReadFile: "Failed to read file: %@",
        .fileSelectionFailed: "File selection failed: %@",
        .deleteItemTitle: "Delete \"%@\"?",
        .deleteFolderMustBeEmpty: "This folder and all its contents will be permanently deleted. This action cannot be undone.",
        .deleteFilePermanent: "This file will be permanently deleted from the device.",
        .deleteFolderWithContents: "This folder contains %d item(s). All contents will be permanently deleted. This action cannot be undone.",
        .deleteFolderCountingContents: "Counting folder contents...",
        .deletingProgress: "Deleting %d/%d...",
        .deletingItem: "Deleting %@...",
        .deletedFolderRecursive: "Deleted folder '%@' and %d item(s) from %@",
        .deletedFolderRecursivePartial: "Deleted folder '%@' (%d item(s)) from %@ — %d item(s) could not be deleted",
        .failedToDeleteFolderRecursive: "Failed to fully delete folder '%@' from %@: %d of %d item(s) deleted",
        .stopDelete: "Stop",
        .deleteStopped: "Stopped — %d of %d item(s) deleted",
        .fileManagerDeviceNote: "The X4 e-reader has limited WiFi performance. Uploads and bulk operations like deleting folders may take longer or occasionally fail — this is a device limitation, not an app issue. The app retries automatically.",
        .fileListSummary: "%d folder(s), %d file(s), %@",
        .fileListSummaryNoFiles: "%d folder(s), %d file(s)",

        // File Manager Row
        .renameComingSoon: "Rename (Coming Soon)",
        .moveTo: "Move to...",
        .move: "Move",

        // Move File Sheet
        .moveFileTitle: "Move \"%@\"",
        .root: "Root",
        .moveHere: "Move Here",
        .noSubfolders: "No Subfolders",
        .noSubfoldersDescription: "This directory has no subfolders.",

        // Rename File Sheet
        .rename: "Rename",
        .name: "Name",
        .renameFileTitle: "Rename \"%@\"",
        .extensionCannotChange: "The file extension cannot be changed.",

        // Create Folder Sheet
        .folderName: "Folder name",
        .avoidSpecialCharacters: "Avoid special characters: \" * : < > ? / \\ |",
        .create: "Create",

        // Settings Sheet
        .settings: "Settings",
        .done: "Done",
        .device: "Device",
        .firmware: "Firmware",
        .deviceIPAddress: "Device IP Address",
        .address: "Address",
        .firmwareIPDescription: "CrossPoint uses crosspoint.local (fallback: 192.168.4.1). Stock uses 192.168.3.3.",
        .featureFolders: "Feature Folders",
        .convertSectionLabel: "Convert",
        .wallpaperXSectionLabel: "WallpaperX",
        .featureFoldersDescription: "Each feature uploads to its own folder on the device (e.g. /%@/). Tap a field to change the destination.",
        .testConnection: "Test Connection",
        .connectedWithInfo: "Connected (%@)",
        .notReachable: "Not reachable",
        .feedbackAndSupport: "Feedback & Support",
        .sourceCode: "Source Code",
        .featureRequests: "Feature Requests",
        .reportABug: "Report a Bug",
        .feedbackDescription: "Opens GitHub Issues where you can suggest features or report bugs. Also you can inspect the Source Code",
        .siriShortcut: "Siri Shortcut",
        .siriShortcutDescription: "Convert web pages to EPUB directly from the Share menu using a Siri Shortcut and add it to the Queue",
        .openShortcutsApp: "Open Shortcuts App",
        .siriShortcutFooter: "The shortcut converts pages in the background and queues them for sending when your X4 connects.",
        .storage: "Storage",
        .database: "Database",
        .webCache: "Web Cache",
        .tempFiles: "Temp Files",
        .queueEPUBCount: "Queue (%d EPUBs)",
        .clearHistoryData: "Clear History Data",
        .clearWebCache: "Clear Web Cache",
        .clearQueue: "Clear Queue",
        .resetTransferStats: "Reset Transfer Stats",
        .transferStatsReset: "Transfer statistics have been reset.",
        .estimateImprovesNotice: "\n\nEstimated times improve with each transfer.",
        .storageDescription: "Database includes conversion history and file activity logs. Web Cache stores fetched web pages for faster re-conversion.",
        .clearHistoryDataTitle: "Clear History Data?",
        .clearHistory: "Clear History",
        .clearHistoryDataMessage: "This will permanently delete all conversion history and file activity logs.",
        .clearWebCacheTitle: "Clear Web Cache?",
        .clearCache: "Clear Cache",
        .clearWebCacheMessage: "Cached web pages will be removed. Future conversions may take slightly longer.",
        .clearEPUBQueueTitle: "Clear EPUB Queue?",
        .clearEPUBQueueMessage: "All %d queued EPUB(s) will be permanently deleted.",
        .about: "About",
        .version: "Version",
        .epubFormat: "EPUB Format",
        .showOnboarding: "Show Onboarding",
        .language: "Language",

        // Settings - Siri Shortcut Steps
        .siriStep1: "Open the **Shortcuts** app",
        .siriStep2: "Tap **+** to create a new Shortcut",
        .siriStep3: "Search for **\"CrossX\"** in the search bar",
        .siriStep4: "Press **\"Convert to EPUB & Add to Queue\"**",
        .siriStep5: "Tap the **info icon** (i) at the bottom",
        .siriStep6: "Enable **\"Show in Share Sheet\"** and close it",
        .siriStep7: "Press **\"Web Page URL\"** input",
        .siriStep8: "Press **\"Select Variable\"**",
        .siriStep9: "Press **\"Shortcut Input\"**",

        // Firmware Type Display Names
        .firmwareStock: "Stock",
        .firmwareCrossPoint: "CrossPoint",
        .firmwareCustom: "Custom",

        // Device Connection Accessory
        .scanningNetwork: "Scanning network...",
        .epubsQueued: "%d EPUB(s) queued",
        .tapConnectToSearch: "Tap Connect to search",
        .disconnect: "Disconnect",
        .connect: "Connect",
        .sendingFilePercent: "Sending %@... %d%%",

        // Device Status Bar
        .accessPoint: "Access Point",
        .stationMode: "Station",

        // Onboarding
        .back: "Back",
        .next: "Next",
        .skip: "Skip",
        .welcomeTitle: "Welcome to CrossX",
        .welcomeDescription: "Convert any web page to EPUB and send it to your Xteink X4 e-reader — no cloud, no accounts, just WiFi.",
        .pasteConvertRead: "Paste. Convert. Read.",
        .pasteConvertReadDescription: "Paste a URL, tap Convert, and CrossX fetches the page, extracts the article, and builds a clean EPUB — all in seconds.",
        .fetch: "Fetch",
        .extract: "Extract",
        .epub: "EPUB",
        .worksOffline: "Works Offline",
        .worksOfflineDescription: "No device connected? No problem. Converted EPUBs are queued and sent automatically when your X4 connects.",
        .queueLabel: "Queue",
        .sendLabel: "Send",
        .convertFromAnywhere: "Convert from Anywhere",
        .convertFromAnywhereDescription: "Set up a Siri Shortcut to convert pages directly from Safari's Share menu.",
        .youreAllSet: "You're All Set",
        .youreAllSetDescription: "Connect to your X4's WiFi hotspot and start converting. Your e-reader is waiting.",
        .getStarted: "Get Started",

        // WallpaperX View
        .selectAnImage: "Select an image",
        .photos: "Photos",
        .fit: "Fit",
        .alignment: "Alignment",
        .rotate: "Rotate",
        .depth: "Depth",
        .fitMode: "Fit Mode",
        .grayscale: "Grayscale",
        .invert: "Invert",
        .save: "Save",
        .advanced: "Advanced",
        .connected: "Connected",
        .refresh: "Refresh",
        .scanning: "Scanning...",
        .processing: "Processing...",

        // ConvertViewModel Phase Labels
        .phaseReady: "Ready",
        .phaseFetching: "Fetching page...",
        .phaseExtracting: "Extracting content...",
        .phaseBuilding: "Building EPUB...",
        .phaseSending: "Sending to X4...",
        .phaseSent: "Sent!",
        .phaseSavedLocally: "Saved locally",
        .phaseFailed: "Failed",

        // Queue Duplicate Prevention
        .urlAlreadyQueued: "This URL is already in the send queue.",
        .intentAlreadyQueued: "This URL is already in the queue. It will be sent when your X4 connects.",

        // ConvertViewModel Messages
        .enterValidURL: "Please enter a valid URL.",
        .uploadAlreadyInProgress: "An upload is already in progress.",
        .x4NotConnected: "X4 is not connected.",
        .invalidArticleURL: "Invalid article URL.",
        .sentArticleToX4: "Sent \"%@\" to X4",
        .queuedArticle: "Queued \"%@\" — will send when connected.",
        .epubCreated: "EPUB created: \"%@\"",
        .resentArticleToX4: "Re-sent \"%@\" to X4",

        // DeviceViewModel
        .x4NotFoundMessage: "X4 not found. Connect to the X4 WiFi hotspot and try again.",

        // FileManagerViewModel
        .notConnectedToDevice: "Not connected to device.",
        .createdFolderIn: "Created folder '%@' in %@",
        .failedToCreateFolderIn: "Failed to create folder '%@' in %@",
        .uploadedFileTo: "Uploaded '%@' to %@",
        .failedToUploadFileTo: "Failed to upload '%@' to %@",
        .deletedFolderFrom: "Deleted folder '%@' from %@",
        .deletedFileFrom: "Deleted file '%@' from %@",
        .failedToDeleteFolderFrom: "Failed to delete folder '%@' from %@",
        .failedToDeleteFileFrom: "Failed to delete file '%@' from %@",
        .movedFileTo: "Moved '%@' to %@",
        .failedToMoveFileTo: "Failed to move '%@' to %@",

        // QueueViewModel
        .failedToQueueEPUB: "Failed to queue EPUB: %@",
        .sentItem: "Sent %@",
        .sentMultipleEPUBs: "Sent %d EPUBs: %@",
        .failedToSendItem: "Failed to send %@: %@",
        .sentSingleItem: "Sent %@",
        .failedToSendSingleItem: "Failed to send %@: %@",

        // Global Batch Progress
        .batchSendingProgress: "Sending %d/%d...",
        .batchConvertingProgress: "Converting %d/%d...",
        .batchSendingItem: "Sending %@...",

        // WallpaperViewModel
        .couldNotLoadImage: "Could not load the selected image.",
        .failedToLoadImage: "Failed to load image: %@",
        .cannotAccessFile: "Cannot access the selected file.",
        .unsupportedImageFormat: "Unsupported image format.",
        .noImageLoaded: "No image loaded.",
        .encodingBMP: "Encoding BMP...",
        .sentImageToFolder: "Sent %@ to /%@/",
        .convertedImageSaveOrConnect: "Converted %@ — save or connect to send.",
        .imageProcessingFailed: "Image processing failed.",

        // ActivityEvent Labels
        .activityFileUploaded: "File Uploaded",
        .activityFolderCreated: "Folder Created",
        .activityFileMoved: "File Moved",
        .activityFileDeleted: "File Deleted",
        .activityFolderDeleted: "Folder Deleted",
        .activityWallpaperSent: "Wallpaper Sent",
        .activityQueueSent: "Queue Sent to Device",
        .categoryFileManager: "File Manager",
        .categoryWallpaper: "Wallpaper",
        .categoryRSS: "RSS Feed",
        .activityRSSConversion: "RSS Conversion",

        // BMPColorDepth Labels
        .depth24bit: "24-bit",
        .depth8bit: "8-bit",
        .depth4bit: "4-bit",
        .depth1bit: "1-bit",
        .depthNotRecommended: "Not recommended for use with X4",

        // DeviceError Descriptions
        .errorCannotReachDevice: "Cannot reach X4 device. Make sure you are connected to the X4 WiFi hotspot.",
        .errorUploadFailed: "Upload failed with status code %d.",
        .errorCreateFolderFailed: "Could not create folder on device.",
        .errorUnexpectedResponse: "Received an unexpected response from the device.",
        .errorTimeout: "Connection to the device timed out.",
        .errorConnectionLostDuringUpload: "The connection to the device was lost during upload. The file may be too large or the WiFi signal too weak. Please try again.",
        .errorDeleteFailed: "Delete failed: %@",
        .errorMoveFailed: "Move failed: %@",
        .errorRenameFailed: "Rename failed: %@",
        .errorBatchDeleteInProgress: "A folder deletion is in progress. Please wait for it to complete before sending files.",
        .errorFolderNotEmpty: "Folder is not empty. Delete its contents first.",
        .errorNameAlreadyExists: "An item with that name already exists.",
        .errorItemProtected: "This item is protected and cannot be modified.",
        .errorOperationNotSupported: "This operation is not supported by the current firmware.",

        // FileNameValidator Errors
        .validatorNameEmpty: "Name cannot be empty.",
        .validatorNameDotOrDotDot: "Name cannot be \".\" or \"..\".",
        .validatorNameStartsWithDot: "Name cannot start with a dot.",
        .validatorNameInvalidCharacters: "Name contains invalid characters. Avoid \" * : < > ? / \\ |",

        // Share Extension
        .preparing: "Preparing...",
        .invalidURL: "Invalid URL",
        .contentTooShort: "Content too short",
        .couldNotExtractURL: "Could not extract a URL from the shared content.",
        .couldNotExtractContent: "Could not extract enough content from this page.",
        .connectingToX4: "Connecting to X4...",
        .sentToX4: "Sent to X4!",
        .epubSaved: "EPUB saved",
        .x4NotConnectedLocalEPUB: "X4 not connected. EPUB file created locally.",

        // ConvertURLIntent
        .intentInvalidURL: "The input is not a valid URL. Please provide a web page link.",
        .intentNotWebPage: "This doesn't appear to be a web page. CrossX can only convert web URLs to EPUB — images, files, and other content are not supported.",
        .intentFetchFailed: "Failed to fetch the web page: %@",
        .intentExtractFailed: "Could not extract readable content from this page.",
        .intentEPUBFailed: "Failed to create the EPUB file: %@",
        .intentQueueFailed: "Could not save the EPUB to the queue: %@",
        .intentProvideURL: "Please provide a web page URL to convert.",
        .intentQueued: "Queued \"%@\" (%@)",
        .intentItemsWaiting: "%d item(s) waiting to send.",

        // Debug Logs
        .debugLogs: "Debug Logs",
        .debugLogsClear: "Clear Logs",
        .debugLogsClearTitle: "Clear Debug Logs?",
        .debugLogsClearMessage: "All debug log entries will be permanently deleted.",
        .debugLogsCopyAll: "Copy All",
        .debugLogsShare: "Share as File",
        .debugLogsEmpty: "No Log Entries",
        .debugLogsEmptyDescription: "Debug events will appear here as you use the app.",
        .debugLogsEntryCount: "%d entries",
        .clearDebugLogs: "Clear Debug Logs",
        .clearDebugLogsTitle: "Clear Debug Logs?",
        .clearDebugLogsMessage: "All debug log entries will be permanently deleted.",
        .storageAndLogsDescription: "Database includes conversion history and file activity logs. Web Cache stores fetched web pages for faster re-conversion. Debug logs help when sharing bug reports.",
        .reportBugTitle: "Report a Bug",
        .reportBugMessage: "Would you like to copy debug logs to the clipboard? Including logs helps diagnose issues faster.",
        .copyLogsAndReport: "Copy Logs & Report",
        .reportWithoutLogs: "Report Without Logs",
        .debugFilterAll: "All",
        .debugFilterErrors: "Errors",
        .debugFilterQueue: "Queue",
        .debugFilterDevice: "Device",
        .debugFilterConversion: "Conversion",
        .debugFilterRSS: "RSS",
        .queueCircuitBreaker: "Aborted after %d consecutive failures. Device may be unreachable.",

        // RSS Feed
        .rssFeeds: "RSS Feeds",
        .rssNew: "new",
        .rssRefreshing: "Refreshing feeds...",
        .rssTapToSetup: "Tap to set up your RSS feeds",
        .rssManageFeeds: "Manage Feeds",
        .rssAllFeeds: "All Feeds",
        .rssFeedCount: "%d feeds",
        .rssAddNewFeed: "Add Feed",
        .rssEnterFeedURL: "Enter website or feed URL",
        .rssValidating: "Validating...",
        .rssAddFeed: "Add Feed",
        .rssAddFeedFooter: "Enter a website URL (e.g. techcrunch.com) or a direct RSS/Atom feed URL. The feed will be auto-discovered if possible.",
        .rssYourFeeds: "Your Feeds",
        .rssNoFeedsTitle: "No RSS Feeds Set Up",
        .rssNoFeedsDescription: "Add your favorite news sources to get articles delivered to your e-reader.",
        .rssAddFirstFeed: "Add Your First Feed",
        .rssNoArticles: "No articles available. Pull to refresh.",
        .rssSelectAllNew: "Select All New",
        .rssDeselectAll: "Deselect All",
        .rssSelectedCount: "%d selected",
        .rssConvertAndSend: "Send (%d)",
        .rssConvertAndQueue: "Queue (%d)",
        .rssConverting: "Converting %d/%d...",
        .rssSent: "Sent",
        .rssQueued: "Queued",
        .rssFailed: "Failed",
        .rssSentArticles: "Sent %d article(s) to device",
        .rssQueuedArticles: "Queued %d article(s) for later",
        .rssSentAndQueued: "Sent %d, queued %d article(s)",
        .rssFailedArticles: "%d article(s) failed to convert",
        .rssInvalidFeedURL: "Please enter a valid URL.",
        .rssFeedAlreadyExists: "Feed already exists: %@",
        .rssInvalidURL: "Invalid article URL",

        // AppLanguage Display Names
        .languageSystemDefault: "System Default",
        .languageEnglish: "English",
        .languageChinese: "中文 (简体)",
    ]

    // MARK: Simplified Chinese

    private static let zhHans: [Key: String] = [

        // Tabs
        .tabConvert: "转换",
        .tabWallpaperX: "壁纸X",
        .tabFiles: "文件",
        .tabHistory: "历史",

        // MainView Alerts
        .sendQueuedFilesTitle: "发送队列文件？",
        .sendAllCount: "全部发送 (%d)",
        .later: "稍后",
        .sendQueuedFilesMessage: "您有 %d 本EPUB排队中。现在发送到X4？",

        // Convert View
        .enterWebpageURL: "输入网页URL",
        .convertAndSend: "转换并发送",
        .convertToEPUB: "转换为EPUB",
        .saveToFiles: "保存到文件",
        .sendingPercent: "发送中 %d%%",
        .recent: "最近",
        .seeAll: "查看全部",
        .resendToX4: "重新发送到X4",
        .reconvertAndShare: "重新转换并分享",
        .copyURL: "复制链接",
        .untitled: "无标题",
        .sendQueue: "发送队列",
        .sendAll: "全部发送",
        .queueTotalSize: "共 %@",
        .noItemsQueued: "队列为空",
        .queueEmptyDescription: "离线转换的EPUB将在此处显示，等待稍后发送。",
        .largeQueueWarningTitle: "队列较大",
        .largeQueueWarningMessage: "发送 %d 篇文章大约需要 %@。由于设备硬件限制，文章将逐一传输。\n\n最佳队列数量为 5–10 篇。请等待传输完成。",
        .estimatedTimeMinSec: "%d 分 %d 秒",
        .estimatedTimeSec: "%d 秒",
        .sendAnyway: "仍然发送",

        // History View
        .noActivityYet: "暂无活动",
        .noActivityDescription: "转换网页或管理设备文件即可在此查看活动记录。",
        .clearAllHistoryTitle: "清除所有历史？",
        .deleteAll: "全部删除",
        .cancel: "取消",
        .clearAllHistoryMessage: "这将永久删除所有转换历史和文件活动记录。",
        .delete: "删除",
        .resend: "重新发送",
        .clear: "清除",
        .clearAll: "清除全部",
        .clearConversions: "清除转换记录",
        .clearFileActivity: "清除文件活动",
        .noActivityRecorded: "暂无活动记录。",
        .noConversionHistory: "暂无转换记录。转换网页为EPUB即可在此查看。",
        .noFileActivity: "暂无文件活动。上传、移动或删除文件即可在此查看。",
        .noQueueActivity: "暂无队列活动。发送到设备的排队EPUB将在此显示。",
        .noRSSActivity: "暂无RSS活动。RSS订阅转换将在此显示。",

        // History Filters
        .filterAll: "全部",
        .filterConversions: "转换",
        .filterFileActivity: "文件活动",
        .filterQueue: "队列",
        .filterRSS: "RSS",
        .filterNoItems: "暂无%@",

        // File Manager View
        .fileManager: "文件管理",
        .newFolder: "新建文件夹",
        .uploadFile: "上传文件",
        .emptyFolder: "空文件夹",
        .emptyFolderDescription: "此目录为空。点击 + 添加文件或创建文件夹。",
        .itemCount: "%d 个项目",
        .notConnected: "未连接",
        .connectToDeviceToManage: "连接到X4设备以浏览和管理文件。",
        .loadingFiles: "正在加载文件...",
        .uploading: "正在上传...",
        .couldNotAccessFile: "无法访问所选文件。",
        .failedToReadFile: "读取文件失败：%@",
        .fileSelectionFailed: "文件选择失败：%@",
        .deleteItemTitle: "删除「%@」？",
        .deleteFolderMustBeEmpty: "此文件夹及其所有内容将被永久删除。此操作无法撤销。",
        .deleteFilePermanent: "此文件将从设备中永久删除。",
        .deleteFolderWithContents: "此文件夹包含 %d 个项目。所有内容将被永久删除。此操作无法撤销。",
        .deleteFolderCountingContents: "正在统计文件夹内容...",
        .deletingProgress: "正在删除 %d/%d...",
        .deletingItem: "正在删除 %@...",
        .deletedFolderRecursive: "已从 %@ 删除文件夹「%@」及 %d 个项目",
        .deletedFolderRecursivePartial: "已从 %@ 删除文件夹「%@」（%d 个项目）— %d 个项目无法删除",
        .failedToDeleteFolderRecursive: "从 %@ 删除文件夹「%@」未完全成功：已删除 %d/%d 个项目",
        .stopDelete: "停止",
        .deleteStopped: "已停止 — 已删除 %d/%d 个项目",
        .fileManagerDeviceNote: "X4电子阅读器的WiFi性能有限。上传和批量操作（如删除文件夹）可能需要较长时间或偶尔失败——这是设备限制，非应用问题。应用会自动重试。",
        .fileListSummary: "%d 个文件夹, %d 个文件, %@",
        .fileListSummaryNoFiles: "%d 个文件夹, %d 个文件",

        // File Manager Row
        .renameComingSoon: "重命名（即将推出）",
        .moveTo: "移动到...",
        .move: "移动",

        // Move File Sheet
        .moveFileTitle: "移动「%@」",
        .root: "根目录",
        .moveHere: "移动到此处",
        .noSubfolders: "无子文件夹",
        .noSubfoldersDescription: "此目录没有子文件夹。",

        // Rename File Sheet
        .rename: "重命名",
        .name: "名称",
        .renameFileTitle: "重命名「%@」",
        .extensionCannotChange: "文件扩展名不可更改。",

        // Create Folder Sheet
        .folderName: "文件夹名称",
        .avoidSpecialCharacters: "避免使用特殊字符：\" * : < > ? / \\ |",
        .create: "创建",

        // Settings Sheet
        .settings: "设置",
        .done: "完成",
        .device: "设备",
        .firmware: "固件",
        .deviceIPAddress: "设备IP地址",
        .address: "地址",
        .firmwareIPDescription: "CrossPoint使用crosspoint.local（备用：192.168.4.1）。Stock使用192.168.3.3。",
        .featureFolders: "功能文件夹",
        .convertSectionLabel: "转换",
        .wallpaperXSectionLabel: "壁纸X",
        .featureFoldersDescription: "每个功能上传到设备上各自的文件夹（例如 /%@/）。点击字段更改目标位置。",
        .testConnection: "测试连接",
        .connectedWithInfo: "已连接（%@）",
        .notReachable: "无法连接",
        .feedbackAndSupport: "反馈与支持",
        .sourceCode: "源代码",
        .featureRequests: "功能请求",
        .reportABug: "报告错误",
        .feedbackDescription: "打开GitHub Issues，您可以在此提出功能建议或报告错误，也可以查看源代码",
        .siriShortcut: "Siri快捷指令",
        .siriShortcutDescription: "使用Siri快捷指令直接从分享菜单将网页转换为EPUB并添加到队列",
        .openShortcutsApp: "打开快捷指令",
        .siriShortcutFooter: "快捷指令在后台转换页面，并在X4连接时排队发送。",
        .storage: "存储",
        .database: "数据库",
        .webCache: "网页缓存",
        .tempFiles: "临时文件",
        .queueEPUBCount: "队列（%d本EPUB）",
        .clearHistoryData: "清除历史数据",
        .clearWebCache: "清除网页缓存",
        .clearQueue: "清除队列",
        .resetTransferStats: "重置传输统计",
        .transferStatsReset: "传输统计已重置。",
        .estimateImprovesNotice: "\n\n每次传输后，预估时间将更加准确。",
        .storageDescription: "数据库包括转换历史和文件活动日志。网页缓存存储已获取的网页以加快重新转换速度。",
        .clearHistoryDataTitle: "清除历史数据？",
        .clearHistory: "清除历史",
        .clearHistoryDataMessage: "这将永久删除所有转换历史和文件活动日志。",
        .clearWebCacheTitle: "清除网页缓存？",
        .clearCache: "清除缓存",
        .clearWebCacheMessage: "缓存的网页将被删除。未来的转换可能会稍慢一些。",
        .clearEPUBQueueTitle: "清除EPUB队列？",
        .clearEPUBQueueMessage: "所有 %d 本排队的EPUB将被永久删除。",
        .about: "关于",
        .version: "版本",
        .epubFormat: "EPUB格式",
        .showOnboarding: "显示引导",
        .language: "语言",

        // Settings - Siri Shortcut Steps
        .siriStep1: "打开**快捷指令**应用",
        .siriStep2: "点击 **+** 创建新的快捷指令",
        .siriStep3: "在搜索栏中搜索 **\"CrossX\"**",
        .siriStep4: "按下 **\"转换为EPUB并添加到队列\"**",
        .siriStep5: "点击底部的**信息图标** (i)",
        .siriStep6: "启用 **\"在分享菜单中显示\"** 并关闭",
        .siriStep7: "按下 **\"网页URL\"** 输入",
        .siriStep8: "按下 **\"选择变量\"**",
        .siriStep9: "按下 **\"快捷指令输入\"**",

        // Firmware Type Display Names
        .firmwareStock: "Stock",
        .firmwareCrossPoint: "CrossPoint",
        .firmwareCustom: "自定义",

        // Device Connection Accessory
        .scanningNetwork: "正在扫描网络...",
        .epubsQueued: "%d 本EPUB排队中",
        .tapConnectToSearch: "点击连接以搜索",
        .disconnect: "断开连接",
        .connect: "连接",
        .sendingFilePercent: "正在发送 %@... %d%%",

        // Device Status Bar
        .accessPoint: "热点模式",
        .stationMode: "站点模式",

        // Onboarding
        .back: "返回",
        .next: "下一步",
        .skip: "跳过",
        .welcomeTitle: "欢迎使用CrossX",
        .welcomeDescription: "将任何网页转换为EPUB并发送到您的Xteink X4电子阅读器——无需云端、无需账户，只需WiFi。",
        .pasteConvertRead: "粘贴。转换。阅读。",
        .pasteConvertReadDescription: "粘贴URL，点击转换，CrossX将获取页面、提取文章并生成整洁的EPUB——一切只需几秒。",
        .fetch: "获取",
        .extract: "提取",
        .epub: "EPUB",
        .worksOffline: "离线可用",
        .worksOfflineDescription: "设备未连接？没问题。转换的EPUB将自动排队，在X4连接时自动发送。",
        .queueLabel: "队列",
        .sendLabel: "发送",
        .convertFromAnywhere: "随时随地转换",
        .convertFromAnywhereDescription: "设置Siri快捷指令，直接从Safari的分享菜单转换页面。",
        .youreAllSet: "一切就绪",
        .youreAllSetDescription: "连接到X4的WiFi热点并开始转换。您的电子阅读器正在等待。",
        .getStarted: "开始使用",

        // WallpaperX View
        .selectAnImage: "选择图片",
        .photos: "照片",
        .fit: "适应",
        .alignment: "对齐",
        .rotate: "旋转",
        .depth: "深度",
        .fitMode: "适应模式",
        .grayscale: "灰度",
        .invert: "反色",
        .save: "保存",
        .advanced: "高级",
        .connected: "已连接",
        .refresh: "刷新",
        .scanning: "扫描中...",
        .processing: "处理中...",

        // ConvertViewModel Phase Labels
        .phaseReady: "就绪",
        .phaseFetching: "正在获取页面...",
        .phaseExtracting: "正在提取内容...",
        .phaseBuilding: "正在生成EPUB...",
        .phaseSending: "正在发送到X4...",
        .phaseSent: "已发送！",
        .phaseSavedLocally: "已本地保存",
        .phaseFailed: "失败",

        // Queue Duplicate Prevention
        .urlAlreadyQueued: "此链接已在发送队列中。",
        .intentAlreadyQueued: "此链接已在队列中。X4连接时将自动发送。",

        // ConvertViewModel Messages
        .enterValidURL: "请输入有效的URL。",
        .uploadAlreadyInProgress: "上传正在进行中。",
        .x4NotConnected: "X4未连接。",
        .invalidArticleURL: "无效的文章URL。",
        .sentArticleToX4: "已发送「%@」到X4",
        .queuedArticle: "已排队「%@」——连接时将自动发送。",
        .epubCreated: "EPUB已创建：「%@」",
        .resentArticleToX4: "已重新发送「%@」到X4",

        // DeviceViewModel
        .x4NotFoundMessage: "未找到X4。请连接到X4 WiFi热点后重试。",

        // FileManagerViewModel
        .notConnectedToDevice: "未连接到设备。",
        .createdFolderIn: "已在 %@ 创建文件夹「%@」",
        .failedToCreateFolderIn: "在 %@ 创建文件夹「%@」失败",
        .uploadedFileTo: "已上传「%@」到 %@",
        .failedToUploadFileTo: "上传「%@」到 %@ 失败",
        .deletedFolderFrom: "已从 %@ 删除文件夹「%@」",
        .deletedFileFrom: "已从 %@ 删除文件「%@」",
        .failedToDeleteFolderFrom: "从 %@ 删除文件夹「%@」失败",
        .failedToDeleteFileFrom: "从 %@ 删除文件「%@」失败",
        .movedFileTo: "已移动「%@」到 %@",
        .failedToMoveFileTo: "移动「%@」到 %@ 失败",

        // QueueViewModel
        .failedToQueueEPUB: "排队EPUB失败：%@",
        .sentItem: "已发送 %@",
        .sentMultipleEPUBs: "已发送 %d 本EPUB：%@",
        .failedToSendItem: "发送 %@ 失败：%@",
        .sentSingleItem: "已发送 %@",
        .failedToSendSingleItem: "发送 %@ 失败：%@",

        // Global Batch Progress
        .batchSendingProgress: "正在发送 %d/%d...",
        .batchConvertingProgress: "正在转换 %d/%d...",
        .batchSendingItem: "正在发送 %@...",

        // WallpaperViewModel
        .couldNotLoadImage: "无法加载所选图片。",
        .failedToLoadImage: "加载图片失败：%@",
        .cannotAccessFile: "无法访问所选文件。",
        .unsupportedImageFormat: "不支持的图片格式。",
        .noImageLoaded: "未加载图片。",
        .encodingBMP: "正在编码BMP...",
        .sentImageToFolder: "已发送 %@ 到 /%@/",
        .convertedImageSaveOrConnect: "已转换 %@ ——保存或连接以发送。",
        .imageProcessingFailed: "图片处理失败。",

        // ActivityEvent Labels
        .activityFileUploaded: "文件已上传",
        .activityFolderCreated: "文件夹已创建",
        .activityFileMoved: "文件已移动",
        .activityFileDeleted: "文件已删除",
        .activityFolderDeleted: "文件夹已删除",
        .activityWallpaperSent: "壁纸已发送",
        .activityQueueSent: "队列已发送到设备",
        .categoryFileManager: "文件管理",
        .categoryWallpaper: "壁纸",
        .categoryRSS: "RSS订阅",
        .activityRSSConversion: "RSS转换",

        // BMPColorDepth Labels
        .depth24bit: "24位",
        .depth8bit: "8位",
        .depth4bit: "4位",
        .depth1bit: "1位",
        .depthNotRecommended: "不建议与X4配合使用",

        // DeviceError Descriptions
        .errorCannotReachDevice: "无法连接X4设备。请确保已连接到X4 WiFi热点。",
        .errorUploadFailed: "上传失败，状态码 %d。",
        .errorCreateFolderFailed: "无法在设备上创建文件夹。",
        .errorUnexpectedResponse: "收到设备的意外响应。",
        .errorTimeout: "设备连接超时。",
        .errorConnectionLostDuringUpload: "上传过程中与设备的连接丢失。文件可能太大或WiFi信号太弱。请重试。",
        .errorDeleteFailed: "删除失败：%@",
        .errorMoveFailed: "移动失败：%@",
        .errorRenameFailed: "重命名失败：%@",
        .errorBatchDeleteInProgress: "正在删除文件夹。请等待删除完成后再发送文件。",
        .errorFolderNotEmpty: "文件夹不为空。请先删除其内容。",
        .errorNameAlreadyExists: "同名项目已存在。",
        .errorItemProtected: "此项目受保护，无法修改。",
        .errorOperationNotSupported: "当前固件不支持此操作。",

        // FileNameValidator Errors
        .validatorNameEmpty: "名称不能为空。",
        .validatorNameDotOrDotDot: "名称不能为「.」或「..」。",
        .validatorNameStartsWithDot: "名称不能以点号开头。",
        .validatorNameInvalidCharacters: "名称包含无效字符。请避免使用 \" * : < > ? / \\ |",

        // Share Extension
        .preparing: "准备中...",
        .invalidURL: "无效URL",
        .contentTooShort: "内容太少",
        .couldNotExtractURL: "无法从分享内容中提取URL。",
        .couldNotExtractContent: "无法从此页面提取足够内容。",
        .connectingToX4: "正在连接X4...",
        .sentToX4: "已发送到X4！",
        .epubSaved: "EPUB已保存",
        .x4NotConnectedLocalEPUB: "X4未连接。EPUB文件已在本地创建。",

        // ConvertURLIntent
        .intentInvalidURL: "输入的不是有效URL。请提供网页链接。",
        .intentNotWebPage: "这似乎不是网页。CrossX只能将网页URL转换为EPUB——不支持图片、文件和其他内容。",
        .intentFetchFailed: "获取网页失败：%@",
        .intentExtractFailed: "无法从此页面提取可读内容。",
        .intentEPUBFailed: "创建EPUB文件失败：%@",
        .intentQueueFailed: "无法将EPUB保存到队列：%@",
        .intentProvideURL: "请提供要转换的网页URL。",
        .intentQueued: "已排队「%@」（%@）",
        .intentItemsWaiting: "%d 个项目等待发送。",

        // Debug Logs
        .debugLogs: "调试日志",
        .debugLogsClear: "清除日志",
        .debugLogsClearTitle: "清除调试日志？",
        .debugLogsClearMessage: "所有调试日志将被永久删除。",
        .debugLogsCopyAll: "全部复制",
        .debugLogsShare: "分享为文件",
        .debugLogsEmpty: "暂无日志",
        .debugLogsEmptyDescription: "使用应用时调试事件将在此显示。",
        .debugLogsEntryCount: "%d 条记录",
        .clearDebugLogs: "清除调试日志",
        .clearDebugLogsTitle: "清除调试日志？",
        .clearDebugLogsMessage: "所有调试日志将被永久删除。",
        .storageAndLogsDescription: "数据库包括转换历史和文件活动日志。网页缓存存储已获取的网页以加快重新转换速度。调试日志有助于报告错误时共享。",
        .reportBugTitle: "报告错误",
        .reportBugMessage: "是否将调试日志复制到剪贴板？附带日志有助于更快地诊断问题。",
        .copyLogsAndReport: "复制日志并报告",
        .reportWithoutLogs: "不附带日志报告",
        .debugFilterAll: "全部",
        .debugFilterErrors: "错误",
        .debugFilterQueue: "队列",
        .debugFilterDevice: "设备",
        .debugFilterConversion: "转换",
        .debugFilterRSS: "RSS",
        .queueCircuitBreaker: "连续 %d 次失败后已中止。设备可能无法连接。",

        // RSS Feed
        .rssFeeds: "RSS 订阅",
        .rssNew: "新",
        .rssRefreshing: "正在刷新订阅...",
        .rssTapToSetup: "点击设置您的RSS订阅",
        .rssManageFeeds: "管理订阅",
        .rssAllFeeds: "全部订阅",
        .rssFeedCount: "%d 个订阅",
        .rssAddNewFeed: "添加订阅",
        .rssEnterFeedURL: "输入网站或订阅链接",
        .rssValidating: "验证中...",
        .rssAddFeed: "添加订阅",
        .rssAddFeedFooter: "输入网站URL（如 techcrunch.com）或直接输入RSS/Atom订阅链接。系统会自动发现订阅。",
        .rssYourFeeds: "我的订阅",
        .rssNoFeedsTitle: "尚未设置RSS订阅",
        .rssNoFeedsDescription: "添加您喜欢的新闻来源，将文章推送到电子阅读器。",
        .rssAddFirstFeed: "添加第一个订阅",
        .rssNoArticles: "没有可用文章。下拉刷新。",
        .rssSelectAllNew: "全选新文章",
        .rssDeselectAll: "取消全选",
        .rssSelectedCount: "已选 %d 篇",
        .rssConvertAndSend: "发送 (%d)",
        .rssConvertAndQueue: "排队 (%d)",
        .rssConverting: "正在转换 %d/%d...",
        .rssSent: "已发送",
        .rssQueued: "已排队",
        .rssFailed: "失败",
        .rssSentArticles: "已发送 %d 篇文章到设备",
        .rssQueuedArticles: "已排队 %d 篇文章",
        .rssSentAndQueued: "已发送 %d 篇，排队 %d 篇",
        .rssFailedArticles: "%d 篇文章转换失败",
        .rssInvalidFeedURL: "请输入有效的URL。",
        .rssFeedAlreadyExists: "订阅已存在：%@",
        .rssInvalidURL: "无效的文章链接",

        // AppLanguage Display Names
        .languageSystemDefault: "跟随系统",
        .languageEnglish: "English",
        .languageChinese: "中文 (简体)",
    ]

    // MARK: - Lookup Methods

    /// Returns the localized string for the given key and language code.
    /// Falls back to English, then to the raw key name.
    static func string(for key: Key, language: String) -> String {
        if let table = translations[language], let value = table[key] {
            return value
        }
        if let value = en[key] {
            return value
        }
        return key.rawValue
    }

    /// Returns the localized string with format arguments applied.
    /// Falls back to English, then to the raw key name.
    static func string(for key: Key, language: String, _ arguments: CVarArg...) -> String {
        let format = string(for: key, language: language)
        return String(format: format, arguments: arguments)
    }
}
