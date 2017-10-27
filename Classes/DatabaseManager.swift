import SwiftyDropbox

let kDatabaseName = "name"
let kDatabaseId = "id"
let kDatabaseLocalPath = "path"
let kDatabaseLastModified = "lastmod"
let kDatabaseLastSynced = "synced"
let kDatabaseRev = "rev"

@objc
class DatabaseManager: NSObject {

    static var dataPath: String {
        // for saving state between simulator runs/devices?
        /*
        #if TARGET_IPHONE_SIMULATOR
            return "/Users/rudism/Documents/PassDrop"
        #else
         */
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory,.userDomainMask, true)
        return paths[0].appendingPathComponent("PassDrop")
    }

    let dataPath: String
    let configFile: String
    var databases: [[String: Any]] = []
    var delegate: DatabaseManagerDelegate? = nil
    @objc var activeDatabase: Database? = nil

    override init() {
        let fileManager = FileManager()
        dataPath = DatabaseManager.dataPath

        if !fileManager.fileExists(atPath: dataPath) {
            try? fileManager.createDirectory(atPath: dataPath, withIntermediateDirectories: true, attributes: nil)
        }

        configFile = dataPath.appendingPathComponent("databases2.archive")

        super.init()

        if !fileManager.fileExists(atPath: configFile) {
            self.databases = []
            self.save()
        }

        self.databases = NSKeyedUnarchiver.unarchiveObject(withFile: configFile) as? [[String: Any]] ?? []
    }

    func save() {
        NSKeyedArchiver.archiveRootObject(databases, toFile: configFile)
    }

    @objc
    func getIdentifierForDatabase(_ localId: String) -> String {
        // only supports dropbox right now anyway, so just use the same id
        return "/dropbox" + localId
    }

    func databaseExists(_ dbId: String) -> Bool {
        for dbData in databases {
            if (dbData[kDatabaseId] as? String) == .some(dbId) {
                return true
            }
        }
        return false
    }

    @objc
    func getLocalFilenameForDatabase(_ dbId: String, forNewFile isNew: Bool) -> String {
        let fileManager = FileManager()
        var fileName = dbId.lastPathComponent
        if isNew {
            var count = 0
            let baseFileName = NSString(string: fileName)
            while fileManager.fileExists(atPath: dataPath.appendingPathComponent(fileName)) {
                fileName = NSString(format: "%d_%@", count, baseFileName) as String
                count += 1
            }
        }

        return dataPath.appendingPathComponent(fileName)
    }

    func createNewDatabaseNamed(_ name: String, withId dbId: String, withLocalPath localPath: String, lastModified: Date, rev: String) {
        let dbData: [String: Any] = [
            kDatabaseName: name,
            kDatabaseId: dbId,
            kDatabaseLocalPath: localPath.lastPathComponent,
            kDatabaseLastModified: lastModified,
            kDatabaseRev: rev,
            kDatabaseLastSynced: Date(), // assume that new database was just downloaded prior to creation
        ]
        databases.append(dbData)
        save()
        delegate?.databaseWasAdded(name)
    }

    func moveDatabaseAtIndex(_ fromIndex: Int, toIndex: Int) {
        let db = databases[fromIndex]
        databases.remove(at: fromIndex)
        databases.insert(db, at: toIndex)
        save()
    }

    func deleteDatabaseAtIndex(_ index: Int) {
        // delete the local file
        let filePath = dataPath.appendingPathComponent((databases[index][kDatabaseLocalPath] as! NSString).lastPathComponent)
        let tmpPath = filePath.appendingPathExtension("tmp")!
        let fileManager = FileManager()
        if fileManager.fileExists(atPath: filePath) {
            try? fileManager.removeItem(atPath: filePath)
        }
        if fileManager.fileExists(atPath: tmpPath) {
            try? fileManager.removeItem(atPath: tmpPath)
        }
        databases.remove(at: index)
        save()
    }

    func getDatabaseAtIndex(_ index: Int) -> Database {
        let dbData = databases[index]
        let database = DropboxDatabase()
        database.identifier = dbData[kDatabaseId] as! String
        database.name = dbData[kDatabaseName] as! String
        database.localPath = dataPath.appendingPathComponent((dbData[kDatabaseLocalPath] as! NSString).lastPathComponent)
        database.lastModified = dbData[kDatabaseLastModified] as! Date
        database.rev = (dbData[kDatabaseRev] as? String)
        database.lastSynced = dbData[kDatabaseLastSynced] as! Date
        let fm = FileManager()
        database.isDirty = fm.fileExists(atPath: database.localPath.appendingPathExtension("tmp")!)
        database.dbManager = self
        return database
    }

    func getIndexOfDatabase(_ database: Database) -> Int {
        for (i, db) in databases.enumerated() {
            if .some(database.identifier) == db[kDatabaseId] as? String {
                return i
            }
        }
        return -1
    }

    @objc
    func updateDatabase(_ database: Database) {
        for (i, var dbData) in databases.enumerated() {
            // find the database in our array
            if dbData[kDatabaseId] as? String == .some(database.identifier) {
                dbData[kDatabaseName] = database.name
                dbData[kDatabaseLastModified] = database.lastModified
                dbData[kDatabaseLastSynced] = database.lastSynced
                dbData[kDatabaseRev] = database.rev
                databases[i] = dbData
                save()
                return
            }
        }
    }

    // MARK - memory management

    func dropboxWasReset() {
        while databases.count > 0 {
            deleteDatabaseAtIndex(0)
        }
    }
}

@objc
protocol DatabaseManagerDelegate {
    func databaseWasAdded(_ databaseName: String)
}
