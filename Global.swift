@objc
protocol GlobalsProtocol {
    static var DROPBOX_KEY: String { get }
    static var DROPBOX_SECRET: String { get }
}

@objc
class Globals: NSObject, GlobalsProtocol {
    static let DROPBOX_KEY = "m2e4d2ht2khynh3"

    // NOTE: For this to compile, you must add a file called Global+Private.swift as a sibling to this file
    // and define the OAuth 2 app secret with an extension of Globals.
}
