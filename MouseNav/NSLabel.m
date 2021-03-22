
#import "NSLabel.h"

@implementation NSLabel

- (instancetype)init {
	return [self initWithFrame:NSZeroRect];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
	if ((self = [super initWithFrame:frameRect])) {
    self.bezeled = NO;
    self.drawsBackground = NO;
    self.editable = NO;
    self.selectable = NO;
    self.preferredMaxLayoutWidth = 1024.0;
	}
	return self;
}

@end
