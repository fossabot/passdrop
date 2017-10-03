//
//  PassDropAppDelegate.swift
//  PassDrop
//
//  Created by Rudis Muiznieks on 1/30/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

import UIKit

class PassDropAppDelegate: NSObject, UIApplicationDelegate, UIAlertViewDelegate {
    var window: UIWindow?
    var navigationController: UINavigationController!
    var splitController: MGSplitViewController!

    var dbSession: DBSession!
    var prefs: AppPrefs!
    var dbManager: DatabaseManager!

    var bgTimer: Date?
    var isLocked = false

    var hide: HideViewController!
    var rootView: RootViewController!

    var settingsView: SettingsViewController!
    
    // MARK: Application lifecycle
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Override point for customization after application launch.
        prefs = AppPrefs()
        prefs.load()
        
        let appKey = Globals.DROPBOX_KEY
        let appSecret = Globals.DROPBOX_SECRET
        
        DBSession.setShared(DBSession(appKey: appKey, appSecret: appSecret, root: kDBRootDropbox))

        dbManager = DatabaseManager()
        
        // Add the navigation controller's view to the window and display.
        if UIDevice.current.userInterfaceIdiom == .pad {
            splitController.showsMasterInLandscape = true
            splitController.showsMasterInPortrait = true
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
        let isHidden = navigationController.topViewController == hide || splitController.presentedViewController == hide
        if !isHidden && dbManager.activeDatabase != nil && prefs.lockInBackgroundSeconds >= 0 {
            bgTimer = Date()
            if UIDevice.current.userInterfaceIdiom == .pad {
                let details = (splitController.detailViewController as! UINavigationController).viewControllers
                if details.count > 1 {
                    if details[1].responds(to: Selector("hideKeyboard")) {
                        details[1].performSelector(onMainThread: Selector("hideKeyboard"), with: nil, waitUntilDone: true)
                    }
                }
                splitController.present(hide, animated: false, completion: nil)
            } else {
                navigationController.dismiss(animated: false, completion: nil)
                navigationController.pushViewController(hide, animated: false)
                navigationController.setNavigationBarHidden(true, animated: false)
            }
        }
    }
    
/*
                    - (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
                        if(alertView.tag == 1){
                            if(buttonIndex == 0){
                                [self userClosedPasswordModal:[dbManager activeDatabase]];
                            } else {
                                if([alertView textFieldAtIndex:0].text.length > 0){
                                    if([dbManager.activeDatabase loadWithPassword:[alertView textFieldAtIndex:0].text]){
                                        [self userUnlockedDatabase:[dbManager activeDatabase]];
                                    } else {
                                        UIAlertView* dialog = [[UIAlertView alloc] initWithTitle:@"Enter Password" message:@"Please try again." delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Unlock", nil];
                                        dialog.tag = 1;
                                        dialog.alertViewStyle = UIAlertViewStyleSecureTextInput;
                                        [dialog show];
                                        [dialog release];
                                    }
                                } else {
                                    UIAlertView* dialog = [[UIAlertView alloc] initWithTitle:@"Enter Password" message:@"You must enter the password." delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Unlock", nil];
                                    dialog.tag = 1;
                                    dialog.alertViewStyle = UIAlertViewStyleSecureTextInput;
                                    [dialog show];
                                    [dialog release];
                                }
                            }
                        }
                        }
                        
                        - (void)userUnlockedDatabase:(id<Database>)database {
                            if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad){
                                [splitController dismissViewControllerAnimated:NO completion:nil];
                            } else {
                                if([navigationController topViewController] == hide){
                                    [navigationController popViewControllerAnimated:NO];
                                    [navigationController setNavigationBarHidden:NO];
                                }
                            }
                            }
                            
                            - (void)userClosedPasswordModal:(id<Database>)database {
                                if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad){
                                    [(UINavigationController*)splitController.detailViewController popToRootViewControllerAnimated:NO];
                                    [rootView.navigationController popToRootViewControllerAnimated:NO];
                                    [rootView.navigationController.view setAlpha:1.0f];
                                    [splitController dismissViewControllerAnimated:NO completion:nil];
                                    dbManager.activeDatabase = nil;
                                    [rootView removeLock:database];
                                } else {
                                    if([navigationController topViewController] == hide){
                                        [navigationController popViewControllerAnimated:NO];
                                        [navigationController setNavigationBarHidden:NO];
                                    }
                                    [navigationController popToRootViewControllerAnimated:NO];
                                    dbManager.activeDatabase = nil;
                                    [rootView removeLock:database];
                                }
                                }
                                
                                - (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
                                    [settingsView updateSettingsUI];
                                    if ([[DBSession sharedSession] handleOpenURL:url]) {
                                        if ([[DBSession sharedSession] isLinked]) {
                                            NSLog(@"App linked successfully!");
                                            // At this point you can start making API calls
                                        }
                                        return YES;
                                    }
                                    // Add whatever other url handling code your app requires here
                                    return NO;
                                    }
                                    
                                    - (void)applicationDidBecomeActive:(UIApplication *)application {
                                        /*
                                         Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
                                         */
                                        
                                        if(bgTimer != nil){
                                            NSTimeInterval diff = fabs([bgTimer timeIntervalSinceNow]);
                                            //[navigationController dismissModalViewControllerAnimated:NO];
                                            if(diff > prefs.lockInBackgroundSeconds){
                                                UIAlertView* dialog = [[UIAlertView alloc] initWithTitle:@"Enter Password" message:nil delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Unlock", nil];
                                                dialog.tag = 1;
                                                dialog.alertViewStyle = UIAlertViewStyleSecureTextInput;
                                                [dialog show];
                                                [dialog release];
                                            } else {
                                                if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad){
                                                    [splitController dismissViewControllerAnimated:NO completion:nil];
                                                } else {
                                                    if([navigationController topViewController] == hide){
                                                        [navigationController popViewControllerAnimated:NO];
                                                        [navigationController setNavigationBarHidden:NO];
                                                    }
                                                }
                                            }
                                            [bgTimer release];
                                            bgTimer = nil;
                                        }
                                        
                                        if(prefs.autoClearClipboard == YES){
                                            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                                            pasteboard.string = @"";
                                        }
                                        
                                        [settingsView updateSettingsUI];
                                        }
                                        
                                        
*/
}
