class Globals: NSObject {
    @objc
    static var DROPBOX_KEY: String {
        return ProcessInfo.processInfo.environment["PASSDROP_APP_KEY"]!
    }

    @objc
    static var DROPBOX_SECRET: String {
        return ProcessInfo.processInfo.environment["PASSDROP_APP_SECRET"]!
    }
}
