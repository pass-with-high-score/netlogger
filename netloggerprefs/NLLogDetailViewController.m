#import "NLLogDetailViewController.h"

// ---------------------------------------------------------------------------
#pragma mark - NLLogEntry
// ---------------------------------------------------------------------------

@implementation NLLogEntry

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    if (self = [super init]) {
        _guid = dict[@"id"];
        _timestamp = [dict[@"timestamp"] doubleValue];
        _method = dict[@"method"];
        _url = dict[@"url"];
        _status = [dict[@"status"] integerValue];
        _app = dict[@"app"];
        _reqHeaders = dict[@"req_headers"];
        _reqBodyBase64 = dict[@"req_body_base64"];
        _resHeaders = dict[@"res_headers"];
        _resBodyBase64 = dict[@"res_body_base64"];
    }
    return self;
}

- (NSString *)hostFromURL {
    NSURL *u = [NSURL URLWithString:self.url];
    return u.host ?: @"—";
}

- (NSString *)pathFromURL {
    NSURL *u = [NSURL URLWithString:self.url];
    NSString *p = u.path;
    if (u.query) p = [p stringByAppendingFormat:@"?%@", u.query];
    return (p && p.length > 0) ? p : @"/";
}

- (NSString *)statusText {
    if (self.status == 0) return @"—";
    return [NSString stringWithFormat:@"%ld", (long)self.status];
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Detail View Controller
// ---------------------------------------------------------------------------

@interface NLLogDetailViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *currentSections; // Array of section dicts
@end

@implementation NLLogDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    
    // --- Segmented Control ---
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Overview", @"Request", @"Response"]];
    self.segmentedControl.selectedSegmentIndex = 0;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentedControl;
    
    // --- Copy button ---
    UIBarButtonItem *copyBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"doc.on.doc"]
        style:UIBarButtonItemStylePlain
        target:self action:@selector(copyContent)];
    self.navigationItem.rightBarButtonItem = copyBtn;
    
    // --- Table View (grouped style) ---
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.estimatedRowHeight = 44;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:self.tableView];
    
    [self rebuildData];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self rebuildData];
}

- (void)copyContent {
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *section in self.currentSections) {
        [text appendFormat:@"── %@ ──\n", section[@"title"]];
        for (NSDictionary *row in section[@"rows"]) {
            if (row[@"label"]) {
                [text appendFormat:@"%@: %@\n", row[@"label"], row[@"value"]];
            } else {
                [text appendFormat:@"%@\n", row[@"value"]];
            }
        }
        [text appendString:@"\n"];
    }
    [UIPasteboard generalPasteboard].string = text;
    
    // Brief toast
    UILabel *toast = [[UILabel alloc] init];
    toast.text = @" Copied! ";
    toast.font = [UIFont boldSystemFontOfSize:14];
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 16;
    toast.clipsToBounds = YES;
    [toast sizeToFit];
    CGRect f = toast.frame;
    f.size.width += 32;
    f.size.height += 16;
    toast.frame = f;
    toast.center = CGPointMake(self.view.center.x, self.view.frame.size.height - 100);
    [self.view addSubview:toast];
    [UIView animateWithDuration:0.3 delay:1.0 options:0 animations:^{ toast.alpha = 0; } completion:^(BOOL f) { [toast removeFromSuperview]; }];
}

// ---------------------------------------------------------------------------
#pragma mark - Build Data
// ---------------------------------------------------------------------------

- (NSArray *)headerRowsFromDict:(NSDictionary *)headers {
    if (!headers || headers.count == 0) return nil;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *key in [headers.allKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        [rows addObject:@{@"label": key, @"value": [NSString stringWithFormat:@"%@", headers[key]], @"wrap": @YES}];
    }
    return rows;
}

- (NSString *)decodeBase64:(NSString *)base64 {
    if (!base64 || base64.length == 0) return nil;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!data) return @"(Invalid Base64)";
    
    NSString *result = nil;
    
    // Try JSON pretty print
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (json) {
        NSData *pretty = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
        if (pretty) result = [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding];
    }
    
    if (!result) {
        result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    if (!result) return [NSString stringWithFormat:@"(Binary data, %lu bytes)", (unsigned long)data.length];
    
    // Truncate to prevent UI lag on massive bodies
    static const NSUInteger kMaxDisplayLength = 8000;
    if (result.length > kMaxDisplayLength) {
        result = [NSString stringWithFormat:@"%@\n\n── Truncated ──\nShowing %lu of %lu bytes.\nUse Copy button to get full content.",
            [result substringToIndex:kMaxDisplayLength],
            (unsigned long)kMaxDisplayLength,
            (unsigned long)result.length];
    }
    
    return result;
}

