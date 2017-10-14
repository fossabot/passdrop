//
//  PassDropAppDelegate.swift
//  PassDrop
//
//  Created by Rudis Muiznieks on 1/30/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

import UIKit
import SwiftyDropbox

@UIApplicationMain
@objc(PassDropAppDelegate)
class PassDropAppDelegate: NSObject, UIApplicationDelegate, UIAlertViewDelegate {
    var window: UIWindow?
    var navigationController: UINavigationController!
    var splitController: MGSplitViewController?

    var prefs: AppPrefs!
    var dbManager: DatabaseManager!

    var bgTimer: Date?
    var isLocked = false

    var hide: HideViewController!
    var rootView: RootViewController!

    var settingsView: SettingsViewController?
    
    // MARK: Application lifecycle
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Override point for customization after application launch.
        prefs = AppPrefs()
        prefs.load()
        
        DropboxClientsManager.setupWithAppKey(Globals.DROPBOX_KEY)
        
        dbManager = DatabaseManager()
        // If there is no linked DropboxClient, then clear the database.
        if DropboxClientsManager.authorizedClient == nil {
            dbManager.dropboxWasReset()
        }
        
        // Add the navigation controller's view to the window and display.
        if UIDevice.current.userInterfaceIdiom == .pad {
            splitController?.showsMasterInLandscape = true
            splitController?.showsMasterInPortrait = true
            window?.rootViewController = splitController
        } else {
            window?.rootViewController = navigationController
        }
        window?.makeKeyAndVisible()
        
        isLocked = true
        bgTimer = nil
        hide = HideViewController(nibName: "HideScreenView", bundle: nil)
        
        return true
    }
    
    func dropboxWasReset() {
        dbManager.dropboxWasReset()
        rootView.dropboxWasReset()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        /*
         Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
         Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
         */
        let isHidden = navigationController.topViewController == hide || splitController?.presentedViewController == hide
        if !isHidden && dbManager.activeDatabase != nil && prefs.lockInBackgroundSeconds >= 0 {
            bgTimer = Date()
            if UIDevice.current.userInterfaceIdiom == .pad {
                let details = (splitController?.detailViewController as! UINavigationController).viewControllers
                if details.count > 1 {
                    if details[1].responds(to: Selector("hideKeyboard")) {
                        details[1].performSelector(onMainThread: Selector("hideKeyboard"), with: nil, waitUntilDone: true)
                    }
                }
                splitController?.present(hide, animated: false, completion: nil)
            } else {
                navigationController.dismiss(animated: false, completion: nil)
                navigationController.pushViewController(hide, animated: false)
                navigationController.setNavigationBarHidden(true, animated: false)
            }
        }
    }
    
    func alertView(_ alertView: UIAlertView, didDismissWithButtonIndex buttonIndex: Int) {
        if alertView.tag == 1 {
            if buttonIndex == 0 {
                userClosedPasswordModal(dbManager.activeDatabase!)
            } else {
                if !alertView.textField(at: 0)!.text!.isEmpty {
                    if dbManager.activeDatabase!.load(withPassword: alertView.textField(at: 0)!.text!) {
                        userUnlockedDatabase(dbManager.activeDatabase!)
                    } else {
                        let dialog = UIAlertView(title: "Enter Password", message: "Please try again.", delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "Unlock")
                        dialog.tag = 1
                        dialog.alertViewStyle = .secureTextInput
                        dialog.show()
                    }
                } else {
                    let dialog = UIAlertView(title: "Enter Password", message: "You must enter the password.", delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "Unlock")
                    dialog.tag = 1
                    dialog.alertViewStyle = .secureTextInput
                    dialog.show()
                }
            }
        }
    }

    func userUnlockedDatabase(_ database: Database) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            splitController?.dismiss(animated: false, completion: nil)
        } else {
            if navigationController.topViewController == hide {
                navigationController.popViewController(animated: false)
                navigationController.setNavigationBarHidden(false, animated: false)
            }
        }
    }
    
    func userClosedPasswordModal(_ database: Database) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            (splitController?.detailViewController as! UINavigationController).popToRootViewController(animated: false)
            rootView.navigationController?.popToRootViewController(animated: false)
            rootView.navigationController?.view.alpha = 1.0
            splitController?.dismiss(animated: false, completion: nil)
            dbManager.activeDatabase = nil
            rootView.removeLock(database)
        } else {
            if navigationController.topViewController == hide {
                navigationController.popViewController(animated: false)
                navigationController.setNavigationBarHidden(false, animated: false)
            }
            navigationController.popToRootViewController(animated: false)
            dbManager.activeDatabase = nil
            rootView.removeLock(database)
        }
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        if let authResult = DropboxClientsManager.handleRedirectURL(url) {
            settingsView?.updateSettingsUI()
            switch authResult {
            case .success:
                NSLog("App linked successfully!")
            case .cancel:
                NSLog("Dropbox authentication flow cancelled")
            case .error(_, let description):
                NSLog("Failed to authenticate with Dropbox", description)
            }
            return true
        }
        return false
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        /*
         Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
         */
        if bgTimer != nil {
            let diff = fabs(bgTimer!.timeIntervalSinceNow)
            //[navigationController dismissModalViewControllerAnimated:NO];
            if diff > Double(prefs.lockInBackgroundSeconds) {
                let dialog = UIAlertView(title: "Enter Password", message: "", delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "Unlock")
                dialog.tag = 1
                dialog.alertViewStyle = .secureTextInput
                dialog.show()
            } else {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    splitController?.dismiss(animated: false, completion: nil)
                } else {
                    if navigationController.topViewController == hide {
                        navigationController.popViewController(animated: false)
                        navigationController.setNavigationBarHidden(false, animated: false)
                    }
                }
            }
            bgTimer = nil
        }
        
        if prefs.autoClearClipboard {
            UIPasteboard.general.string = ""
        }

        settingsView?.updateSettingsUI()
    }
}
