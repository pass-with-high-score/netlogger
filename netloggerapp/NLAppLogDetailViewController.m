#import "NLAppLogDetailViewController.h"
#import <WebKit/WebKit.h>

@interface NLAppLogDetailViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *currentSections;
@end

@implementation NLAppLogDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Overview", @"Request", @"Response"]];
    self.segmentedControl.selectedSegmentIndex = 0;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentedControl;

    UIBarButtonItem *actionBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
        style:UIBarButtonItemStylePlain target:self action:@selector(showActions)];
    self.navigationItem.rightBarButtonItem = actionBtn;

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

// ---------------------------------------------------------------------------
#pragma mark - Actions
// ---------------------------------------------------------------------------

- (void)showActions {
    if (!self.logEntry) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Options" message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Replay Request" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self replayRequest]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy Screen Content" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self copyContent]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy cURL" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *curl = [self.logEntry toCurlCommand];
        if (curl) { [UIPasteboard generalPasteboard].string = curl; [self showToast:@"Copied cURL!"]; }
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Share Log as Text" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self shareAsText]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Export Raw Response (.bin)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self exportBinaryResponse]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)copyContent {
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *section in self.currentSections) {
        [text appendFormat:@"── %@ ──\n", section[@"title"]];
        for (NSDictionary *row in section[@"rows"]) {
            if (row[@"label"]) [text appendFormat:@"%@: %@\n", row[@"label"], row[@"value"]];
            else [text appendFormat:@"%@\n", row[@"value"]];
        }
        [text appendString:@"\n"];
    }
    [UIPasteboard generalPasteboard].string = text;
    [self showToast:@"Copied!"];
}

- (void)shareAsText {
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *section in self.currentSections) {
        [text appendFormat:@"── %@ ──\n", section[@"title"]];
        for (NSDictionary *row in section[@"rows"]) {
            if (row[@"label"]) [text appendFormat:@"%@: %@\n", row[@"label"], row[@"value"]];
            else [text appendFormat:@"%@\n", row[@"value"]];
        }
        [text appendString:@"\n"];
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)replayRequest {
    if (!self.logEntry || !self.logEntry.url) return;
    NSURL *url = [NSURL URLWithString:self.logEntry.url];
    if (!url) return;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = self.logEntry.method ?: @"GET";
    if (self.logEntry.reqHeaders) {
        for (NSString *key in self.logEntry.reqHeaders) {
            [req setValue:[NSString stringWithFormat:@"%@", self.logEntry.reqHeaders[key]] forHTTPHeaderField:key];
        }
    }
    if (self.logEntry.reqBodyBase64) {
        req.HTTPBody = [[NSData alloc] initWithBase64EncodedString:self.logEntry.reqBodyBase64 options:0];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Replaying" message:@"Sending request..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:nil];

    NSTimeInterval start = [[NSDate date] timeIntervalSince1970];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                NSTimeInterval duration = ([[NSDate date] timeIntervalSince1970] - start) * 1000.0;
                NSString *msg;
                if (err) { msg = [NSString stringWithFormat:@"Error: %@", err.localizedDescription]; }
                else {
                    NSHTTPURLResponse *http = (NSHTTPURLResponse *)res;
                    msg = [NSString stringWithFormat:@"Status: %ld\nDuration: %.0f ms\nBytes: %lu", (long)http.statusCode, duration, (unsigned long)data.length];
                }
                UIAlertController *resAlert = [UIAlertController alertControllerWithTitle:@"Replay Result" message:msg preferredStyle:UIAlertControllerStyleAlert];
                [resAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:resAlert animated:YES completion:nil];
            }];
        });
    }] resume];
}

