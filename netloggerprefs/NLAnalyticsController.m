#import "NLAnalyticsController.h"
#import "NLLogDetailViewController.h"
#import "NLLocalization.h"

#define PREFS_PLIST @"/var/jb/var/mobile/Library/Preferences/com.minh.netlogger.settings.plist"

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(id)arg1;
@property(nonatomic, readonly) NSURL *dataContainerURL;
@end

// ---------------------------------------------------------------------------
#pragma mark - Stats Model
// ---------------------------------------------------------------------------

@interface NLAnalyticsStats : NSObject
@property (nonatomic, assign) NSUInteger totalRequests;
@property (nonatomic, assign) NSUInteger status2xx;
@property (nonatomic, assign) NSUInteger status3xx;
@property (nonatomic, assign) NSUInteger status4xx;
@property (nonatomic, assign) NSUInteger status5xx;
@property (nonatomic, assign) NSUInteger statusNone;
@property (nonatomic, assign) double totalDurationMs;
@property (nonatomic, assign) double totalTrafficBytes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *methodCounts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *domainCounts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *appCounts;
@end

@implementation NLAnalyticsStats
- (instancetype)init {
    if (self = [super init]) {
        _methodCounts = [NSMutableDictionary dictionary];
        _domainCounts = [NSMutableDictionary dictionary];
        _appCounts = [NSMutableDictionary dictionary];
    }
    return self;
}

- (double)successRate {
    if (self.totalRequests == 0) return 0;
    return (double)self.status2xx / self.totalRequests * 100.0;
}

- (double)avgDurationMs {
    if (self.totalRequests == 0) return 0;
    return self.totalDurationMs / self.totalRequests;
}

- (NSString *)formattedTraffic {
    double bytes = self.totalTrafficBytes;
    if (bytes < 1024) return [NSString stringWithFormat:@"%.0f B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    if (bytes < 1024 * 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

- (NSArray<NSDictionary *> *)sortedMethods {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in self.methodCounts) {
        [result addObject:@{@"name": key, @"count": self.methodCounts[key]}];
    }
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"count"] compare:a[@"count"]];
    }];
    return result;
}

- (NSArray<NSDictionary *> *)topDomains:(NSUInteger)limit {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in self.domainCounts) {
        [result addObject:@{@"name": key, @"count": self.domainCounts[key]}];
    }
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"count"] compare:a[@"count"]];
    }];
    if (result.count > limit) {
        return [result subarrayWithRange:NSMakeRange(0, limit)];
    }
    return result;
}

- (NSArray<NSDictionary *> *)sortedApps {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in self.appCounts) {
        [result addObject:@{@"name": key, @"count": self.appCounts[key]}];
    }
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"count"] compare:a[@"count"]];
    }];
    return result;
}
@end

// ---------------------------------------------------------------------------
#pragma mark - Custom Bar Cell
// ---------------------------------------------------------------------------

@interface NLBarCell : UITableViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *percentLabel;
@property (nonatomic, strong) UIView *barBackground;
@property (nonatomic, strong) UIView *barFill;
@property (nonatomic, strong) NSLayoutConstraint *barWidthConstraint;
@end

