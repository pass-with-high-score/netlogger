#import "NLAppLogViewController.h"
#import "NLLogEntry.h"
#import "NLLogCell.h"
#import "NLAppLogDetailViewController.h"

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(id)arg1;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@end

@interface NLAppLogViewController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NLLogEntry *> *allLogs;
@property (nonatomic, strong) NSMutableArray<NLLogEntry *> *filteredLogs;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSTimer *autoRefreshTimer;
@property (nonatomic, assign) BOOL isAutoRefreshEnabled;
@property (nonatomic, strong) UIBarButtonItem *autoRefreshBtn;
@end

@implementation NLAppLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"NetLogger";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;

    self.allLogs = [NSMutableArray array];
    self.filteredLogs = [NSMutableArray array];

    // ── Table View ──
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.estimatedRowHeight = 72;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    [self.tableView registerClass:[NLLogCell class] forCellReuseIdentifier:@"NLLogCell"];
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    [self.view addSubview:self.tableView];

    // ── Search Controller ──
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Filter by URL, method, app...";
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.scopeButtonTitles = @[@"All", @"2xx", @"3xx", @"4xx+", @"Err"];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;

    // ── Nav Bar Buttons ──
    self.autoRefreshBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"timer"]
        style:UIBarButtonItemStylePlain target:self action:@selector(toggleAutoRefresh)];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
        style:UIBarButtonItemStylePlain target:self action:@selector(reloadLogs)];

    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"trash"]
        style:UIBarButtonItemStylePlain target:self action:@selector(clearLog)];
    clearBtn.tintColor = [UIColor systemRedColor];

    UIBarButtonItem *settingsBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"gearshape"]
        style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];

    self.navigationItem.rightBarButtonItems = @[clearBtn, self.autoRefreshBtn, refreshBtn];
    self.navigationItem.leftBarButtonItem = settingsBtn;

    // ── Pull-to-Refresh ──
    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(pullRefresh:) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = rc;

    [self reloadLogs];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.autoRefreshTimer) {
        [self.autoRefreshTimer invalidate];
        self.autoRefreshTimer = nil;
    }
    self.isAutoRefreshEnabled = NO;
    self.autoRefreshBtn.tintColor = nil;
}

- (void)toggleAutoRefresh {
    self.isAutoRefreshEnabled = !self.isAutoRefreshEnabled;
    if (self.isAutoRefreshEnabled) {
        self.autoRefreshBtn.tintColor = [UIColor systemGreenColor];
        self.autoRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(reloadLogs) userInfo:nil repeats:YES];
    } else {
        self.autoRefreshBtn.tintColor = nil;
        [self.autoRefreshTimer invalidate];
        self.autoRefreshTimer = nil;
    }
}

- (void)pullRefresh:(UIRefreshControl *)rc {
    [self reloadLogs];
    [rc endRefreshing];
}