- (void)exportBinaryResponse {
    if (!self.logEntry.resBodyBase64 || self.logEntry.resBodyBase64.length == 0) { [self showToast:@"No Response Body"]; return; }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:self.logEntry.resBodyBase64 options:0];
    if (!data) return;
    NSString *fileName = [NSString stringWithFormat:@"/var/mobile/Downloads/dump_%ld.bin", (long)[[NSDate date] timeIntervalSince1970]];
    [data writeToFile:fileName atomically:YES];
    [self showToast:@"Saved to Downloads!"];
}

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = [NSString stringWithFormat:@" %@ ", message];
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
    [UIView animateWithDuration:0.3 delay:1.0 options:0 animations:^{ toast.alpha = 0; } completion:^(BOOL done) { [toast removeFromSuperview]; }];
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

- (NSDictionary *)decodeBase64:(NSString *)base64 {
    if (!base64 || base64.length == 0) return nil;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (!data) return @{@"display": @"(Invalid Base64)", @"raw": @"(Invalid Base64)"};

    NSString *result = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (json) {
        NSData *pretty = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
        if (pretty) result = [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding];
    }
    if (!result) result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!result) {
        NSUInteger peekLen = MIN(data.length, (NSUInteger)256);
        NSData *peekData = [data subdataWithRange:NSMakeRange(0, peekLen)];
        NSString *s = [NSString stringWithFormat:@"(Binary Data - %lu bytes)\n\nHex Dump (First %lu bytes):\n%@", (unsigned long)data.length, (unsigned long)peekLen, [peekData description]];
        return @{@"display": s, @"raw": s};
    }

    NSString *rawResult = result;
    static const NSUInteger kMaxDisplayLength = 20000;
    if (result.length > kMaxDisplayLength) {
        result = [NSString stringWithFormat:@"%@\n\n── Truncated ──\nShowing %lu of %lu characters.",
            [result substringToIndex:kMaxDisplayLength], (unsigned long)kMaxDisplayLength, (unsigned long)result.length];
    }
    return @{@"display": result, @"raw": rawResult};
}

