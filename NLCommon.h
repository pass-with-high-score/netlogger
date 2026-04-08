#import <Foundation/Foundation.h>

extern BOOL isAppEnabled(void);
extern BOOL isNoCachingEnabled(void);
extern BOOL isSocketCaptureEnabled(void);
extern NSData *applyMitmRules(NSData *responseData, NSURLRequest *request);
extern NSMutableURLRequest *applyMitmRequestRules(NSMutableURLRequest *request);
extern NSURLResponse *applyMitmResponseRules(NSURLResponse *response, NSURLRequest *request);
extern NSString *buildEntry(NSURLRequest *request, NSData *data, NSURLResponse *response, double durationMs);
extern void appendLine(NSString *line);
