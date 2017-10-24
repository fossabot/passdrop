//
//  KdbWriter.swift
//  PassDrop
//
//  Created by Rudis Muiznieks on 8/7/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

class KdbWriter: NSObject {
    var lastError = ""
    var retval: kpass_retval = kpass_success
    
    func saveDatabase(
        _ database: UnsafeMutablePointer<kpass_db>!,
        withPassword pw: UnsafeMutablePointer<UInt8>,
        toFile path: String
    ) -> Bool {
        let size = Int(kpass_db_encrypted_len(database))
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        var success = false
        retval = kpass_encrypt_db(database, pw, buf)
        if retval == kpass_success {
            let content = Data(bytes: buf, count: size)
            (content as NSData).write(to: URL(fileURLWithPath: path), atomically: false)
            success = true
        } else {
            lastError = "There was an error encrypting the database."
        }
        free(buf);
        return success;
    }
}

