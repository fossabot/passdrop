//
//  RootViewController.swift
//  PassDrop
//
//  Created by Rudis Muiznieks on 1/30/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

import UIKit
import SwiftyDropbox

@objc(RootViewController)
class RootViewController: NetworkActivityViewController, DatabaseManagerDelegate, DatabaseDelegate, UIActionSheetDelegate, UIAlertViewDelegate, UITableViewDataSource, UITableViewDelegate {
    
    var settingsView: SettingsViewController!
    var dbManager: DatabaseManager!
    var dbRootView: DropboxBrowserController?
    var extraRows: Int = 0
    var loadingDb: Database!
    var alertMode: Int = 0
    var unlocking: Database!
    var tutorialShown: Bool = false
    
    // MARK: View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
            
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        self.navigationItem.rightBarButtonItem = self.editButtonItem
        self.title = "Databases"
        
        let app = UIApplication.shared.delegate as! PassDropAppDelegate
        dbManager = app.dbManager
        dbManager.delegate = self
 
        settingsView = SettingsViewController()
        settingsView.title = "Settings"

        let settingsButtonItem = UIBarButtonItem(title: "Settings", style: .plain, target: self, action: #selector(settingsButtonClicked))
        navigationItem.leftBarButtonItem = settingsButtonItem
        
        extraRows = 0
        tutorialShown = false
    }
    
