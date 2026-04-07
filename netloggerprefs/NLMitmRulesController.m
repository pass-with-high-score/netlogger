#import "NLMitmRulesController.h"

#define PREFS_PLIST @"/var/jb/var/mobile/Library/Preferences/com.minh.netlogger.settings.plist"

// ---------------------------------------------------------------------------
#pragma mark - Add/Edit Rule Controller
// ---------------------------------------------------------------------------

@interface NLMitmEditController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) NSMutableDictionary *rule;
@property (nonatomic, assign) NSInteger ruleIndex;
@property (nonatomic, copy) void (^onSave)(NSDictionary *rule, NSInteger index);
@end

@implementation NLMitmEditController {
    UITableView *_tableView;
    UITextField *_urlField;
    UITextField *_keyField;
    UITextField *_valueField;
    UISwitch *_enabledSwitch;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.ruleIndex < 0 ? @"New Rule" : @"Edit Rule";
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveRule)];
    
    if (!self.rule) {
        self.rule = [@{
            @"url_pattern": @"",
            @"key_path": @"",
            @"new_value": @"true",
            @"enabled": @YES
        } mutableCopy];
    }
    
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    [self.view addSubview:_tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"Rule Configuration" : @"State";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        return @"URL Pattern: phần URL cần khớp (vd: /api/v1/user)\n"
               @"Key Path: đường dẫn JSON key (vd: data.user.is_vip)\n"
               @"New Value: giá trị mới (true/false/số/chuỗi)";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(16, 0, self.view.bounds.size.width - 64, 44)];
        field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        
        switch (indexPath.row) {
            case 0:
                field.placeholder = @"URL Pattern (e.g. /api/v1/user)";
                field.text = self.rule[@"url_pattern"];
                _urlField = field;
                break;
            case 1:
                field.placeholder = @"Key Path (e.g. data.user.is_vip)";
                field.text = self.rule[@"key_path"];
                _keyField = field;
                break;
            case 2:
                field.placeholder = @"New Value (e.g. true, 999)";
                field.text = self.rule[@"new_value"];
                _valueField = field;
                break;
        }
        
        [cell.contentView addSubview:field];
        return cell;
    } else {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"Enabled";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        _enabledSwitch = [[UISwitch alloc] init];
        _enabledSwitch.on = [self.rule[@"enabled"] boolValue];
        cell.accessoryView = _enabledSwitch;
        return cell;
    }
}

- (void)saveRule {
    NSString *urlPattern = _urlField.text ?: @"";
    NSString *keyPath = _keyField.text ?: @"";
    NSString *newValue = _valueField.text ?: @"";
    
    if (urlPattern.length == 0 || keyPath.length == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Error"
            message:@"URL Pattern và Key Path không được để trống!" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    
    NSDictionary *saved = @{
        @"url_pattern": urlPattern,
        @"key_path": keyPath,
        @"new_value": newValue,
        @"enabled": @(_enabledSwitch.on)
    };
    
    if (self.onSave) self.onSave(saved, self.ruleIndex);
    [self.navigationController popViewControllerAnimated:YES];
}

@end

// ---------------------------------------------------------------------------
#pragma mark - MitM Rules List Controller
// ---------------------------------------------------------------------------

@implementation NLMitmRulesController {
    UITableView *_tableView;
    NSMutableArray *_rules;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MitM Rules";
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addRule)];
    
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:_tableView];
    
    [self loadRules];
}

- (void)loadRules {
    CFPreferencesAppSynchronize(CFSTR("com.minh.netlogger"));
    CFPropertyListRef ref = CFPreferencesCopyAppValue(CFSTR("mitmRules"), CFSTR("com.minh.netlogger"));
    NSArray *saved = ref ? (__bridge_transfer NSArray *)ref : @[];
    _rules = [saved mutableCopy] ?: [NSMutableArray array];
}

- (void)saveRules {
    CFPreferencesSetAppValue(CFSTR("mitmRules"), (__bridge CFArrayRef)_rules, CFSTR("com.minh.netlogger"));
    CFPreferencesAppSynchronize(CFSTR("com.minh.netlogger"));
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PLIST] ?: [NSMutableDictionary dictionary];
    dict[@"mitmRules"] = _rules;
    [dict writeToFile:PREFS_PLIST atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0644)} ofItemAtPath:PREFS_PLIST error:nil];
    
    [_tableView reloadData];
}

- (void)addRule {
    NLMitmEditController *vc = [[NLMitmEditController alloc] init];
    vc.ruleIndex = -1;
    __weak typeof(self) weakSelf = self;
    vc.onSave = ^(NSDictionary *rule, NSInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf->_rules addObject:rule];
        [strongSelf saveRules];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return _rules.count == 0 ? 1 : _rules.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @"Response Modification Rules";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"Mỗi rule sẽ tự động sửa JSON Response khi URL khớp pattern.\n"
           @"Hỗ trợ nested key path (data.user.is_vip).";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_rules.count == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = @"No rules yet. Tap + to add.";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        if (@available(iOS 13.0, *)) cell.textLabel.textColor = [UIColor tertiaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    
    NSDictionary *rule = _rules[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    
    NSString *pattern = rule[@"url_pattern"] ?: @"(empty)";
    NSString *keyPath = rule[@"key_path"] ?: @"?";
    NSString *value = rule[@"new_value"] ?: @"?";
    BOOL enabled = [rule[@"enabled"] boolValue];
    
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", enabled ? @"🟢" : @"⚪️", pattern];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ → %@", keyPath, value];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    if (@available(iOS 13.0, *)) cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    if (_rules.count == 0) return;
    
    NLMitmEditController *vc = [[NLMitmEditController alloc] init];
    vc.rule = [_rules[indexPath.row] mutableCopy];
    vc.ruleIndex = indexPath.row;
    __weak typeof(self) weakSelf = self;
    vc.onSave = ^(NSDictionary *rule, NSInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf->_rules replaceObjectAtIndex:index withObject:rule];
        [strongSelf saveRules];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return _rules.count > 0;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style == UITableViewCellEditingStyleDelete) {
        [_rules removeObjectAtIndex:indexPath.row];
        [self saveRules];
    }
}

@end
