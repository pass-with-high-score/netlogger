#import "NLLogCell.h"

@implementation NLLogCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        _methodBadge = [[UILabel alloc] init];
        _methodBadge.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightBold];
        _methodBadge.textColor = [UIColor whiteColor];
        _methodBadge.textAlignment = NSTextAlignmentCenter;
        _methodBadge.layer.cornerRadius = 4;
        _methodBadge.clipsToBounds = YES;
        _methodBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_methodBadge];

        _statusBadge = [[UILabel alloc] init];
        _statusBadge.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightBold];
        _statusBadge.textAlignment = NSTextAlignmentCenter;
        _statusBadge.layer.cornerRadius = 4;
        _statusBadge.clipsToBounds = YES;
        _statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_statusBadge];

        _hostLabel = [[UILabel alloc] init];
        _hostLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _hostLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _hostLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self.contentView addSubview:_hostLabel];

        _pathLabel = [[UILabel alloc] init];
        _pathLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        _pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _pathLabel.textColor = [UIColor secondaryLabelColor];
        [self.contentView addSubview:_pathLabel];

        _metaLabel = [[UILabel alloc] init];
        _metaLabel.font = [UIFont systemFontOfSize:11];
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metaLabel.textColor = [UIColor tertiaryLabelColor];
        [self.contentView addSubview:_metaLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_methodBadge.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_methodBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_methodBadge.widthAnchor constraintGreaterThanOrEqualToConstant:40],
            [_methodBadge.heightAnchor constraintEqualToConstant:20],

            [_statusBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [_statusBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_statusBadge.widthAnchor constraintGreaterThanOrEqualToConstant:36],
            [_statusBadge.heightAnchor constraintEqualToConstant:20],

            [_hostLabel.leadingAnchor constraintEqualToAnchor:_methodBadge.trailingAnchor constant:8],
            [_hostLabel.centerYAnchor constraintEqualToAnchor:_methodBadge.centerYAnchor],
            [_hostLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusBadge.leadingAnchor constant:-8],

            [_pathLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_pathLabel.topAnchor constraintEqualToAnchor:_methodBadge.bottomAnchor constant:4],
            [_pathLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-36],

            [_metaLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_metaLabel.topAnchor constraintEqualToAnchor:_pathLabel.bottomAnchor constant:2],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-36],
            [_metaLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)configureWithEntry:(NLLogEntry *)entry {
    NSString *m = entry.method ?: @"?";
    self.methodBadge.text = [NSString stringWithFormat:@" %@ ", m];

    UIColor *methodColor;
    if ([m isEqualToString:@"GET"])         methodColor = [UIColor systemGreenColor];
    else if ([m isEqualToString:@"POST"])   methodColor = [UIColor systemBlueColor];
    else if ([m isEqualToString:@"PUT"])    methodColor = [UIColor systemOrangeColor];
    else if ([m isEqualToString:@"DELETE"]) methodColor = [UIColor systemRedColor];
    else if ([m isEqualToString:@"PATCH"])  methodColor = [UIColor systemPurpleColor];
    else if ([m isEqualToString:@"DIAGNOSTIC"]) methodColor = [UIColor systemTealColor];
    else methodColor = [UIColor systemGrayColor];
    self.methodBadge.backgroundColor = methodColor;

    NSInteger s = entry.status;
    self.statusBadge.text = (s > 0) ? [NSString stringWithFormat:@" %ld ", (long)s] : @" — ";

    UIColor *statusBg, *statusFg;
    if (s >= 200 && s < 300) {
        statusBg = [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
        statusFg = [UIColor systemGreenColor];
    } else if (s >= 300 && s < 400) {
        statusBg = [[UIColor systemOrangeColor] colorWithAlphaComponent:0.15];
        statusFg = [UIColor systemOrangeColor];
    } else if (s >= 400) {
        statusBg = [[UIColor systemRedColor] colorWithAlphaComponent:0.15];
        statusFg = [UIColor systemRedColor];
    } else {
        statusBg = [UIColor tertiarySystemFillColor];
        statusFg = [UIColor secondaryLabelColor];
    }
    self.statusBadge.backgroundColor = statusBg;
    self.statusBadge.textColor = statusFg;

    self.hostLabel.text = [entry hostFromURL];
    self.pathLabel.text = [entry pathFromURL];

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss";
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:entry.timestamp];
    NSString *durText = [entry durationText];
    self.metaLabel.text = [NSString stringWithFormat:@"%@  •  %@  •  %@", [df stringFromDate:d], entry.app ?: @"?", durText];
}

@end
