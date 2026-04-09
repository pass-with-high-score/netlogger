#import <UIKit/UIKit.h>
#import "NLLogEntry.h"

@interface NLLogCell : UITableViewCell
@property (nonatomic, strong) UILabel *methodBadge;
@property (nonatomic, strong) UILabel *statusBadge;
@property (nonatomic, strong) UILabel *hostLabel;
@property (nonatomic, strong) UILabel *pathLabel;
@property (nonatomic, strong) UILabel *metaLabel;
- (void)configureWithEntry:(NLLogEntry *)entry;
@end
