//
//  DropboxBrowserController.swift
//  PassDrop
//
//  Created by Rudis Muiznieks on 2/5/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

import UIKit

class DropboxBrowserController: UIPullToReloadTableViewController, DBRestClientDelegate, NewDatabaseDelegate {
    var restClient: DBRestClient!
    var myPath: String
    var isLoaded = false
    var loadingView: LoadingView!
    var metadataHash: String?
    var dirContents: [DBMetadata]
    var dirBrowsers: [IndexPath: DropboxBrowserController]
    var tempDbId: String!
    var tempPath: String!
    var dbManager: DatabaseManager!
    
    static var networkIndicatorReq = 0
    
    init(path: String) {
        self.myPath = path
        self.dirContents = []
        self.dirBrowsers = [:]
        super.init(nibName: nil, bundle: nil)
        DropboxBrowserController.networkIndicatorReq = 0
        self.metadataHash = nil
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Actions

    func newButtonClicked() {
        let ndbvc = NewDatabaseViewController(nibName: "EditViewController", bundle: nil)
        ndbvc.location = myPath
        ndbvc.delegate = self
        navigationController?.pushViewController(ndbvc, animated: true)
    }
    
    func newDatabaseCreated(_ path: String!) {
        let localFile = dbManager.getLocalFilenameForDatabase(dbManager.getIdentifierForDatabase(path), forNewFile: true)
        networkRequestStarted()
        tempDbId = path
        restClient.loadFile(path, intoPath: localFile)
    }
    
    // MARK: View lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
            
        restClient = DBRestClient(session: DBSession.shared())
        restClient.delegate = self
        let newButton = UIBarButtonItem(title: "New", style: .plain, target: self, action: #selector(newButtonClicked))
        navigationItem.rightBarButtonItem = newButton
        
        edgesForExtendedLayout = []
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isLoaded {
            refreshDirectory()
        }
    }
    
    // MARK: PullDown implementation
    
    override func pullDownToReloadAction() {
        refreshDirectory()
    }

    func refreshDirectory() {
        networkRequestStarted()
        if let metadataHash = metadataHash {
            restClient.loadMetadata(myPath, withHash: metadataHash)
        } else {
            restClient.loadMetadata(myPath)
        }
    }

    // MARK: Error UI
    
    func alertMessage(_ message: String, withTitle alertTitle: String) {
        let alert = UIAlertView(title: alertTitle, message: message, delegate: nil, cancelButtonTitle: "OK")
        alert.show()
    }

    func alertError(_ error: Error!) {
        let msg = ((error as NSError).userInfo["error"] as? String) ?? "Dropbox reported an unknown error."
        let alert = UIAlertView(title: "Dropbox Error", message: msg, delegate: nil, cancelButtonTitle: "OK")
        alert.show()
    }

     // MARK: Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Return the number of rows in the section.
        return dirContents.count
    }
    
    // Customize the appearance of table view cells.
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        struct Static {
            static let CellIdentifier = "Cell"
        }
        
        let cell: UITableViewCell
        
        switch tableView.dequeueReusableCell(withIdentifier: Static.CellIdentifier) {
        case .some(let c):
            cell = c
        case .none:
            cell = UITableViewCell(style: .default, reuseIdentifier: Static.CellIdentifier)
            cell.textLabel?.textColor = UIColor.black
        }
        
        let cellData = dirContents[indexPath.row]
        let fileName = cellData.path.lastPathComponent
        if cellData.isDirectory {
            cell.accessoryType = .disclosureIndicator
            cell.imageView?.image = UIImage(named: "folder_icon.png")
            cell.isUserInteractionEnabled = true
            cell.textLabel?.textColor = UIColor.black
        } else {
            if fileName.hasSuffix(".kdb") {
                cell.imageView?.image = UIImage(named: "keepass_icon.png")
                cell.isUserInteractionEnabled = true
                cell.textLabel?.textColor = UIColor.black
            } else {
                cell.imageView?.image = UIImage(named: "unknown_icon.png")
                //cell.userInteractionEnabled = NO;
                cell.textLabel?.textColor = UIColor.lightGray
            }
        }
        cell.textLabel?.text = fileName
        
