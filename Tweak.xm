#include <notify.h>
#import "LSStatusBarItem.h"
#import "MBWiFiProxyInfo.h"

static BOOL enabled = NO;
static BOOL alwaysShow = YES;
static NSUInteger type = 0;
static MBWiFiProxyInfo *proxyInfo;
static LSStatusBarItem *statusBarItem;

@interface SBWiFiManager : NSObject
+ (instancetype)sharedInstance;
- (void)_powerStateDidChange;
- (NSString *)currentNetworkName;
- (BOOL)wiFiEnabled;
@end

@interface RadiosPreferences : NSObject
@property (nonatomic) BOOL airplaneMode;
@end

static BOOL canShowStatusBarIcon() {
    return alwaysShow ? YES : [[%c(SBWiFiManager) sharedInstance] wiFiEnabled] && [[%c(SBWiFiManager) sharedInstance] currentNetworkName];
}

static void updateStatusBarImage() {
    statusBarItem.imageName = type > 0 ? @"ProxySwitcher" : @"ProxySwitcherUnselected";
}

static void setStatusBarVisible(BOOL visible) {
    statusBarItem.visible = enabled && canShowStatusBarIcon() ? visible : NO; 
}

static void networkChanged() {
    if (!enabled) { return; }
    setStatusBarVisible(![[[%c(RadiosPreferences) alloc] init] airplaneMode]);
    if ([[%c(SBWiFiManager) sharedInstance] wiFiEnabled] && [[%c(SBWiFiManager) sharedInstance] currentNetworkName]) {
        if (type == 1) {
            notify_post("com.mbo42.proxyswitcherd.enable"); 
        } else {
            notify_post("com.mbo42.proxyswitcherd.disable");
        }
    }
}

static void loadPreferences() {
    CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("com.mbo42.proxyswitcher"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *preferences;
    if (keyList) {
        preferences = (__bridge NSDictionary *)CFPreferencesCopyMultiple(keyList, 
                                                                   CFSTR("com.mbo42.proxyswitcher"), 
                                                                   kCFPreferencesCurrentUser, 
                                                                   kCFPreferencesAnyHost);
        if (!preferences) { 
            preferences = [NSDictionary dictionary]; 
        }
        CFRelease(keyList);
    }
    enabled = [preferences objectForKey:@"enabled"] ? [[preferences objectForKey:@"enabled"] boolValue] : YES;
    alwaysShow = [preferences objectForKey:@"alwaysShow"] ? [[preferences objectForKey:@"alwaysShow"] boolValue] : YES;
    proxyInfo = [MBWiFiProxyInfo infoFromDictionary:preferences];
    type = [preferences objectForKey:@"type"] ? [[preferences objectForKey:@"type"] integerValue] : 0;
    notify_post("com.mbo42.proxyswitcherd.refreshPreferences");
    setStatusBarVisible(![[[%c(RadiosPreferences) alloc] init] airplaneMode]);
    updateStatusBarImage();
    networkChanged();
}

static void saveNewType() {
    CFPreferencesSetAppValue(CFSTR("type"),
                            CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt16Type, &type),
                            CFSTR("com.mbo42.proxyswitcher"));
    networkChanged();
    updateStatusBarImage();
}

static void toggleProxy() {
    type = !type ? 1 : 0;
    saveNewType();
}


%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;
    statusBarItem = [[%c(LSStatusBarItem) alloc] initWithIdentifier:@"com.mbo42.proxyswitcher" alignment:StatusBarAlignmentRight];
    statusBarItem.imageName = @"ProxySwitcher";
    loadPreferences();
}

%end


%hook RadiosPreferences

- (void)setAirplaneMode:(BOOL)airplaneMode {
    %orig;
    setStatusBarVisible(!airplaneMode);
}

%end


%hook _UIAlertControllerView

- (void)setAlertController:(id)controller {
    %orig;
    if ([controller isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alertVC = (UIAlertController *)controller;
        NSString *message = alertVC.message;
        if (!proxyInfo.server.length || !proxyInfo.port || !proxyInfo.username.length || !proxyInfo.password.length) { 
            return; 
        }
        if (message && 
            [message rangeOfString:proxyInfo.server].location != NSNotFound && 
            [message rangeOfString:[proxyInfo.port stringValue]].location != NSNotFound) {
            if (alertVC.textFields.count > 1) {
                UITextField *usernameField = alertVC.textFields[0];
                UITextField *passwordField = alertVC.textFields[1];
                usernameField.text = proxyInfo.username;
                passwordField.text = proxyInfo.password;
            }
        }
    }
}

%end


%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    (CFNotificationCallback)networkChanged,
                                    CFSTR("com.apple.system.config.network_change"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    (CFNotificationCallback)loadPreferences, 
                                    CFSTR("com.mbo42.proxyswitcher/settingschanged"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorCoalesce);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                    NULL, 
                                    (CFNotificationCallback)toggleProxy, 
                                    CFSTR("com.mbo42.proxyswitcheruikit/didTapOnStatusBar"), 
                                    NULL, 
                                    CFNotificationSuspensionBehaviorCoalesce);
}
