//
//  KdbReader.m
//  PassDrop
//
//  Created by Rudis Muiznieks on 2/8/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "KdbReader.h"


@implementation KdbReader

@synthesize databaseFilePath;
@synthesize lastError;

- (id) initWithKdbFile:(NSString*)filePath usingPassword:(NSString*)password {
	lastError = nil;
	if((self = [super init])){
		// load database from file
		self.databaseFilePath = [NSString stringWithString:filePath];
		NSData *dbData = [NSData dataWithContentsOfFile:filePath];
		int length = [dbData length];
		const void *bytes = [dbData bytes];
		uint8_t *data = (uint8_t*)bytes;
		kpassDb = malloc(sizeof(kpass_db));

		// read encrypted database
		retval = kpass_init_db(kpassDb, data, length);
		if(retval != kpass_success){
			self.lastError = @"There was an error loading the database.";
		} else {		
			// hash the password
			kpassPw = malloc(sizeof(uint8_t)*32);
			const char *cPw = [password cStringUsingEncoding:NSUTF8StringEncoding];
			retval = kpass_hash_pw(kpassDb, cPw, kpassPw);
			if(retval != kpass_success){
				self.lastError = @"There was an error with that password.";
			} else {
				// perform initial decryption
				retval = kpass_decrypt_db(kpassDb, kpassPw);
				if(retval != kpass_success){
					self.lastError = @"Could not decrypt the database. Please verify your password.";
				}
			}
		}
	}
	return self;
}

- (BOOL)hasError {
	return retval != kpass_success;
}

static int compareGroup(const void* lhs_, const void* rhs_) {
    const kpass_group* lhs = *(const kpass_group**)lhs_;
    const kpass_group* rhs = *(const kpass_group**)rhs_;
    if (lhs->name == NULL && rhs->name == NULL) {
        return 0;
    } else if (lhs->name == NULL) {
        return -1;
    } else if (rhs->name == NULL) {
        return 1;
    } else {
        return strcasecmp(lhs->name, rhs->name);
    }
}

static int compareEntry(const void* lhs_, const void* rhs_) {
    const kpass_entry* lhs = *(const kpass_entry**)lhs_;
    const kpass_entry* rhs = *(const kpass_entry**)rhs_;
    if (lhs->title == NULL && rhs->title == NULL) {
        return 0;
    } else if (lhs->title == NULL) {
        return -1;
    } else if (rhs->title == NULL) {
        return 1;
    } else {
        return strcasecmp(lhs->title, rhs->title);
    }
}

- (KdbGroup*)getRootGroupForDatabase:(id<Database>)database {
    [database setKpDatabase:kpassDb];
    [database setPwHash:kpassPw];

    qsort(kpassDb->groups, kpassDb->groups_len, sizeof(kpassDb->groups[0]), compareGroup);
    qsort(kpassDb->entries, kpassDb->entries_len, sizeof(kpassDb->entries[0]), compareEntry);

	return [[[KdbGroup alloc] initRootGroupWithCount:kpassDb->groups_len subGroups:kpassDb->groups andCount:kpassDb->entries_len groupEntries:kpassDb->entries forDatabase:database] autorelease];
}

- (kpass_db*)kpDatabase {
    return kpassDb;
}

- (void) dealloc {
	[lastError release];
	[databaseFilePath release];
	[super dealloc];
}

@end
