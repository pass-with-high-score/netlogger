#import "NLBlacklistController.h"
#import "NLLocalization.h"

#define PREFS_PLIST @"/var/jb/var/mobile/Library/Preferences/com.minh.netlogger.settings.plist"

@interface NLBlacklistController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSString *> *domains;
@end

@implementation NLBlacklistController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NLLocalizedString(@"Blacklisted Domains", @"Blacklisted Domains");
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addDomainPrompt)];
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DomainCell"];
    [self.view addSubview:self.tableView];
    
    [self loadDomains];
}

- (void)loadDomains {
    CFPreferencesAppSynchronize(CFSTR("com.minh.netlogger"));
    CFPropertyListRef ref = CFPreferencesCopyAppValue(CFSTR("blacklistedDomains"), CFSTR("com.minh.netlogger"));
    NSString *saved = ref ? (__bridge_transfer NSString *)ref : @"";
    
    if (saved.length > 0) {
        NSArray *parts = [saved componentsSeparatedByString:@","];
        self.domains = [NSMutableArray array];
        for (NSString *p in parts) {
            NSString *trimmed = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length > 0) {
                [self.domains addObject:trimmed];
            }
        }
    } else {
        self.domains = [NSMutableArray array];
    }
    [self.tableView reloadData];
}

- (void)saveDomains {
    NSString *joined = [self.domains componentsJoinedByString:@", "];
    
    CFPreferencesSetAppValue(CFSTR("blacklistedDomains"), (__bridge CFStringRef)joined, CFSTR("com.minh.netlogger"));
    CFPreferencesAppSynchronize(CFSTR("com.minh.netlogger"));
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PLIST] ?: [NSMutableDictionary dictionary];
    dict[@"blacklistedDomains"] = joined;
    [dict writeToFile:PREFS_PLIST atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0644)} ofItemAtPath:PREFS_PLIST error:nil];
    
    [self.tableView reloadData];
}

- (void)addDomainPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NLLocalizedString(@"Add Domain", @"Add Domain")
                                                                   message:NLLocalizedString(@"Enter domain to block (e.g. google-analytics.com)", @"Enter domain to block")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"example.com";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    
    UIAlertAction *add = [UIAlertAction actionWithTitle:NLLocalizedString(@"Add", @"Add") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *field = alert.textFields.firstObject;
        NSString *text = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (text.length > 0 && ![self.domains containsObject:text]) {
            [self.domains addObject:text];
            [self saveDomains];
        }
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NLLocalizedString(@"Cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:cancel];
    [alert addAction:add];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableView DataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.domains.count == 0) {
        UIView *emptyView = [[UIView alloc] initWithFrame:tableView.bounds];
        
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.slash"]];
        icon.tintColor = [UIColor systemGray3Color];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyView addSubview:icon];
        
        UILabel *titleLbl = [[UILabel alloc] init];
        titleLbl.text = NLLocalizedString(@"No Blacklisted Domains", @"No Blacklisted Domains");
        titleLbl.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        titleLbl.textColor = [UIColor secondaryLabelColor];
        titleLbl.textAlignment = NSTextAlignmentCenter;
        titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyView addSubview:titleLbl];
        
        [NSLayoutConstraint activateConstraints:@[
            [icon.centerXAnchor constraintEqualToAnchor:emptyView.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:emptyView.centerYAnchor constant:-50],
            [icon.widthAnchor constraintEqualToConstant:50],
            [icon.heightAnchor constraintEqualToConstant:50],
            [titleLbl.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:16],
            [titleLbl.centerXAnchor constraintEqualToAnchor:emptyView.centerXAnchor]
        ]];
        
        tableView.backgroundView = emptyView;
        return 0;
    }
    
    tableView.backgroundView = nil;
    return self.domains.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.domains.count > 0 ? [NSString stringWithFormat:@"%lu Domains", (unsigned long)self.domains.count] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DomainCell" forIndexPath:indexPath];
    cell.textLabel.text = self.domains[indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    UIImageView *lockIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    lockIcon.tintColor = [UIColor systemRedColor];
    cell.accessoryView = lockIcon;
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.domains removeObjectAtIndex:indexPath.row];
        [self saveDomains];
    }
}

@end
