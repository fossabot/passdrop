import SwiftyDropbox

fileprivate enum Mode: Int {
    case none = 0
    case loadingLockFile = 1
    case loadingDBFile = 2
    case sendingDBFile = 3
    case updatingDBRevision = 4
}

extension Error {
    public var errorMsg: String? {
        return (self as NSError).userInfo["error"] as? String
    }
}

class DropboxDatabase: NSObject, Database {
    let dropboxClient: DropboxClient
    var localPath: String!
    var identifier: String!
    var name: String!
    var lastModified: Date!
    var lastSynced: Date!
    var delegate: DatabaseDelegate!
    var savingDelegate: DatabaseDelegate!
    var lastError_: String!
    var kdbGroup: KdbGroup!
    var isReadOnly = false
    var kpDatabase: UnsafeMutablePointer<kpass_db>?
    var pwHash: UnsafeMutablePointer<UInt8>?
    var isDirty = false
    var dbManager: DatabaseManager!
    var rev: String?

    private var mode = Mode.none

    override init() {
        guard let dbClient = DropboxClientsManager.authorizedClient else {
            fatalError("DropboxDatabase needs an authorized client")
        }
        dropboxClient = dbClient
        super.init()
    }

    deinit {
        if kpDatabase != nil {
            kpass_free_db(kpDatabase)
        }
        if pwHash != nil {
            free(pwHash)
        }
    }

    // MARK: Database loading stuff

    func location() -> String! {
        return (identifier as NSString).substring(from: 8) // trim the "/dropbox" from the identifier to get the location
    }

    func load(withPassword password: String) -> Bool {
        var success = true

        let localPathTmp = localPath.appendingPathExtension("tmp")!

        let fm = FileManager()
        isDirty = fm.fileExists(atPath: localPathTmp)

        let kdb = KdbReader(kdbFile: isDirty ? localPathTmp : localPath, usingPassword: password)!
        if kdb.hasError() {
            lastError_ = kdb.lastError
            success = false
        } else {
            kdbGroup = kdb.getRootGroup(for: self)
        }
        return success;
    }

    func lastError() -> String! {
        return lastError_
    }

    func lockForEditing() {
        mode = .loadingLockFile
        dropboxClient.files.getMetadata(
            path: location() + ".lock",
            includeMediaInfo: false,
            includeDeleted: true,
            includeHasExplicitSharedMembers: false
        ).response { [weak self] response, error in
            if let response = response {
                self?.restClient(loadedMetadata: response)
            } else if let error = error {
                self?.restClient(loadMetadataFailedWithError: error)
            }
        }
    }

    func rootGroup() -> KdbGroup {
        return kdbGroup
    }

    func uploadLockFile() {
        let dataPath = DatabaseManager.dataPath
        let fileManager = FileManager()
        let localLock = dataPath.appendingPathComponent("lock")
        if !fileManager.fileExists(atPath: localLock) {
            fileManager.createFile(atPath: localLock, contents: Data(), attributes: nil)
        }

        mode = .loadingLockFile
        dropboxClient.files.upload(path: location() + ".lock", input: URL(fileURLWithPath: localLock)).response {
            [weak self] response, error in
            if let _ = response {
                self?.restClient(uploadedFile: ())
            } else if let error = error {
                self?.restClient(uploadFileFailedWithError: error)
            }
        }
    }

    func removeLock() {
        dropboxClient.files.delete(path: location() + ".lock").response { [weak self] response, error in
            if let _ = response {
                self?.restClient(deletedPath: ())
            } else if let error = error {
                self?.restClient(deletePathFailedWithError: error)
            }
        }
    }

    func update() {
        // get metadata for last modified date
        mode = .loadingDBFile
        let fm = FileManager()
        isDirty = fm.fileExists(atPath: (localPath as NSString).appendingPathExtension("tmp")!)
        dropboxClient.files.getMetadata(path: location()).response { [weak self] response, error in
            if let response = response {
                self?.restClient(loadedMetadata: response)
            } else if let error = error {
                self?.restClient(loadMetadataFailedWithError: error)
            }
        }
    }

    func upload() {
        let fileManager = FileManager()
        let newDb = localPath.appendingPathExtension("tmp")!
        if fileManager.fileExists(atPath: newDb) {
            dropboxClient.files.upload(path: location(), input: URL(fileURLWithPath: newDb)).response {
                [weak self] response, error in
                if let _ = response {
                    self?.restClient(uploadedFile: ())
                } else if let error = error {
                    self?.restClient(uploadFileFailedWithError: error)
                }
            }
        } else {
            savingDelegate.database?(self, saveFailedWithReason: "The modified database could not be found.")
        }
    }