    // hack to fix weird bug with the leftbarbuttonitems disappearing
    override func didRotate(from fromInterfaceOrientation: UIInterfaceOrientation) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let sb = navigationItem.leftBarButtonItem!
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: sb.title, style: sb.style, target: sb.target, action: sb.action)
        }
    }
    
    var dropboxIsLinked: Bool {
        return DropboxClientsManager.authorizedClient != nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationItem.rightBarButtonItem?.isEnabled = dropboxIsLinked
        self.view.viewWithTag(1)?.isHidden = dropboxIsLinked
        
        // hack to fix issue with disappearing insert/delete control icons
        if tableView.isEditing {
            tableView.setEditing(false, animated: false)
            tableView.setEditing(true, animated: false)
        } else {
            tableView.reloadData()
        }
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let app = UIApplication.shared.delegate as! PassDropAppDelegate
        if app.prefs.firstLoad && tutorialShown == false {
            app.prefs.save() // sets version
            tutorialShown = false
            if dbManager.databases.count == 0 {
                if !dropboxIsLinked {
                    alertMode = 1
                    let helpView = UIAlertView(title: "Tutorial", message: "Welcome to PassDrop! Since this is your first time using PassDrop, you will need enter your Dropbox credentials on the settings screen.", delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "Settings")
                    helpView.show()
                } else {
                    alertMode = 2
                    let helpView = UIAlertView(title: "Tutorial", message: "Now that you have linked your Dropbox account, you need to create or choose a KeePass 1.x database to use with PassDrop.", delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "Dropbox");
                    helpView.show()
                }
            }
        }
        navigationController?.setToolbarHidden(true, animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        if tableView.isEditing {
            setEditing(false, animated: false)
        }
        super.viewDidDisappear(animated)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    override var shouldAutorotate: Bool {
        return true
    }

    // MARK: Subview Handling
    
    var tableView: UITableView! {
        return view.viewWithTag(10) as! UITableView
    }
    
    // MARK: Actions
    
    func settingsButtonClicked() {
        navigationController?.pushViewController(settingsView, animated: true)
    }
    
    func gotoDropbox() {
        if !dropboxIsLinked {
            alertMode = 1
            let notLinked = UIAlertView(title: "Dropbox Not Linked", message: "Before you can add databases, you must link your Dropbox account from the settings screen. Do you want to do that now?", delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "Settings")
            notLinked.show()
        } else {
            if dbRootView == nil {
                dbRootView = DropboxBrowserController(path: "")
                dbRootView!.dbManager = dbManager
                dbRootView!.title = "Dropbox"
            }
            navigationController?.pushViewController(dbRootView!, animated: true)
        }
    }

    func databaseWasAdded(_ databaseName: String) {
        let app = UIApplication.shared.delegate as! PassDropAppDelegate
        app.prefs.firstLoad = false
        app.prefs.save()
        while navigationController!.viewControllers.count > 1 {
            navigationController?.popViewController(animated: false)
        }
        tableView.insertRows(at: [IndexPath(row: dbManager.databases.count - 1, section: 0)], with: .fade)
    }
    
    func dropboxWasReset() {
        tableView.reloadData()
        dbRootView?.reset()
    }
    
    func alertView(_ alertView: UIAlertView, didDismissWithButtonIndex buttonIndex: Int) {
        if alertMode == 1 && buttonIndex == 1 {
            // means they clicked the settings button
            settingsButtonClicked()
            tutorialShown = false
        } else if alertMode == 2 && buttonIndex == 1 {
            // clicked the dropbox button
            gotoDropbox()
            tutorialShown = false
        } else if alertMode == 3 && buttonIndex == 1 {
            if alertView.textField(at: 0)!.text != "" {
                if unlocking.load(withPassword: alertView.textField(at: 0)!.text!) {
                    self.userUnlockedDatabase(unlocking)
                } else {
                    let alert = UIAlertView(title: "Error", message: unlocking.lastError(), delegate: nil, cancelButtonTitle: "Okay")
                    alert.show()
                }
            } else {
                let alert = UIAlertView(title: "Error", message: "You must enter your password.", delegate: nil, cancelButtonTitle: "Okay")
                alert.show()
            }
        } else if alertMode == 4 {
            databaseUpdateComplete(unlocking)
        } else if buttonIndex == 0 {
            let app = UIApplication.shared.delegate as! PassDropAppDelegate
            app.prefs.firstLoad = false
            app.prefs.save()
        }
    }
    
    func removeLock(_ database: Database) {
        if !database.isReadOnly {
            self.loadingMessage = "Unlocking"
            self.networkRequestStarted()
            database.delegate = self
            database.removeLock()
        }
    }
    
    // MARK: Table view data source
    
    // Customize the number of sections in the table view.
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    // Customize the number of rows in the table view.
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dbManager.databases.count + extraRows
    }

    let kDatabaseName = "name"
    static let cellIdentifier = "Cell"
    
    // Customize the appearance of table view cells.
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        switch tableView.dequeueReusableCell(withIdentifier: RootViewController.cellIdentifier) {
        case .some(let c):
            cell = c
        case .none:
            cell = UITableViewCell(style: .default, reuseIdentifier: RootViewController.cellIdentifier)
        }
        
        if tableView.isEditing && indexPath.row == dbManager.databases.count {
            cell.imageView?.image = nil
            cell.accessoryType = .none
            cell.textLabel?.text = "Add Database"
        } else if indexPath.row < dbManager.databases.count {
            cell.imageView?.image = UIImage(named: "keepass_icon.png")
            cell.accessoryType = .disclosureIndicator
            cell.textLabel?.text = dbManager.databases[indexPath.row][kDatabaseName] as? String
        }
        
        return cell;
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        if indexPath.row == dbManager.databases.count {
            return .insert
        }
        return .delete
    }
    
    func tableView(_ tableView: UITableView, willBeginEditingRowAt willBeginEditingRowAtIndexPath: IndexPath) -> Void {
    }
    
    func tableView(_ tableView: UITableView, didEndEditingRowAt didEndEditingRowAtIndexPath: IndexPath?) -> Void {
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        if tableView.isEditing && extraRows == 0 {
            tableView.setEditing(false, animated: true)
            super.setEditing(false, animated: true)
        }
        tableView.setEditing(editing, animated: animated)
        super.setEditing(editing, animated: animated)
        tableView.allowsSelectionDuringEditing = true
        let paths = [IndexPath(row: dbManager.databases.count, section: 0)]
        if editing {
            extraRows = 1
            tableView.insertRows(at: paths, with: .fade)
        } else {
            extraRows = 0
            tableView.deleteRows(at: paths, with: .fade)
        }
    }

    // Override to support editing the table view.
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            if dbManager.getDatabaseAtIndex(indexPath.row).isDirty {
                let deleteSheet = UIActionSheet(title: "You have unsaved changes to this database that haven't been synced to Dropbox yet. Are you sure you want to delete it?", delegate: self, cancelButtonTitle: "Cancel", destructiveButtonTitle: "Delete")
                deleteSheet.tag = 100 + indexPath.row
                deleteSheet.show(in: view)
            } else {
                dbManager.deleteDatabaseAtIndex(indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .fade)
            }
        }
        else if editingStyle == .insert {
            gotoDropbox()
        }
    }
    
    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        if proposedDestinationIndexPath.row < dbManager.databases.count {
            return proposedDestinationIndexPath
        }
        return IndexPath(row: dbManager.databases.count - 1, section: 0)
    }
    
    // Override to support rearranging the table view.
    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        dbManager.moveDatabaseAtIndex(sourceIndexPath.row, toIndex: destinationIndexPath.row)
    }
    
    // Override to support conditional rearranging of the table view.
    func tableView(
        _ tableView: UITableView,
        canMoveRowAt indexPath: IndexPath
    ) -> Bool {
        // Return NO if you do not want the item to be re-orderable.
        if indexPath.row < dbManager.databases.count {
            return true
        }
        return false
    }
    
    // MARK: Table view delegate

    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        if tableView.cellForRow(at: indexPath)!.isEditing {
            if indexPath.row < dbManager.databases.count {
                let detailViewController = EditDatabaseViewController(nibName: "EditDatabaseViewController", bundle: nil)
                detailViewController.database = dbManager.getDatabaseAtIndex(indexPath.row)
                detailViewController.title = "Details"
                navigationController?.pushViewController(detailViewController, animated: true)
            } else {
                gotoDropbox()
            }
        } else {
            let app = UIApplication.shared.delegate as! PassDropAppDelegate
        
            self.loadingDb = dbManager.getDatabaseAtIndex(indexPath.row)
            self.loadingDb.delegate = self
            
            switch(app.prefs.databaseOpenMode){
            case kOpenModeReadOnly:
                self.loadingDb.isReadOnly = true
                self.completeLoad()
                break;
            case kOpenModeWritable:
                self.completeLoad()
                break;
            case kOpenModeAlwaysAsk:
                let openMode = UIActionSheet(title: nil, delegate: self, cancelButtonTitle: "Cancel", destructiveButtonTitle: nil, otherButtonTitles: "Open Read-Only", "Open Writable")
                openMode.tag = 3
                openMode.show(from: tableView.cellForRow(at: indexPath)!.frame, in: view, animated: true)
                break;
            default:
                break
            }
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func completeLoad() {
        loadingMessage = "Updating"
        self.networkRequestStarted()
        self.loadingDb.update()
    }
    
    // MARK: database delegate
    
    func databaseWasLocked(forEditing database: Database!) {
        database.dbManager.activeDatabase = database // set the active database
        networkRequestStopped()
        let gvc = KdbGroupViewController(nibName: "KdbGroupViewController", bundle: nil)
        gvc.kdbGroup = database.rootGroup()
        gvc.title = database.name
        self.navigationController?.pushViewController(gvc, animated: true)
    }
    
    func databaseWasAlreadyLocked(_ database: Database!) {
        networkRequestStopped()
        let sheet = UIActionSheet(title: "This database has already been locked by another process.", delegate: self, cancelButtonTitle: "Cancel", destructiveButtonTitle: "Recover Lock", otherButtonTitles: "Open Read-Only")
        sheet.tag = 2
        let row = dbManager.getIndexOfDatabase(database)
        if row >= 0 {
            sheet.show(from: self.tableView.cellForRow(at: IndexPath(row: row, section: 0))!.frame, in: view, animated: true)
        } else {
            sheet.show(in: view)
        }
    }
    
    func database(_ database: Database!, failedToLockWithReason reason: String!) {
        networkRequestStopped()
        let alert = UIAlertView(title: "Error", message: reason, delegate: nil, cancelButtonTitle: "Okay")
        alert.show()
    }
    
    func databaseUpdateComplete(_ database: Database!) {
        networkRequestStopped()
        alertMode = 3
        unlocking = database
        let nillish: String = "" // the objective-c passed nil for the message
        let dialog = UIAlertView(title: "Enter Password", message: nillish, delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "Unlock")
        dialog.alertViewStyle = .secureTextInput
        dialog.show()
    }

    func databaseUpdateWouldOverwriteChanges(_ database: Database!) {
        networkRequestStopped()
        alertMode = 4
        unlocking = database
        let alert = UIAlertView(title: "Update Cancelled", message: "The database on Dropbox has changes that would overwrite changes in your local copy. Open the database in writable mode and use the sync button to choose which copy to keep.", delegate: self, cancelButtonTitle: "Okay")
        alert.show()
    }
    
    func databaseWasDeleted(_ database: Database!) {
        networkRequestStopped()
        let sheet = UIActionSheet(title: "This database has been deleted from your Dropbox account. What would you like to do?", delegate: self, cancelButtonTitle: "Cancel", destructiveButtonTitle: nil, otherButtonTitles: "Open Local Copy")
        sheet.tag = 4
        let row = dbManager.getIndexOfDatabase(database)
        if row >= 0 {
            sheet.show(from: tableView.cellForRow(at: IndexPath(row: row, section: 0))!.frame, in: view, animated: true)
        } else {
            sheet.show(in: view)
        }
    }
    
    func database(_ database: Database!, updateFailedWithReason error: String!) {
        networkRequestStopped()
        let openMode = UIActionSheet(title: error, delegate: self, cancelButtonTitle: "Cancel", destructiveButtonTitle: nil, otherButtonTitles: "Read Local Copy")
        openMode.tag = 1
        let row = dbManager.getIndexOfDatabase(database)
        if row >= 0 {
            openMode.show(from: tableView.cellForRow(at: IndexPath(row: row, section: 0))!.frame, in: view, animated: true)
        } else {
            openMode.show(in: view)
        }
    }
    
    func databaseLockWasRemoved(_ database: Database!) {
        networkRequestStopped()
    }
    
    func database(_ database: Database!, failedToRemoveLockWithReason reason: String!) {
        networkRequestStopped()
        let error = UIAlertView(title: "Error", message: "The database lock was missing. It's possible that another instance recovered the lock and removed it already.", delegate: nil, cancelButtonTitle: "Okay")
        error.show()
    }
    
    // MARK: ActionSheetDelegate
    
    func actionSheet(_ actionSheet: UIActionSheet, didDismissWithButtonIndex buttonIndex: Int) {
        if actionSheet.tag == 1 { //database update failed
            if buttonIndex == 0 { // open read-only
                loadingDb.isReadOnly = true
                databaseUpdateComplete(loadingDb)
            }
        } else if actionSheet.tag == 2 { // database was already locked
            if buttonIndex == 0 { // recover lock
                databaseWasLocked(forEditing: loadingDb)
            } else if buttonIndex == 1 { // open read-only
                loadingDb.isReadOnly = true
                databaseWasLocked(forEditing: loadingDb)
            }
        } else if actionSheet.tag == 3 { // read only or writable mode database load
            if buttonIndex == 1 { // read-only
                loadingDb.isReadOnly = true
                completeLoad()
            } else if buttonIndex == 2 { // writable
                completeLoad()
            }
        } else if actionSheet.tag == 4 { // database was deleted
            if buttonIndex == 0 {
                databaseUpdateComplete(loadingDb)
            }
        } else if actionSheet.tag >= 100 {
            if buttonIndex == 0 {
                let index = actionSheet.tag - 100
                dbManager.deleteDatabaseAtIndex(index)
                tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
            }
        }
    }

    // MARK: EnterPasswordDelegate
    
    func userUnlockedDatabase(_ database: Database) {
        if !database.isReadOnly {
            loadingMessage = "Locking"
            networkRequestStarted()
            
            loadingDb = database
            loadingDb.lockForEditing()
        } else {
            databaseWasLocked(forEditing: database)
        }
    }

}

