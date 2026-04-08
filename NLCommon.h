#import <Foundation/Foundation.h>

extern BOOL isAppEnabled(void);
extern BOOL isNoCachingEnabled(void);
extern NSData *applyMitmRules(NSData *responseData, NSURLRequest *request);
extern NSString *buildEntry(NSURLRequest *request, NSData *data, NSURLResponse *response, double durationMs);
extern void appendLine(NSString *line);
