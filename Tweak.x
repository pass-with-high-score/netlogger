#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <syslog.h>

#define SETTINGS_PATH @"/var/tmp/com.minh.netlogger.settings.plist"
#define LOG_PATH      @"/var/tmp/com.minh.netlogger.logs.txt"
#define NL_DOMAIN     CFSTR("com.minh.netlogger")
#define TAG           "NetLogger"

// ---------------------------------------------------------------------------
// Log writer
// ---------------------------------------------------------------------------

static void appendLine(NSString *text) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:LOG_PATH])
        [fm createFileAtPath:LOG_PATH contents:nil attributes:@{NSFilePosixPermissions: @(0666)}];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LOG_PATH];
    if (!fh) { syslog(LOG_ERR, TAG ": cannot open log file"); return; }
    [fh seekToEndOfFile];
    [fh writeData:[[text stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

static NSDictionary *readPrefs() {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:SETTINGS_PATH];
    if (d) return d;

    CFPreferencesAppSynchronize(NL_DOMAIN);
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    CFPropertyListRef en   = CFPreferencesCopyAppValue(CFSTR("enabled"), NL_DOMAIN);
    CFPropertyListRef apps = CFPreferencesCopyAppValue(CFSTR("selectedApps"), NL_DOMAIN);
    if (en)   r[@"enabled"]      = (__bridge_transfer id)en;
    if (apps) r[@"selectedApps"] = (__bridge_transfer id)apps;
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
// Build log entry
// ---------------------------------------------------------------------------

static NSString *buildEntry(NSURLRequest *request, NSData *data, NSURLResponse *response) {
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";

    NSString *body = @"(no body / binary)";
    if (data.length > 0 && data.length < 16384) {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (s) body = s;
    }
    return [NSString stringWithFormat:
        @"[%@] %@ %@\nStatus: %@\nApp: %@\nResponse:\n%@\n---",
        [df stringFromDate:[NSDate date]],
        request.HTTPMethod ?: @"GET",
        request.URL.absoluteString ?: @"(unknown)",
        http ? @(http.statusCode).stringValue : @"?",
        [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown",
        body];
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
}

- (instancetype)initWithDelegate:(id<NSURLSessionDelegate>)delegate {
    if ((self = [super init])) {
        _real   = delegate;
        _bodies = [NSMutableDictionary dictionary];
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

// Accumulate body chunks
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data {
    NSNumber *tid = @(task.taskIdentifier);
    if (!_bodies[tid]) _bodies[tid] = [NSMutableData data];
    [_bodies[tid] appendData:data];
    // Forward to real delegate if it cares
    if ([_real respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)])
        [(id<NSURLSessionDataDelegate>)_real URLSession:session dataTask:task didReceiveData:data];
}

// Log completed request
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (!error) {
        NSNumber *tid = @(task.taskIdentifier);
        appendLine(buildEntry(task.currentRequest ?: task.originalRequest,
                              _bodies[tid], task.response));
        [_bodies removeObjectForKey:tid];
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
    void (^h)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        appendLine(buildEntry(request, d, r));
        if (completionHandler) completionHandler(d, r, e);
    };
    return %orig(request, h);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!isAppEnabled()) return %orig;
    void (^h)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        appendLine(buildEntry(req, d, r));
        if (completionHandler) completionHandler(d, r, e);
    };
    return %orig(url, h);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!isAppEnabled()) return %orig;
    void (^h)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        appendLine(buildEntry(request, d, r));
        if (completionHandler) completionHandler(d, r, e);
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

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";

    appendLine([NSString stringWithFormat:
        @"[%@] DIAGNOSTIC — %@\n  settingsFile: %@  masterSwitch: %@  selected: %@\n---",
        [df stringFromDate:[NSDate date]], bid,
        prefs ? @"found" : @"MISSING",
        masterOn ? @"ON" : @"OFF",
        thisApp ? @"YES" : @"NO"]);
}
