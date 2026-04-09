#import "NLAppDelegate.h"
#import "NLAppLogViewController.h"

@implementation NLAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    
    NLAppLogViewController *logVC = [[NLAppLogViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:logVC];
    
    // Premium appearance
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithDefaultBackground];
        nav.navigationBar.standardAppearance = appearance;
        nav.navigationBar.scrollEdgeAppearance = appearance;
    }
    
    nav.navigationBar.prefersLargeTitles = YES;
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.30 green:0.45 blue:0.95 alpha:1.0];
    
    self.window.rootViewController = nav;
    self.window.tintColor = [UIColor colorWithRed:0.30 green:0.45 blue:0.95 alpha:1.0];
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
