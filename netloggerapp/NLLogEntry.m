#import "NLLogEntry.h"

@implementation NLLogEntry

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    if (self = [super init]) {
        _guid = dict[@"id"];
        _timestamp = [dict[@"timestamp"] doubleValue];
        _method = dict[@"method"];
        _url = dict[@"url"];
        _status = [dict[@"status"] integerValue];
        _app = dict[@"app"];
        _durationMs = [dict[@"duration_ms"] doubleValue];
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

- (NSString *)durationText {
    if (self.durationMs <= 0) return @"—";
    if (self.durationMs < 1000) return [NSString stringWithFormat:@"%.0f ms", self.durationMs];
    return [NSString stringWithFormat:@"%.2f s", self.durationMs / 1000.0];
}

- (NSString *)toCurlCommand {
    NSMutableString *curl = [NSMutableString stringWithFormat:@"curl -X %@ '%@'", self.method ?: @"GET", self.url ?: @""];
    
    for (NSString *key in self.reqHeaders) {
        NSString *val = [NSString stringWithFormat:@"%@", self.reqHeaders[key]];
        val = [val stringByReplacingOccurrencesOfString:@"'" withString:@"'\\'"];
        [curl appendFormat:@" \\ \n  -H '%@: %@'", key, val];
    }
    
    if (self.reqBodyBase64.length > 0) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:self.reqBodyBase64 options:0];
        if (data) {
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (body) {
                body = [body stringByReplacingOccurrencesOfString:@"'" withString:@"'\\'"];
                [curl appendFormat:@" \\ \n  --data '%@'", body];
            }
        }
    }
    
    return curl;
}

@end