    func sync(withForce force: Bool) {
        if !force {
            // check if we're overwriting other changes
            mode = .sendingDBFile
            dropboxClient.files.getMetadata(path: location()).response { [weak self] response, error in
                if let response = response {
                    self?.restClient(loadedMetadata: response)
                } else if let error = error {
                    self?.restClient(loadMetadataFailedWithError: error)
                }
            }
        } else {
            mode = .sendingDBFile
            upload()
        }
    }

    // MARK: Database stuff

    func save() {
        // save to temp file
        let writer = KdbWriter()
        let tmpPath = localPath + ".tmp"
        if writer.saveDatabase(kpDatabase, withPassword: pwHash, toFile: tmpPath) {
            // call success method on delegate
            if let cb = savingDelegate.databaseSaveComplete {
                cb(self)
                isDirty = true
                lastModified = Date()
                dbManager.updateDatabase(self)
            }
        } else {
            // call fail method on delegate
            savingDelegate.database?(self, saveFailedWithReason: writer.lastError)
        }
    }

    func save(withPassword password: String!) {
        let cPw = password.cString(using: .utf8)
        if pwHash != nil {
            free(pwHash)
        }
        pwHash = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
        let retval = kpass_hash_pw(kpDatabase, cPw, pwHash)
        if retval != kpass_success {
            savingDelegate.database?(self, saveFailedWithReason: "There was a problem with your new password.")
            return
        }
        save()
    }

    func nextGroupId() -> UInt32 {
        guard let db = kpDatabase?.pointee else {
            return arc4random()
        }

        var found = false
        var nextId: UInt32
        repeat {
            nextId = arc4random()
            found = true
            for group in UnsafeBufferPointer(start: db.groups, count: Int(db.groups_len)) {
                if group?.pointee.id == nextId {
                    found = false
                    continue
                }
            }
        } while !found
        return nextId
    }

    func discardChanges() {
        rev = nil
        isDirty = false
        dbManager.updateDatabase(self)

        let fm = FileManager()
        try? fm.removeItem(atPath: localPath.appendingPathExtension("tmp")!)
    }

    // MARK: DBRestClientDelegate

    func restClient(loadedMetadata metadata: Files.Metadata) {
        switch mode {
        case .none:
            break
        case .loadingLockFile:
            if let _ = metadata as? Files.DeletedMetadata {
                uploadLockFile()
            } else {
                delegate.databaseWasAlreadyLocked?(self)
            }
        case .loadingDBFile:
            if let _ = metadata as? Files.DeletedMetadata {
                delegate.databaseWasDeleted?(self)
            } else if let fileMetadata = metadata as? Files.FileMetadata {
                if self.rev != fileMetadata.rev {
                    if self.isDirty {
                        delegate.databaseUpdateWouldOverwriteChanges?(self)
                    } else {
                        // need to download newer revision
                        let destURL = URL(fileURLWithPath: localPath)
                        let destination: (URL, HTTPURLResponse) -> URL = { temporaryURL, response in
                            return destURL
                        }
                        dropboxClient.files.download(path: location(), overwrite: true, destination: destination).response {
                            [weak self] response, error in
                            if let _ = response {
                                self?.restClient(loadedFile: fileMetadata)
                            } else if let error = error {
                                self?.restClient(loadFileFailedWithError: error)
                            }
                        }
                        //dropboxClient.loadFile(location(), intoPath: localPath)
                    }
                } else {
                    // already have latest revision
                    delegate.databaseUpdateComplete?(self)
                }
            }
        case .sendingDBFile:
            if let _ = metadata as? Files.DeletedMetadata {
                savingDelegate.databaseWasDeleted?(self)
            } else if let fileMetadata = metadata as? Files.FileMetadata {
                if self.rev != fileMetadata.rev {
                    savingDelegate.databaseSyncWouldOverwriteChanges?(self)
                } else {
                    self.upload()
                }
            }
        case .updatingDBRevision:
            self.rev = (metadata as? Files.FileMetadata)?.rev
            self.isDirty = false
            self.lastSynced = Date()
            dbManager.updateDatabase(self)
            savingDelegate.databaseSyncComplete?(self)
        }
    }