- (void)openSettings {
    NSURL *url = [NSURL URLWithString:@"prefs:root=NetLogger"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        // Fallback: open Settings app
        NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        [[UIApplication sharedApplication] openURL:settingsURL options:@{} completionHandler:nil];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Data Loading
// ---------------------------------------------------------------------------

- (void)reloadLogs {
    [self.allLogs removeAllObjects];

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.minh.netlogger.settings.plist"];
    NSArray *selectedApps = prefs[@"selectedApps"];

    for (NSString *bundleID in selectedApps) {
        if (!bundleID || bundleID.length == 0) continue;

        NSString *logPath = nil;

        if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
            // Settings.app container
            NSString *settingsHome = @"/var/mobile/Library";
            logPath = [settingsHome stringByAppendingPathComponent:@"Caches/com.minh.netlogger.logs.txt"];
        } else {
            LSApplicationProxy *proxy = [NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:bundleID];
            if (!proxy || !proxy.dataContainerURL) continue;
            NSString *cachesPath = [[proxy.dataContainerURL path] stringByAppendingPathComponent:@"Library/Caches"];
            logPath = [cachesPath stringByAppendingPathComponent:@"com.minh.netlogger.logs.txt"];
        }

        NSString *content = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
        if (!content || content.length == 0) continue;

        NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            if (line.length == 0) continue;
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            if (!data) continue;
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([dict isKindOfClass:[NSDictionary class]]) {
                NLLogEntry *entry = [[NLLogEntry alloc] initWithDictionary:dict];
                [self.allLogs addObject:entry];
            }
        }
    }

    [self.allLogs sortUsingComparator:^NSComparisonResult(NLLogEntry *a, NLLogEntry *b) {
        if (a.timestamp < b.timestamp) return NSOrderedAscending;
        if (a.timestamp > b.timestamp) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    [self applyFilter];
}

- (void)applyFilter {
    NSString *query = self.searchController.searchBar.text;
    NSInteger scope = self.searchController.searchBar.selectedScopeButtonIndex;
    NSMutableArray *results = [NSMutableArray array];
    NSString *lower = [query lowercaseString];

    for (NLLogEntry *e in self.allLogs) {
        BOOL scopeMatch = YES;
        if (scope == 1)      scopeMatch = (e.status >= 200 && e.status < 300);
        else if (scope == 2) scopeMatch = (e.status >= 300 && e.status < 400);
        else if (scope == 3) scopeMatch = (e.status >= 400);
        else if (scope == 4) scopeMatch = (e.status == 0);
        if (!scopeMatch) continue;

        BOOL textMatch = YES;
        if (query.length > 0) {
            textMatch = ([e.url.lowercaseString containsString:lower] ||
                         [e.method.lowercaseString containsString:lower] ||
                         [e.app.lowercaseString containsString:lower]);
        }
        if (textMatch) [results addObject:e];
    }

    self.filteredLogs = results;
    [self.tableView reloadData];
    self.title = [NSString stringWithFormat:@"NetLogger (%lu)", (unsigned long)self.filteredLogs.count];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    [self applyFilter];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilter];
}

// ---------------------------------------------------------------------------
#pragma mark - Clear Logs
// ---------------------------------------------------------------------------

- (void)clearLog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Logs" message:@"Delete all captured network logs?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.minh.netlogger.settings.plist"];
        NSArray *selectedApps = prefs[@"selectedApps"];
        for (NSString *bundleID in selectedApps) {
            NSString *logPath = nil;
            if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
                logPath = @"/var/mobile/Library/Caches/com.minh.netlogger.logs.txt";
            } else {
                LSApplicationProxy *proxy = [NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:bundleID];
                if (!proxy || !proxy.dataContainerURL) continue;
                logPath = [[[proxy.dataContainerURL path] stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:@"com.minh.netlogger.logs.txt"];
            }
            [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [self reloadLogs];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - Table View
// ---------------------------------------------------------------------------

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.filteredLogs.count == 0) {
        UIView *emptyView = [[UIView alloc] initWithFrame:tableView.bounds];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"]];
        icon.tintColor = [UIColor systemGray3Color];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyView addSubview:icon];

        UILabel *titleLbl = [[UILabel alloc] init];
        titleLbl.text = @"No Network Logs";
        titleLbl.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        titleLbl.textColor = [UIColor secondaryLabelColor];
        titleLbl.textAlignment = NSTextAlignmentCenter;
        titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyView addSubview:titleLbl];

        UILabel *subtitleLbl = [[UILabel alloc] init];
        subtitleLbl.text = @"Enable NetLogger and select apps\nto start capturing traffic.";
        subtitleLbl.font = [UIFont systemFontOfSize:14];
        subtitleLbl.numberOfLines = 0;
        subtitleLbl.textColor = [UIColor tertiaryLabelColor];
        subtitleLbl.textAlignment = NSTextAlignmentCenter;
        subtitleLbl.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyView addSubview:subtitleLbl];

        [NSLayoutConstraint activateConstraints:@[
            [icon.centerXAnchor constraintEqualToAnchor:emptyView.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:emptyView.centerYAnchor constant:-60],
            [icon.widthAnchor constraintEqualToConstant:50],
            [icon.heightAnchor constraintEqualToConstant:50],
            [titleLbl.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:16],
            [titleLbl.centerXAnchor constraintEqualToAnchor:emptyView.centerXAnchor],
            [subtitleLbl.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:8],
            [subtitleLbl.centerXAnchor constraintEqualToAnchor:emptyView.centerXAnchor],
            [subtitleLbl.widthAnchor constraintLessThanOrEqualToConstant:280],
        ]];
        tableView.backgroundView = emptyView;
    } else {
        tableView.backgroundView = nil;
    }
    return self.filteredLogs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NLLogCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NLLogCell" forIndexPath:indexPath];
    NLLogEntry *entry = self.filteredLogs[indexPath.row];
    [cell configureWithEntry:entry];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NLLogEntry *entry = self.filteredLogs[indexPath.row];
    NLAppLogDetailViewController *vc = [[NLAppLogDetailViewController alloc] init];
    vc.logEntry = entry;
    [self.navigationController pushViewController:vc animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NLLogEntry *entry = self.filteredLogs[indexPath.row];
        [self.allLogs removeObject:entry];
        [self.filteredLogs removeObject:entry];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        self.title = [NSString stringWithFormat:@"NetLogger (%lu)", (unsigned long)self.filteredLogs.count];
    }
}

@end