@implementation NLBarCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_nameLabel];

        _countLabel = [[UILabel alloc] init];
        _countLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold];
        _countLabel.textAlignment = NSTextAlignmentRight;
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_countLabel];

        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        _percentLabel.textColor = [UIColor secondaryLabelColor];
        _percentLabel.textAlignment = NSTextAlignmentRight;
        _percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_percentLabel];

        _barBackground = [[UIView alloc] init];
        _barBackground.backgroundColor = [UIColor tertiarySystemFillColor];
        _barBackground.layer.cornerRadius = 3;
        _barBackground.clipsToBounds = YES;
        _barBackground.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_barBackground];

        _barFill = [[UIView alloc] init];
        _barFill.layer.cornerRadius = 3;
        _barFill.clipsToBounds = YES;
        _barFill.translatesAutoresizingMaskIntoConstraints = NO;
        [_barBackground addSubview:_barFill];

        _barWidthConstraint = [_barFill.widthAnchor constraintEqualToConstant:0];

        [NSLayoutConstraint activateConstraints:@[
            [_nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],

            [_percentLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_percentLabel.centerYAnchor constraintEqualToAnchor:_nameLabel.centerYAnchor],
            [_percentLabel.widthAnchor constraintEqualToConstant:44],

            [_countLabel.trailingAnchor constraintEqualToAnchor:_percentLabel.leadingAnchor constant:-8],
            [_countLabel.centerYAnchor constraintEqualToAnchor:_nameLabel.centerYAnchor],

            [_barBackground.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_barBackground.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_barBackground.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:6],
            [_barBackground.heightAnchor constraintEqualToConstant:6],
            [_barBackground.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],

            [_barFill.leadingAnchor constraintEqualToAnchor:_barBackground.leadingAnchor],
            [_barFill.topAnchor constraintEqualToAnchor:_barBackground.topAnchor],
            [_barFill.bottomAnchor constraintEqualToAnchor:_barBackground.bottomAnchor],
            _barWidthConstraint,
        ]];
    }
    return self;
}

- (void)configureName:(NSString *)name count:(NSUInteger)count total:(NSUInteger)total color:(UIColor *)color {
    self.nameLabel.text = name;
    self.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)count];

    double pct = total > 0 ? (double)count / total * 100.0 : 0;
    self.percentLabel.text = [NSString stringWithFormat:@"%.0f%%", pct];

    self.barFill.backgroundColor = color;

    // Bar width = percentage of available width. We'll update in layoutSubviews.
    CGFloat maxBarWidth = UIScreen.mainScreen.bounds.size.width - 64;
    self.barWidthConstraint.constant = maxBarWidth * (total > 0 ? (CGFloat)count / total : 0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Recalculate bar width based on actual background width
    // (called after constraints resolve)
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Custom Stat Cell
// ---------------------------------------------------------------------------

@interface NLStatCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@end

@implementation NLStatCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _titleLabel.textColor = [UIColor secondaryLabelColor];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_titleLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightBold];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:28],
            [_iconView.heightAnchor constraintEqualToConstant:28],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8],

            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:50],
        ]];
    }
    return self;
}