    func restClient(loadMetadataFailedWithError error: CallError<Files.GetMetadataError>) {
        switch mode {
        case .none:
            break
        case .loadingLockFile:
            switch error {
            case .routeError(let lookupErrorBox, /*userMessage*/_, /*errorSummary*/_, /*requestId*/_):
                if case .path(.notFound) = lookupErrorBox.unboxed {
                    self.uploadLockFile()
                    return
                }
            default:
                delegate.database?(self, failedToLockWithReason: error.description)
            }
        case .loadingDBFile:
            delegate.database?(self, updateFailedWithReason: error.description)
        case .sendingDBFile:
            savingDelegate.database?(self, syncFailedWithReason: error.description)
        case .updatingDBRevision:
            savingDelegate.database?(self, syncFailedWithReason: error.description)
        }
    }
    
    func restClient(uploadedFile: ()) {
        switch mode {
        case .loadingLockFile:
            delegate.databaseWasLocked?(forEditing: self)
        case .sendingDBFile:
            let tmpFile = localPath.appendingPathExtension("tmp")!
            let fm = FileManager()
            do {
                try fm.removeItem(atPath: localPath)
                try fm.copyItem(atPath: tmpFile, toPath: localPath)
                try fm.removeItem(atPath: tmpFile)

                mode = .updatingDBRevision
                dropboxClient.files.getMetadata(path: location()).response { [weak self] response, error in
                    if let response = response {
                        self?.restClient(loadedMetadata: response)
                    } else if let error = error {
                        self?.restClient(loadMetadataFailedWithError: error)
                    }
                }
            }
            catch {
                savingDelegate.database?(self, syncFailedWithReason: "The database was uploaded successfully, but a filesystem error prevented the local copy from being updated.")
            }
        default:
            break
        }
    }

    func restClient(uploadFileFailedWithError error: CallError<Files.UploadError>) {
        switch mode {
        case .loadingLockFile:
            delegate.database?(self, failedToLockWithReason: error.description)
        case .sendingDBFile:
            savingDelegate.database?(self, syncFailedWithReason: error.description)
        default:
            break
        }
    }

    func restClient(deletedPath path: ()) {
        delegate.databaseLockWasRemoved?(self)
    }

    func restClient(deletePathFailedWithError error: CallError<Files.DeleteError>) {
        delegate.database?(self, failedToRemoveLockWithReason: error.description)
    }
 
    func restClient(loadedFile metadata: Files.FileMetadata) {
        if mode == .loadingDBFile {
            // update local metadata
            self.rev = metadata.rev
            self.lastModified = metadata.serverModified
            self.lastSynced = Date()
            dbManager.updateDatabase(self)
            delegate.databaseUpdateComplete?(self)
        }
    }

    func restClient(loadFileFailedWithError error: CallError<Files.DownloadError>) {
        if mode == .loadingDBFile { // loading latest revision
            delegate.database?(self, updateFailedWithReason: error.description)
        }
    }

    // MARK: utility stuff needs to be moved

    func parseDate(_ dtime: UnsafeMutablePointer<UInt8>!) -> Date! {
        var comps = DateComponents()
        let gregorian = NSCalendar(calendarIdentifier: .gregorian)

        let year = (dtime[0] << 6) | (dtime[1] >> 2)
        let mon = ((dtime[1] & 3) << 2) | (dtime[2] >> 6)
        let day = (dtime[2] & 63) >> 1
        let hour = ((dtime[2] & 1) << 4) | (dtime[3] >> 4)
        let min = ((dtime[3] & 15) << 2) | (dtime[4] >> 6)
        let sec = dtime[4] & 63

        comps.year = Int(year)
        comps.month = Int(mon)
        comps.day = Int(day)
        comps.hour = Int(hour)
        comps.minute = Int(min)
        comps.second = Int(sec)

        return gregorian?.date(from: comps)
    }

    func pack(_ date: Date!, toBuffer buffer: UnsafeMutablePointer<UInt8>!) {
        let cal = NSCalendar(calendarIdentifier: .gregorian)!
        var com = cal.components([.year, .month, .day, .hour, .minute, .second], from: date)
        let y = com.year!, mon = com.month!, d=com.day!, h=com.hour!, min=com.minute!, s=com.second!
        buffer[0] = UInt8((y >> 6) & 0x0000003F)
        buffer[1] = UInt8(((y & 0x0000003F) << 2) | ((mon >> 2) & 0x00000003))
        buffer[2] = UInt8(((mon & 0x00000003) << 6) | ((d & 0x0000001F) << 1) | ((h >> 4) & 0x00000001))
        buffer[3] = UInt8(((h & 0x0000000F) << 4) | ((min >> 2) & 0x0000000F))
        buffer[4] = UInt8(((min & 0x00000003) << 6) | (s & 0x0000003F))
    }
}