        return cell
    }

    /*
            /*
             // Override to support conditional editing of the table view.
             - (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
             // Return NO if you do not want the specified item to be editable.
             return YES;
             }
             */
            
            
            /*
             // Override to support editing the table view.
             - (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
             
             if (editingStyle == UITableViewCellEditingStyleDelete) {
             // Delete the row from the data source.
             [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
             }
             else if (editingStyle == UITableViewCellEditingStyleInsert) {
             // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
             }
             }
             */
            
            
            /*
             // Override to support rearranging the table view.
             - (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
             }
             */
            
            
            - (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
                return YES;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations{
    return UIInterfaceOrientationMaskAll;
}

-(BOOL)shouldAutorotate{
    return YES;
}


#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    DBMetadata *cellData = [dirContents objectAtIndex:[indexPath row]];
    if(cellData.isDirectory){
        if([dirBrowsers objectForKey:cellData.path] == nil){
            DropboxBrowserController *dirBrowser = [[[DropboxBrowserController alloc] initWithPath:cellData.path] autorelease];
            dirBrowser.dbManager = dbManager;
            dirBrowser.title = [cellData.path lastPathComponent];
            [dirBrowsers setValue:dirBrowser forKey:cellData.path];
        }
        [self.navigationController pushViewController:[dirBrowsers objectForKey:cellData.path] animated:YES];
    } else {
        //if([cellData.path hasSuffix:@".kdb"]){
        if([dbManager databaseExists:[dbManager getIdentifierForDatabase:cellData.path]]){
            [self alertMessage:@"That database has already been added. You cannot add the same database more than once." withTitle:@"Oops!"];
        } else {
            NSString *localFile = [dbManager getLocalFilenameForDatabase:[dbManager getIdentifierForDatabase:cellData.path] forNewFile:YES];
            [self networkRequestStarted];
            self.tempDbId = [NSString stringWithString:cellData.path];
            [restClient loadFile:cellData.path intoPath:localFile];
        }
        //}
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}
*/
    
    // MARK: Dropbox/RestClient
    func setWorking(_ working: Bool) {
        view.isUserInteractionEnabled = !working
        self.navigationController?.view.isUserInteractionEnabled = !working
        if working {
            loadingView = LoadingView(title: "Loading")
            loadingView.show()
        } else {
            loadingView.dismiss(animated: false)
            loadingView = nil
        }
    }
    
    func networkRequestStarted() {
        let app = UIApplication.shared
        app.isNetworkActivityIndicatorVisible = true
        if DropboxBrowserController.networkIndicatorReq == 0 {
            setWorking(true)
        }
        DropboxBrowserController.networkIndicatorReq += 1
    }
    
    func networkRequestStopped() {
        DropboxBrowserController.networkIndicatorReq -= 1
        if DropboxBrowserController.networkIndicatorReq <= 0 {
            let app = UIApplication.shared
            app.isNetworkActivityIndicatorVisible = false
            setWorking(false)
            pullToReloadHeaderView.finishReloading(tableView, animated: true)
        }
    }
    
    func restClient(_ client: DBRestClient!, loadedFile destPath: String!) {
        // now that we downloaded the file, we need to get the hash value for it
        self.tempPath = destPath
        restClient.loadMetadata(tempDbId)
    }
    
    func restClient(_ client: DBRestClient!, loadFileFailedWithError error: Error!) {
        networkRequestStopped()
        alertError(error)
        tempDbId = nil
    }
    
    func restClient(_ client: DBRestClient!, loadedMetadata metadata: DBMetadata!) {
        networkRequestStopped()
        if metadata.isDirectory {
            // if it was a directory it means we refreshed this view
            isLoaded = true
            metadataHash = metadata.hash
            dirContents = metadata.contents as! [DBMetadata]
            tableView.reloadData()
        } else {
            // otherwise it means we justdownloaded a database for the lastmod date
            let dbId = dbManager.getIdentifierForDatabase(tempDbId)
            dbManager.createNewDatabaseNamed(dbId.lastPathComponent, withId: dbId, withLocalPath: tempPath, lastModified: metadata.lastModifiedDate, revision: metadata.revision)
            tempDbId = nil
            tempPath = nil
        }
    }

    func restClient(_ client: DBRestClient!, metadataUnchangedAtPath path: String!) {
        isLoaded = true
        networkRequestStopped()
    }
    
    func restClient(_ client: DBRestClient!, loadMetadataFailedWithError error: Error!) {
        isLoaded = false
        alertError(error)
        dirContents = []
        tableView.reloadData()
        networkRequestStopped()
    }

    // MARK: Memory management
    
    func reset() {
        for browser in dirBrowsers.values {
            browser.reset()
        }
        dirBrowsers = [:]
        isLoaded = false
        metadataHash = nil
        dirContents = []
        tableView.reloadData()
    }
    
    deinit {
        reset()
    }
}
