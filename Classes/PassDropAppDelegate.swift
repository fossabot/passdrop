import UIKit

class PassDropAppDelegate2: NSObject, UIApplicationDelegate, UIAlertViewDelegate {
    override init() {
        super.init()
    }
    
    @IBOutlet var window: UIWindow?
    @IBOutlet var navigationController: UINavigationController?
    @IBOutlet var splitController: MGSplitViewController?

    /*
    let dbSession: DBSession
    let prefs: AppPrefs
    let dbManager: DatabaseManager
    */

    //let hide: HideViewController
    @IBOutlet var rootView: RootViewController?
    
    //let settingsView: SettingsViewController
}