- (void)configureIcon:(NSString *)sfName color:(UIColor *)color title:(NSString *)title value:(NSString *)value {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    UIImage *img = [[UIImage systemImageNamed:sfName withConfiguration:config]
                    imageWithTintColor:[UIColor whiteColor]
                    renderingMode:UIImageRenderingModeAlwaysOriginal];

    CGFloat boxSize = 28;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(boxSize, boxSize), NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, boxSize, boxSize) cornerRadius:7];
    [color setFill];
    [path fill];
    CGSize imgSize = [img size];
    [img drawAtPoint:CGPointMake((boxSize - imgSize.width) / 2, (boxSize - imgSize.height) / 2)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    self.iconView.image = [result imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    self.titleLabel.text = title;
    self.valueLabel.text = value;
    self.valueLabel.textColor = color;
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Analytics Controller
// ---------------------------------------------------------------------------

// Section indices
enum {
    kSectionSummary = 0,
    kSectionStatus,
    kSectionMethods,
    kSectionDomains,
    kSectionApps,
    kSectionCount
};

@implementation NLAnalyticsController {
    UITableView *_tableView;
    NLAnalyticsStats *_stats;
    NSArray<NSDictionary *> *_sortedMethods;
    NSArray<NSDictionary *> *_topDomains;
    NSArray<NSDictionary *> *_sortedApps;
}

- (void)loadView {
    [super loadView];
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.estimatedRowHeight = 60;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    [_tableView registerClass:[NLStatCell class] forCellReuseIdentifier:@"StatCell"];
    [_tableView registerClass:[NLBarCell class] forCellReuseIdentifier:@"BarCell"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DomainCell"];
    [self.view addSubview:_tableView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NLLocalizedString(@"Network Analytics", @"Network Analytics");

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
        style:UIBarButtonItemStylePlain target:self action:@selector(refreshData)];

    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(pullRefresh:) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = rc;

    [self refreshData];
}

- (void)pullRefresh:(UIRefreshControl *)rc {
    [self refreshData];
    [rc endRefreshing];
}

// ---------------------------------------------------------------------------
#pragma mark - Data Loading
// ---------------------------------------------------------------------------

- (void)refreshData {
    _stats = [[NLAnalyticsStats alloc] init];

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PLIST];
    NSArray *selectedApps = prefs[@"selectedApps"];

    for (NSString *bundleID in selectedApps) {
        if (!bundleID || bundleID.length == 0) continue;

        NSString *logPath = nil;
        if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
            logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/com.minh.netlogger.logs.txt"];
        } else {
            LSApplicationProxy *proxy = [NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:bundleID];
            if (!proxy || !proxy.dataContainerURL) continue;
            logPath = [[proxy.dataContainerURL path] stringByAppendingPathComponent:@"Library/Caches/com.minh.netlogger.logs.txt"];
        }

        NSString *content = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
        if (!content || content.length == 0) continue;

        NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            if (line.length == 0) continue;
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            if (!data) continue;

            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![dict isKindOfClass:[NSDictionary class]]) continue;

            [self processLogEntry:dict];
        }
    }

    _sortedMethods = [_stats sortedMethods];
    _topDomains = [_stats topDomains:10];
    _sortedApps = [_stats sortedApps];

    [_tableView reloadData];
}

- (void)processLogEntry:(NSDictionary *)dict {
    _stats.totalRequests++;

    // Status
    NSInteger status = [dict[@"status"] integerValue];
    if (status >= 200 && status < 300) _stats.status2xx++;
    else if (status >= 300 && status < 400) _stats.status3xx++;
    else if (status >= 400 && status < 500) _stats.status4xx++;
    else if (status >= 500) _stats.status5xx++;
    else _stats.statusNone++;

    // Duration
    double duration = [dict[@"duration_ms"] doubleValue];
    if (duration > 0) _stats.totalDurationMs += duration;

    // Traffic (estimate from base64 length * 3/4)
    NSString *reqBody = dict[@"req_body_base64"];
    NSString *resBody = dict[@"res_body_base64"];
    if (reqBody.length > 0) _stats.totalTrafficBytes += reqBody.length * 0.75;
    if (resBody.length > 0) _stats.totalTrafficBytes += resBody.length * 0.75;

    // Method
    NSString *method = dict[@"method"] ?: @"?";
    _stats.methodCounts[method] = @([_stats.methodCounts[method] unsignedIntegerValue] + 1);

    // Domain
    NSString *url = dict[@"url"];
    if (url) {
        NSURL *u = [NSURL URLWithString:url];
        NSString *host = u.host;
        if (host.length > 0) {
            _stats.domainCounts[host] = @([_stats.domainCounts[host] unsignedIntegerValue] + 1);
        }
    }

    // App
    NSString *app = dict[@"app"] ?: @"unknown";
    _stats.appCounts[app] = @([_stats.appCounts[app] unsignedIntegerValue] + 1);
}

// ---------------------------------------------------------------------------
#pragma mark - Table View
// ---------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    if (_stats.totalRequests == 0) return 0;
    NSInteger count = 3; // summary + status + methods
    if (_topDomains.count > 0) count++;
    if (_sortedApps.count > 1) count++;
    return count;
}

- (NSInteger)sectionForLogical:(NSInteger)logical {
    // Map logical sections to actual based on data availability
    if (logical <= kSectionMethods) return logical;
    if (logical == kSectionDomains && _topDomains.count > 0) return kSectionDomains;
    if (logical == kSectionApps && _sortedApps.count > 1) {
        return _topDomains.count > 0 ? 4 : 3;
    }
    return -1;
}

