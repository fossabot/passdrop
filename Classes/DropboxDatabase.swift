//
//  DropboxDatabase.h
//  PassDrop
//
//  Created by Rudis Muiznieks on 2/5/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

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

class DropboxDatabase: NSObject, Database, DBRestClientDelegate {
    let restClient: DBRestClient
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
    var revision: Int64 = 0
    var rev: String?

    private var mode = Mode.none
    private var tempMeta: DBMetadata!

    override init() {
        restClient = DBRestClient(session: DBSession.shared())
        super.init()
        restClient.delegate = self
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
        restClient.loadMetadata(location() + ".lock")
    }

    func rootGroup() -> KdbGroup {
        return kdbGroup
    }

    func uploadLockFile() {
        let dataPath = DatabaseManager.dataPath
        let fileManager = FileManager()
        let fname = location().lastPathComponent + ".lock"
        let localLock = dataPath.appendingPathComponent("lock")
        if !fileManager.fileExists(atPath: localLock) {
            fileManager.createFile(atPath: localLock, contents: Data(), attributes: nil)
        }

        mode = .loadingLockFile
        restClient.uploadFile(fname, toPath:location().deletingLastPathComponent, fromPath: localLock)
    }

    func removeLock() {
        restClient.deletePath(location() + ".lock")
    }

    func update() {
        // get metedata for last modified date
        mode = .loadingDBFile
        let fm = FileManager()
        isDirty = fm.fileExists(atPath: (localPath as NSString).appendingPathExtension("tmp")!)
        restClient.loadMetadata(location())
    }

    func upload() {
        let fileManager = FileManager()
        let newDb = localPath.appendingPathExtension("tmp")!
        if fileManager.fileExists(atPath: newDb) {
            restClient.uploadFile(location().lastPathComponent, toPath: location().deletingLastPathComponent, fromPath: newDb)
        } else {
            savingDelegate.database?(self, saveFailedWithReason: "The modified database could not be found.")
        }
    }

    func sync(withForce force: Bool) {
        if !force {
            // check if we're overwriting other changes
            mode = .sendingDBFile
            restClient.loadMetadata(location())
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
        revision = 0
        rev = nil
        isDirty = false
        dbManager.updateDatabase(self)

        let fm = FileManager()
        try? fm.removeItem(atPath: localPath.appendingPathExtension("tmp")!)
    }

    // MARK: DBRestClientDelegate

    func restClient(_ client: DBRestClient, loadedMetadata metadata: DBMetadata) {
        switch mode {
        case .none:
            break
        case .loadingLockFile:
            if !metadata.isDeleted {
                delegate.databaseWasAlreadyLocked?(self)
            } else {
                uploadLockFile()
            }
        case .loadingDBFile:
            if !metadata.isDeleted {
                if self.revision != metadata.revision {
                    if self.isDirty {
                        delegate.databaseUpdateWouldOverwriteChanges?(self)
                    } else {
                        // need to download newer revision
                        tempMeta = metadata
                        restClient.loadFile(location(), intoPath: localPath)
                    }
                } else {
                    // already have latest revision
                    delegate.databaseUpdateComplete?(self)
                }
            } else {
                delegate.databaseWasDeleted?(self)
            }
        case .sendingDBFile:
            if !metadata.isDeleted {
                if self.revision != metadata.revision {
                    savingDelegate.databaseSyncWouldOverwriteChanges?(self)
                } else {
                    self.upload()
                }
            } else {
                savingDelegate.databaseWasDeleted?(self)
            }
        case .updatingDBRevision:
            self.revision = metadata.revision
            self.rev = metadata.rev
            self.isDirty = false
            self.lastSynced = Date()
            dbManager.updateDatabase(self)
            savingDelegate.databaseSyncComplete?(self)
        }
    }

    func restClient(_ client: DBRestClient!, loadMetadataFailedWithError error: Error!) {
        let err = error as NSError
        switch mode {
        case .none:
            break
        case .loadingLockFile:
            if err.code == 404 {
                self.uploadLockFile()
            } else {
                let msg = error.errorMsg ?? "There was an error locking the database."
                delegate.database?(self, failedToLockWithReason: msg)
            }
        case .loadingDBFile:
            let msg = error.errorMsg ?? "There was an error updating the database."
            delegate.database?(self, updateFailedWithReason: msg)
        case .sendingDBFile:
            let msg = error.errorMsg ?? "There was an error uploading the database."
            savingDelegate.database?(self, syncFailedWithReason: msg)
        case .updatingDBRevision:
            let msg = error.errorMsg ?? "The database was uploaded to Dropbox, but there was an error retrieving the revision number afterwards.";
            savingDelegate.database?(self, syncFailedWithReason: msg)
        }
    }

    func restClient(_ client: DBRestClient!, uploadedFile destPath: String!, from srcPath: String!) {
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
                restClient.loadMetadata(location())
            }
            catch {
                savingDelegate.database?(self, syncFailedWithReason: "The database was uploaded successfully, but a filesystem error prevented the local copy from being updated.")
            }
        default:
            break
        }
    }

    func restClient(_ client: DBRestClient!, uploadFileFailedWithError error: Error!) {
        switch mode {
        case .loadingLockFile:
            let msg = error.errorMsg ?? "There was an error uploading the lock file."
            delegate.database?(self, failedToLockWithReason: msg)
        case .sendingDBFile:
            let msg = error.errorMsg ?? "There was an error uploading the database file."
            savingDelegate.database?(self, syncFailedWithReason: msg)
        default:
            break
        }
    }

    func restClient(_ client: DBRestClient!, deletedPath path: String!) {
        delegate.databaseLockWasRemoved?(self)
    }

    func restClient(_ client: DBRestClient!, deletePathFailedWithError error: Error!) {
        let msg = error.errorMsg ?? "There was an error removing the lock file."
        delegate.database?(self, failedToRemoveLockWithReason: msg)
    }

    func restClient(_ client: DBRestClient!, loadedFile destPath: String!) {
        if mode == .loadingDBFile {
            // update local metadata
            self.revision = tempMeta.revision
            self.rev = tempMeta.rev
            self.lastModified = tempMeta.lastModifiedDate
            self.lastSynced = Date()
            dbManager.updateDatabase(self)
            delegate.databaseUpdateComplete?(self)
        }
    }

    func restClient(_ client: DBRestClient!, loadFileFailedWithError error: Error!) {
        if mode == .loadingDBFile { // loading latest revision
            tempMeta = nil
            let msg = error.errorMsg ?? "There was an error removing the lock file."
            delegate.database?(self, updateFailedWithReason: msg)
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
