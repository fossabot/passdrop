extension String {
    func appendingPathExtension(_ str: String) -> String? {
        return (self as NSString).appendingPathExtension(str)
    }

    func appendingPathComponent(_ str: String) -> String {
        return (self as NSString).appendingPathComponent(str)
    }

    var lastPathComponent: String {
        return (self as NSString).lastPathComponent
    }

    var deletingLastPathComponent: String {
        return (self as NSString).deletingLastPathComponent
    }
}