- (NSInteger)logicalForSection:(NSInteger)section {
    if (section <= 2) return section; // summary, status, methods
    if (section == 3) return _topDomains.count > 0 ? kSectionDomains : kSectionApps;
    if (section == 4) return kSectionApps;
    return -1;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (_stats.totalRequests == 0) {
        tv.backgroundView = [self emptyStateView:tv];
        return 0;
    }
    tv.backgroundView = nil;

    NSInteger logical = [self logicalForSection:section];
    switch (logical) {
        case kSectionSummary: return 4;
        case kSectionStatus: return 5;
        case kSectionMethods: return _sortedMethods.count;
        case kSectionDomains: return _topDomains.count;
        case kSectionApps: return _sortedApps.count;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    NSInteger logical = [self logicalForSection:section];
    switch (logical) {
        case kSectionSummary: return NLLocalizedString(@"Overview", @"Overview");
        case kSectionStatus: return NLLocalizedString(@"Status Codes", @"Status Codes");
        case kSectionMethods: return NLLocalizedString(@"HTTP Methods", @"HTTP Methods");
        case kSectionDomains: return [NSString stringWithFormat:@"%@ (%lu)", NLLocalizedString(@"Top Domains", @"Top Domains"), (unsigned long)_topDomains.count];
        case kSectionApps: return NLLocalizedString(@"Per App", @"Per App");
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger logical = [self logicalForSection:indexPath.section];

    // ── Summary ──
    if (logical == kSectionSummary) {
        NLStatCell *cell = [tv dequeueReusableCellWithIdentifier:@"StatCell" forIndexPath:indexPath];
        switch (indexPath.row) {
            case 0:
                [cell configureIcon:@"number.circle" color:[UIColor systemBlueColor]
                    title:NLLocalizedString(@"Total Requests", @"Total Requests")
                    value:[NSString stringWithFormat:@"%lu", (unsigned long)_stats.totalRequests]];
                break;
            case 1:
                [cell configureIcon:@"checkmark.circle" color:[UIColor systemGreenColor]
                    title:NLLocalizedString(@"Success Rate", @"Success Rate")
                    value:[NSString stringWithFormat:@"%.1f%%", [_stats successRate]]];
                break;
            case 2:
                [cell configureIcon:@"clock" color:[UIColor systemOrangeColor]
                    title:NLLocalizedString(@"Avg Response Time", @"Avg Response Time")
                    value:[NSString stringWithFormat:@"%.0f ms", [_stats avgDurationMs]]];
                break;
            case 3:
                [cell configureIcon:@"arrow.up.arrow.down" color:[UIColor systemPurpleColor]
                    title:NLLocalizedString(@"Total Traffic", @"Total Traffic")
                    value:[_stats formattedTraffic]];
                break;
        }
        return cell;
    }

    // ── Status Codes ──
    if (logical == kSectionStatus) {
        NLBarCell *cell = [tv dequeueReusableCellWithIdentifier:@"BarCell" forIndexPath:indexPath];
        NSArray *names = @[@"2xx Success", @"3xx Redirect", @"4xx Client Error", @"5xx Server Error", @"No Response"];
        NSArray *colors = @[[UIColor systemGreenColor], [UIColor systemYellowColor], [UIColor systemOrangeColor], [UIColor systemRedColor], [UIColor systemGrayColor]];
        NSArray *counts = @[@(_stats.status2xx), @(_stats.status3xx), @(_stats.status4xx), @(_stats.status5xx), @(_stats.statusNone)];
        [cell configureName:names[indexPath.row]
                      count:[counts[indexPath.row] unsignedIntegerValue]
                      total:_stats.totalRequests
                      color:colors[indexPath.row]];
        return cell;
    }

    // ── HTTP Methods ──
    if (logical == kSectionMethods) {
        NLBarCell *cell = [tv dequeueReusableCellWithIdentifier:@"BarCell" forIndexPath:indexPath];
        NSDictionary *item = _sortedMethods[indexPath.row];
        UIColor *color = [UIColor systemBlueColor];
        NSString *m = item[@"name"];
        if ([m isEqualToString:@"GET"]) color = [UIColor systemGreenColor];
        else if ([m isEqualToString:@"POST"]) color = [UIColor systemBlueColor];
        else if ([m isEqualToString:@"PUT"]) color = [UIColor systemOrangeColor];
        else if ([m isEqualToString:@"DELETE"]) color = [UIColor systemRedColor];
        else if ([m isEqualToString:@"PATCH"]) color = [UIColor systemPurpleColor];
        [cell configureName:m count:[item[@"count"] unsignedIntegerValue] total:_stats.totalRequests color:color];
        return cell;
    }

    // ── Top Domains ──
    if (logical == kSectionDomains) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"DomainCell" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        NSDictionary *item = _topDomains[indexPath.row];
        NSUInteger count = [item[@"count"] unsignedIntegerValue];
        double pct = _stats.totalRequests > 0 ? (double)count / _stats.totalRequests * 100.0 : 0;

        // Rank badge
        NSString *rank;
        UIColor *rankColor;
        if (indexPath.row == 0) { rank = @"🥇"; rankColor = [UIColor labelColor]; }
        else if (indexPath.row == 1) { rank = @"🥈"; rankColor = [UIColor labelColor]; }
        else if (indexPath.row == 2) { rank = @"🥉"; rankColor = [UIColor labelColor]; }
        else { rank = [NSString stringWithFormat:@" %lu", (unsigned long)(indexPath.row + 1)]; rankColor = [UIColor secondaryLabelColor]; }

        NSString *text = [NSString stringWithFormat:@"%@ %@", rank, item[@"name"]];
        NSString *detail = [NSString stringWithFormat:@"%lu (%.0f%%)", (unsigned long)count, pct];

        cell.textLabel.text = text;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
        cell.textLabel.textColor = rankColor;

        // Use accessoryView for count
        UILabel *detailLabel = [[UILabel alloc] init];
        detailLabel.text = detail;
        detailLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        detailLabel.textColor = [UIColor secondaryLabelColor];
        [detailLabel sizeToFit];
        cell.accessoryView = detailLabel;

        return cell;
    }

    // ── Per App ──
    if (logical == kSectionApps) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"DomainCell" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        NSDictionary *item = _sortedApps[indexPath.row];
        NSUInteger count = [item[@"count"] unsignedIntegerValue];

        cell.textLabel.text = item[@"name"];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
        cell.textLabel.textColor = [UIColor labelColor];

        UILabel *detailLabel = [[UILabel alloc] init];
        detailLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)count];
        detailLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold];
        detailLabel.textColor = [UIColor systemBlueColor];
        [detailLabel sizeToFit];
        cell.accessoryView = detailLabel;

        return cell;
    }

    return [[UITableViewCell alloc] init];
}

// ---------------------------------------------------------------------------
#pragma mark - Empty State
// ---------------------------------------------------------------------------

- (UIView *)emptyStateView:(UITableView *)tv {
    UIView *emptyView = [[UIView alloc] initWithFrame:tv.bounds];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chart.bar.xaxis"]];
    icon.tintColor = [UIColor systemGray3Color];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [emptyView addSubview:icon];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.text = NLLocalizedString(@"No Analytics Data", @"No Analytics Data");
    titleLbl.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    titleLbl.textColor = [UIColor secondaryLabelColor];
    titleLbl.textAlignment = NSTextAlignmentCenter;
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    [emptyView addSubview:titleLbl];

    UILabel *subtitleLbl = [[UILabel alloc] init];
    subtitleLbl.text = NLLocalizedString(@"Start capturing network traffic\nto see analytics here.", @"Start capturing network traffic\nto see analytics here.");
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

    return emptyView;
}

@end
