#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <syslog.h>

#define LOG_FILENAME  @"com.minh.netlogger.logs.txt"
#define NL_DOMAIN     CFSTR("com.minh.netlogger")
#define TAG           "NetLogger"

// ---------------------------------------------------------------------------
// Log writer
// ---------------------------------------------------------------------------

static NSString *getLogPath() {
    NSString *home = NSHomeDirectory();
    NSString *caches = [home stringByAppendingPathComponent:@"Library/Caches"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;
    if (![fm fileExistsAtPath:caches]) {
        BOOL success = [fm createDirectoryAtPath:caches withIntermediateDirectories:YES attributes:nil error:&error];
        if (!success) {
            NSLog(@"[NetLogger-Debug] Failed to create Caches dir: %@", error);
        }
    }
    NSString *path = [caches stringByAppendingPathComponent:LOG_FILENAME];
    // NSLog(@"[NetLogger-Debug] Log Path is: %@", path);
    return path;
}

static void appendLine(NSString *text) {
    NSString *logPath = getLogPath();
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:logPath]) {
        BOOL success = [fm createFileAtPath:logPath contents:nil attributes:@{NSFilePosixPermissions: @(0666)}];
        if (!success) {
            NSLog(@"[NetLogger-Debug] Failed to create log file at path: %@", logPath);
            return;
        }
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        NSLog(@"[NetLogger-Debug] Cannot open log file for writing at path: %@", logPath);
        return;
    }
    [fh seekToEndOfFile];
    [fh writeData:[[text stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
    
    // Uncomment to see every log written
    // NSLog(@"[NetLogger-Debug] Wrote line to %@", logPath);
}

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

static NSDictionary *readPrefs() {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.minh.netlogger.settings.plist"];
    if (d) return d;
    
    d = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.minh.netlogger.settings.plist"];
    if (d) return d;


    CFPreferencesAppSynchronize(NL_DOMAIN);
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    CFPropertyListRef en   = CFPreferencesCopyAppValue(CFSTR("enabled"), NL_DOMAIN);
    CFPropertyListRef apps = CFPreferencesCopyAppValue(CFSTR("selectedApps"), NL_DOMAIN);
    CFPropertyListRef bl   = CFPreferencesCopyAppValue(CFSTR("blacklistedDomains"), NL_DOMAIN);
    if (en)   r[@"enabled"]      = (__bridge_transfer id)en;
    if (apps) r[@"selectedApps"] = (__bridge_transfer id)apps;
    if (bl)   r[@"blacklistedDomains"] = (__bridge_transfer id)bl;
    return r.count ? r : nil;
}

static BOOL isAppEnabled() {
    NSDictionary *prefs = readPrefs();
    if (![prefs[@"enabled"] boolValue]) return NO;
    NSArray *sel = prefs[@"selectedApps"];
    if (!sel.count) return NO;
    return [sel containsObject:[[NSBundle mainBundle] bundleIdentifier] ?: @""];
}

// ---------------------------------------------------------------------------
// MitM Response Modifier
// ---------------------------------------------------------------------------

static NSArray *readMitmRules() {
    NSDictionary *prefs = readPrefs();
    NSArray *rules = prefs[@"mitmRules"];
    if (![rules isKindOfClass:[NSArray class]]) return nil;
    return rules;
}

// Đặt giá trị vào nested key path (vd: "data.user.is_vip")
static void setNestedValue(NSMutableDictionary *dict, NSString *keyPath, id value) {
    NSArray *keys = [keyPath componentsSeparatedByString:@"."];
    NSMutableDictionary *current = dict;
    
    for (NSUInteger i = 0; i < keys.count - 1; i++) {
        id next = current[keys[i]];
        if ([next isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *mutable = [next mutableCopy];
            current[keys[i]] = mutable;
            current = mutable;
        } else {
            return; // Path không tồn tại, bỏ qua
        }
    }
    current[[keys lastObject]] = value;
}

// Parse giá trị từ string sang đúng kiểu dữ liệu
static id parseValue(NSString *valueStr) {
    if (!valueStr) return @"";
    NSString *lower = [valueStr lowercaseString];
    if ([lower isEqualToString:@"true"]) return @YES;
    if ([lower isEqualToString:@"false"]) return @NO;
    if ([lower isEqualToString:@"null"]) return [NSNull null];
    
    // Thử parse số
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    NSNumber *num = [f numberFromString:valueStr];
    if (num) return num;
    
    // Mặc định là string
    return valueStr;
}

// Áp dụng tất cả MitM rules lên response data
static NSData *applyMitmRules(NSData *originalData, NSURLRequest *request) {
    if (!originalData || !request.URL) return originalData;
    
    NSArray *rules = readMitmRules();
    if (!rules || rules.count == 0) return originalData;
    
    NSString *urlString = request.URL.absoluteString;
    BOOL matched = NO;
    
    // Tìm rules khớp với URL
    NSMutableArray *matchedRules = [NSMutableArray array];
    for (NSDictionary *rule in rules) {
        if (![rule isKindOfClass:[NSDictionary class]]) continue;
        if (![rule[@"enabled"] boolValue]) continue;
        NSString *pattern = rule[@"url_pattern"];
        if (pattern && [urlString containsString:pattern]) {
            [matchedRules addObject:rule];
            matched = YES;
        }
    }
    
    if (!matched) return originalData;
    
    // Parse JSON gốc
    NSError *parseError = nil;
    id jsonObj = [NSJSONSerialization JSONObjectWithData:originalData
                                               options:NSJSONReadingMutableContainers
                                                 error:&parseError];
    if (parseError || ![jsonObj isKindOfClass:[NSDictionary class]]) {
        return originalData; // Không phải JSON, bỏ qua
    }
    
    NSMutableDictionary *json = (NSMutableDictionary *)jsonObj;
    
    // Áp dụng từng rule
    for (NSDictionary *rule in matchedRules) {
        NSString *keyPath = rule[@"key_path"];
        NSString *valueStr = rule[@"new_value"];
        if (!keyPath || keyPath.length == 0) continue;
        
        id newValue = parseValue(valueStr);
        setNestedValue(json, keyPath, newValue);
        
        NSLog(@"[NetLogger-MitM] ✅ URL: %@ | Đổi '%@' → %@", urlString, keyPath, newValue);
    }
    
    // Đóng gói lại
    NSData *modifiedData = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    return modifiedData ?: originalData;
}

// ---------------------------------------------------------------------------
// Build log entry
// ---------------------------------------------------------------------------

static NSString *buildEntry(NSURLRequest *request, NSData *data, NSURLResponse *response, double durationMs) {
    if (!request || !request.URL) return nil;
    
    // Check blacklist
    NSDictionary *prefs = readPrefs();
    NSString *blacklistString = prefs[@"blacklistedDomains"];
    if (blacklistString && blacklistString.length > 0) {
        NSString *host = request.URL.host.lowercaseString;
        if (host) {
            NSArray *domains = [blacklistString componentsSeparatedByString:@","];
            for (NSString *d in domains) {
                NSString *trimmed = [d stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;
                if (trimmed.length > 0 && [host containsString:trimmed]) {
                    return nil; // Blocked by blacklist
                }
            }
        }
    }

    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = [[NSUUID UUID] UUIDString];
    dict[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    dict[@"method"] = request.HTTPMethod ?: @"GET";
    dict[@"url"] = request.URL.absoluteString ?: @"(unknown)";
    dict[@"status"] = http ? @(http.statusCode) : @(0);
    dict[@"app"] = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    dict[@"duration_ms"] = @(durationMs);
    
    if (request.allHTTPHeaderFields) {
        dict[@"req_headers"] = request.allHTTPHeaderFields;
    }
    
    NSData *reqBodyData = request.HTTPBody;
    if (reqBodyData.length > 0 && reqBodyData.length < 1024 * 1024) {
        dict[@"req_body_base64"] = [reqBodyData base64EncodedStringWithOptions:0];
    }
    
    if (http && http.allHeaderFields) {
        dict[@"res_headers"] = http.allHeaderFields;
    }
    
    if (data.length > 0 && data.length < 1024 * 1024) {
        dict[@"res_body_base64"] = [data base64EncodedStringWithOptions:0];
    }
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
    if (!jsonData) return nil;
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

// ---------------------------------------------------------------------------
// Delegate proxy — captures delegate-based NSURLSession traffic
// (the common pattern in most modern apps)
// ---------------------------------------------------------------------------

@interface NLDelegateProxy : NSObject <NSURLSessionDataDelegate, NSURLSessionTaskDelegate>
- (instancetype)initWithDelegate:(id<NSURLSessionDelegate>)delegate;
@end

@implementation NLDelegateProxy {
    id<NSURLSessionDelegate> _real;
    NSMutableDictionary<NSNumber *, NSMutableData *> *_bodies;
    NSMutableDictionary<NSNumber *, NSNumber *> *_startTimes;
}

- (instancetype)initWithDelegate:(id<NSURLSessionDelegate>)delegate {
    if ((self = [super init])) {
        _real       = delegate;
        _bodies     = [NSMutableDictionary dictionary];
        _startTimes = [NSMutableDictionary dictionary];
    }
    return self;
}

// Forward any selector we don't implement ourselves to the real delegate
- (BOOL)respondsToSelector:(SEL)sel {
    return [super respondsToSelector:sel] || [_real respondsToSelector:sel];
}

- (id)forwardingTargetForSelector:(SEL)sel {
    if ([_real respondsToSelector:sel]) return _real;
    return nil;
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data {
    NSNumber *tid = @(task.taskIdentifier);
    if (!_startTimes[tid]) _startTimes[tid] = @(CFAbsoluteTimeGetCurrent());
    if (!_bodies[tid]) _bodies[tid] = [NSMutableData data];
    [_bodies[tid] appendData:data];
    if ([_real respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)])
        [(id<NSURLSessionDataDelegate>)_real URLSession:session dataTask:task didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (!error) {
        NSNumber *tid = @(task.taskIdentifier);
        double startTime = [_startTimes[tid] doubleValue];
        double durationMs = startTime > 0 ? (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0 : 0;
        NSString *entry = buildEntry(task.currentRequest ?: task.originalRequest,
                                     _bodies[tid], task.response, durationMs);
        if (entry) appendLine(entry);
        [_bodies removeObjectForKey:tid];
        [_startTimes removeObjectForKey:tid];
    }
    if ([_real respondsToSelector:@selector(URLSession:task:didCompleteWithError:)])
        [(id<NSURLSessionTaskDelegate>)_real URLSession:session task:task didCompleteWithError:error];
}

@end

// ---------------------------------------------------------------------------
// NSURLSession hooks
// ---------------------------------------------------------------------------

static const char kProxyKey = 0;

%hook NSURLSession

// ── Delegate-based sessions (most apps) ─────────────────────────────────────
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)config
                                  delegate:(id<NSURLSessionDelegate>)delegate
                             delegateQueue:(NSOperationQueue *)queue {
    if (delegate && isAppEnabled()) {
        NLDelegateProxy *proxy = [[NLDelegateProxy alloc] initWithDelegate:delegate];
        NSURLSession *session = %orig(config, proxy, queue);
        // Retain proxy for the session's lifetime
        objc_setAssociatedObject(session, &kProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return session;
    }
    return %orig;
}

// ── Completion-handler-based sessions (shared session, simple calls) ─────────
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!isAppEnabled()) return %orig;
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    void (^h)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        double durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0;
        // MitM: Sửa response trước khi log và trả về cho app
        NSData *finalData = (e == nil && d != nil) ? applyMitmRules(d, request) : d;
        NSString *entry = buildEntry(request, finalData, r, durationMs);
        if (entry) appendLine(entry);
        if (completionHandler) completionHandler(finalData, r, e);
    };
    return %orig(request, h);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!isAppEnabled()) return %orig;
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    NSMutableURLRequest *fakeReq = [NSMutableURLRequest requestWithURL:url];
    void (^h)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        double durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0;
        NSData *finalData = (e == nil && d != nil) ? applyMitmRules(d, fakeReq) : d;
        NSString *entry = buildEntry(fakeReq, finalData, r, durationMs);
        if (entry) appendLine(entry);
        if (completionHandler) completionHandler(finalData, r, e);
    };
    return %orig(url, h);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!isAppEnabled()) return %orig;
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    void (^h)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        double durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0;
        NSData *finalData = (e == nil && d != nil) ? applyMitmRules(d, request) : d;
        NSString *entry = buildEntry(request, finalData, r, durationMs);
        if (entry) appendLine(entry);
        if (completionHandler) completionHandler(finalData, r, e);
    };
    return %orig(request, bodyData, h);
}

%end

// ---------------------------------------------------------------------------
// Constructor diagnostic
// ---------------------------------------------------------------------------

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (!bid) return;

    NSDictionary *prefs = readPrefs();
    BOOL masterOn       = [prefs[@"enabled"] boolValue];
    NSArray *selected   = prefs[@"selectedApps"];
    BOOL thisApp        = [selected containsObject:bid];

    if (masterOn && thisApp) {
        NSDictionary *diag = @{
            @"id": [[NSUUID UUID] UUIDString],
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"method": @"DIAGNOSTIC",
            @"url": [NSString stringWithFormat:@"diagnostic://app-started/%@", bid],
            @"status": @(200),
            @"app": bid
        };
        NSData *d = [NSJSONSerialization dataWithJSONObject:diag options:0 error:nil];
        if (d) {
            appendLine([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]);
        }
    }
}