- (void)rebuildData {
    NSMutableArray *sections = [NSMutableArray array];
    NLLogEntry *e = self.logEntry;
    if (!e) { self.currentSections = @[]; [self.tableView reloadData]; return; }
    
    NSInteger idx = self.segmentedControl.selectedSegmentIndex;
    
    if (idx == 0) {
        // ── Overview ──
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSDate *d = [NSDate dateWithTimeIntervalSince1970:e.timestamp];
        
        [sections addObject:@{
            @"title": @"General",
            @"rows": @[
                @{@"label": @"URL",    @"value": e.url ?: @"—", @"wrap": @YES},
                @{@"label": @"Host",   @"value": [e hostFromURL], @"wrap": @YES},
                @{@"label": @"Path",   @"value": [e pathFromURL], @"wrap": @YES},
                @{@"label": @"Method", @"value": e.method ?: @"—"},
                @{@"label": @"Status", @"value": [e statusText], @"statusColor": @YES},
            ]
        }];
        
        [sections addObject:@{
            @"title": @"Metadata",
            @"rows": @[
                @{@"label": @"App",  @"value": e.app ?: @"—"},
                @{@"label": @"Time", @"value": [df stringFromDate:d]},
                @{@"label": @"ID",   @"value": e.guid ?: @"—", @"wrap": @YES},
            ]
        }];
        
        if ([e.method isEqualToString:@"DIAGNOSTIC"]) {
            [sections addObject:@{
                @"title": @"Note",
                @"rows": @[@{@"value": @"This is a diagnostic event generated on app start."}]
            }];
        }
        
    } else if (idx == 1) {
        // ── Request ──
        NSArray *headerRows = [self headerRowsFromDict:e.reqHeaders];
        if (headerRows) {
            [sections addObject:@{
                @"title": [NSString stringWithFormat:@"Headers (%lu)", (unsigned long)e.reqHeaders.count],
                @"rows": headerRows
            }];
        } else {
            [sections addObject:@{@"title": @"Headers", @"rows": @[@{@"value": @"No request headers captured."}]}];
        }
        
        NSString *body = [self decodeBase64:e.reqBodyBase64];
        if (body) {
            [sections addObject:@{
                @"title": @"Body",
                @"rows": @[@{@"value": body, @"mono": @YES}]
            }];
        } else {
            [sections addObject:@{@"title": @"Body", @"rows": @[@{@"value": @"No request body."}]}];
        }
        
    } else if (idx == 2) {
        // ── Response ──
        NSArray *headerRows = [self headerRowsFromDict:e.resHeaders];
        if (headerRows) {
            [sections addObject:@{
                @"title": [NSString stringWithFormat:@"Headers (%lu)", (unsigned long)e.resHeaders.count],
                @"rows": headerRows
            }];
        } else {
            [sections addObject:@{@"title": @"Headers", @"rows": @[@{@"value": @"No response headers captured."}]}];
        }
        
        NSString *body = [self decodeBase64:e.resBodyBase64];
        if (body) {
            [sections addObject:@{
                @"title": @"Body",
                @"rows": @[@{@"value": body, @"mono": @YES}]
            }];
        } else {
            [sections addObject:@{@"title": @"Body", @"rows": @[@{@"value": @"No response body."}]}];
        }
    }
    
    self.currentSections = sections;
    [self.tableView reloadData];
}

// ---------------------------------------------------------------------------
#pragma mark - UITableView
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.currentSections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.currentSections[section][@"title"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.currentSections[section][@"rows"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.currentSections[indexPath.section][@"rows"][indexPath.row];
    
    NSString *label = row[@"label"];
    NSString *value = row[@"value"];
    BOOL isMono = [row[@"mono"] boolValue];
    BOOL hasStatusColor = [row[@"statusColor"] boolValue];
    
    if (label) {
        BOOL shouldWrap = [row[@"wrap"] boolValue];
        
        if (shouldWrap) {
            // Subtitle style: key on top, value wraps below
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.textLabel.text = label;
            cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            if (@available(iOS 13.0, *)) cell.textLabel.textColor = [UIColor secondaryLabelColor];
            
            cell.detailTextLabel.text = value;
            cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.lineBreakMode = NSLineBreakByCharWrapping;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        } else {
            // Value1 style: key left, short value right
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
            cell.textLabel.text = label;
            cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
            cell.detailTextLabel.text = value;
            cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            
            if (hasStatusColor && self.logEntry) {
                NSInteger s = self.logEntry.status;
                if (s >= 200 && s < 300) cell.detailTextLabel.textColor = [UIColor systemGreenColor];
                else if (s >= 300 && s < 400) cell.detailTextLabel.textColor = [UIColor systemOrangeColor];
                else if (s >= 400) cell.detailTextLabel.textColor = [UIColor systemRedColor];
            }
            return cell;
        }
    } else {
        // Full-width content row (headers dump, body, notes)
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
        cell.textLabel.text = value;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        if (isMono) {
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        } else {
            cell.textLabel.font = [UIFont systemFontOfSize:14];
            if (@available(iOS 13.0, *)) {
                cell.textLabel.textColor = [UIColor secondaryLabelColor];
            }
        }
        
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *row = self.currentSections[indexPath.section][@"rows"][indexPath.row];
    NSString *value = row[@"value"];
    if (!value) return;
    
    [UIPasteboard generalPasteboard].string = value;
    
    // Brief feedback
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    UIColor *origColor = cell.backgroundColor;
    
        cell.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.15];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{
            cell.backgroundColor = origColor;
        }];
    });
}

@end
