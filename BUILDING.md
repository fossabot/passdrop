# Build Notes

The Dropbox OAuth 2 application key is embedded in the source code, but the secret must be defined in a Global+Private.swift file, sibling to Global.swift.

All third-party dependencies are checked in except OpenSSL.  To obtain that dependency, install CocoaPods and run `pod install`.
