//
//  KdbReader.swift
//  PassDrop
//
//  Created by Rudis Muiznieks on 2/8/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

class KdbReader: NSObject {
    var databaseFilePath: String
    var lastError: String?
    
    var kpassDb: UnsafeMutablePointer<kpass_db>
    var kpassPw: UnsafeMutablePointer<UInt8>?
    var retval: kpass_retval

    init(kdbFile filePath: String, usingPassword password: String) {
        // load database from file
        self.databaseFilePath = filePath
        let dbData = NSData(contentsOfFile: filePath)!
        let length = dbData.length
        let bytes = dbData.bytes
        let data = bytes.assumingMemoryBound(to: UInt8.self)
        
        kpassDb = UnsafeMutablePointer<kpass_db>.allocate(capacity: 1)
        
        // read encrypted database
        retval = kpass_init_db(kpassDb, data, Int32(length))
        if retval != kpass_success {
            self.lastError = "There was an error loading the database."
        } else {
            // hash the password
            kpassPw = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
            let cPw = password.cString(using: .utf8)
            retval = kpass_hash_pw(kpassDb, cPw, kpassPw)
            if retval != kpass_success {
                self.lastError = "There was an error with that password."
            } else {
                // perform initial decryption
                retval = kpass_decrypt_db(kpassDb, kpassPw)
                if retval != kpass_success {
                    self.lastError = "Could not decrypt the database. Please verify your password."
                }
            }
        }
    }
    
    deinit {
        // this causes a segfault in Database destruction
        //kpassDb.deallocate(capacity: 1)
        //kpassPw?.deallocate(capacity: 32)
    }
    
    var hasError: Bool {
        return retval != kpass_success
    }

    var kpDatabase: UnsafeMutablePointer<kpass_db> {
        return kpassDb
    }

    func getRootGroup(for database: Database) -> KdbGroup {
        database.kpDatabase = kpassDb
        database.pwHash = kpassPw
        
        return KdbGroup(rootGroupWithCount: kpassDb.pointee.groups_len, subGroups: kpassDb.pointee.groups, andCount: kpassDb.pointee.entries_len, groupEntries: kpassDb.pointee.entries, for: database)
    }
}

