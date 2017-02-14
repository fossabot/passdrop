# Build Notes

The Dropbox application key and secret are set in the build scheme, under Environment Variables.  The two variables are named PASSDROP_APP_KEY and PASSDROP_APP_SECRET.  The app key is also in PassDrop-Info.plist.

All third-party dependencies are checked in except OpenSSL.  To obtain that dependency, install CocoaPods and run `pod install`.