- (void)rebuildData {
    NSMutableArray *sections = [NSMutableArray array];
    NLLogEntry *e = self.logEntry;
    if (!e) { self.currentSections = @[]; [self.tableView reloadData]; return; }

    NSInteger idx = self.segmentedControl.selectedSegmentIndex;

    if (idx == 0) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSDate *d = [NSDate dateWithTimeIntervalSince1970:e.timestamp];
        [sections addObject:@{
            @"title": @"General",
            @"rows": @[
                @{@"label": @"URL",      @"value": e.url ?: @"—", @"wrap": @YES},
                @{@"label": @"Host",     @"value": [e hostFromURL], @"wrap": @YES},
                @{@"label": @"Path",     @"value": [e pathFromURL], @"wrap": @YES},
                @{@"label": @"Method",   @"value": e.method ?: @"—"},
                @{@"label": @"Status",   @"value": [e statusText], @"statusColor": @YES},
                @{@"label": @"Duration", @"value": [e durationText]},
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
    } else if (idx == 1) {
        NSArray *headerRows = [self headerRowsFromDict:e.reqHeaders];
        if (headerRows) {
            [sections addObject:@{@"title": [NSString stringWithFormat:@"Headers (%lu)", (unsigned long)e.reqHeaders.count], @"rows": headerRows}];
        } else {
            [sections addObject:@{@"title": @"Headers", @"rows": @[@{@"value": @"No request headers captured."}]}];
        }
        NSDictionary *bodyDict = [self decodeBase64:e.reqBodyBase64];
        if (bodyDict) {
            [sections addObject:@{@"title": @"Body", @"rows": @[@{@"value": bodyDict[@"display"], @"rawValue": bodyDict[@"raw"], @"mono": @YES}]}];
        } else {
            [sections addObject:@{@"title": @"Body", @"rows": @[@{@"value": @"No request body."}]}];
        }
    } else if (idx == 2) {
        NSArray *headerRows = [self headerRowsFromDict:e.resHeaders];
        if (headerRows) {
            [sections addObject:@{@"title": [NSString stringWithFormat:@"Headers (%lu)", (unsigned long)e.resHeaders.count], @"rows": headerRows}];
        } else {
            [sections addObject:@{@"title": @"Headers", @"rows": @[@{@"value": @"No response headers captured."}]}];
        }

        NSString *contentType = e.resHeaders[@"Content-Type"] ?: e.resHeaders[@"content-type"];
        contentType = [contentType lowercaseString];
        BOOL isMedia = ([contentType hasPrefix:@"image/"] || [contentType hasPrefix:@"video/"] || [contentType hasPrefix:@"audio/"]);
        if (isMedia && e.resBodyBase64.length > 0) {
            [sections addObject:@{@"title": @"Media Preview", @"rows": @[@{@"value": @"Tap to preview media", @"action": @"previewMedia", @"contentType": contentType}]}];
        }
        BOOL isHTML = (contentType && [contentType containsString:@"html"]);
        if (isHTML && e.resBodyBase64.length > 0) {
            [sections addObject:@{@"title": @"HTML Preview", @"rows": @[@{@"value": @"Tap to render HTML", @"action": @"previewHTML"}]}];
        }

        NSDictionary *bodyDict = [self decodeBase64:e.resBodyBase64];
        if (bodyDict) {
            [sections addObject:@{@"title": @"Body", @"rows": @[@{@"value": bodyDict[@"display"], @"rawValue": bodyDict[@"raw"], @"mono": @YES}]}];
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.currentSections.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.currentSections[section][@"title"]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.currentSections[section][@"rows"] count]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.currentSections[indexPath.section][@"rows"][indexPath.row];
    NSString *label = row[@"label"];
    NSString *value = row[@"value"];
    BOOL isMono = [row[@"mono"] boolValue];
    BOOL hasStatusColor = [row[@"statusColor"] boolValue];

    if (label) {
        BOOL shouldWrap = [row[@"wrap"] boolValue];
        if (shouldWrap) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.textLabel.text = label;
            cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.detailTextLabel.text = value;
            cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.lineBreakMode = NSLineBreakByCharWrapping;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            return cell;
        } else {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
            cell.textLabel.text = label;
            cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
            cell.detailTextLabel.text = value;
            cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
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
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
        cell.textLabel.text = value;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (isMono) {
            cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        } else {
            cell.textLabel.font = [UIFont systemFontOfSize:14];
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
        }
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.currentSections[indexPath.section][@"rows"][indexPath.row];

    NSString *action = row[@"action"];
    if ([action isEqualToString:@"previewMedia"]) { [self previewMedia:row[@"contentType"]]; return; }
    if ([action isEqualToString:@"previewHTML"]) { [self previewHTML]; return; }

    NSString *value = row[@"rawValue"] ?: row[@"value"];
    if (!value) return;
    [UIPasteboard generalPasteboard].string = value;
    [self showToast:@"Copied!"];

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.15];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{
            cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        }];
    });
}

- (void)previewHTML {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:self.logEntry.resBodyBase64 options:0];
    if (!data) { [self showToast:@"No HTML Data"]; return; }
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!html) { [self showToast:@"Invalid HTML Data"]; return; }
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"HTML Preview";
    vc.view.backgroundColor = [UIColor systemBackgroundColor];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:vc.view.bounds];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:webView];
    NSURL *baseURL = self.logEntry.url ? [NSURL URLWithString:self.logEntry.url] : nil;
    [webView loadHTMLString:html baseURL:baseURL];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)previewMedia:(NSString *)contentType {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:self.logEntry.resBodyBase64 options:0];
    if (!data) return;
    if ([contentType hasPrefix:@"image/"]) {
        UIImage *img = [UIImage imageWithData:data];
        if (!img) { [self showToast:@"Invalid Image Data"]; return; }
        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor systemBackgroundColor];
        UIImageView *iv = [[UIImageView alloc] initWithImage:img];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        iv.frame = vc.view.bounds;
        [vc.view addSubview:iv];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end
