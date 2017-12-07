//
//  MGCDayColumnCell.m
//  Graphical Calendars Library for iOS
//
//  Distributed under the MIT License
//  Get the latest version from here:
//
//	https://github.com/jumartin/Calendar
//
//  Copyright (c) 2014-2015 Julien Martin
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#import "MGCDayColumnCell.h"
#import "NSCalendar+MGCAdditions.h"
#import "MGCAlignedGeometry.h"


static const CGFloat dotSize = 4;


@interface MGCDayColumnCell ()

@property (nonatomic) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic) CAShapeLayer *dotLayer;
@property (nonatomic) CALayer *leftBorder;
@property (nonatomic) CALayer *topBorder;
@property (nonatomic) CALayer *bottomBorder;


@property (nonatomic) UIView *coverViewMask;

@property (nonatomic) NSTimer *timer;
@property (nonatomic) NSUInteger rounding;
@end


@implementation MGCDayColumnCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        
        self.backgroundColor = [UIColor clearColor];
		_markColor = [UIColor blackColor];
		_dotColor = [UIColor blueColor];
        _separatorColor = [UIColor lightGrayColor];
		_headerHeight = 50;
        if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
            _coverViewMask = [[UIView alloc] initWithFrame:CGRectZero];
            _coverViewMask.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
            [self.contentView addSubview:_coverViewMask];
        }
		_dayLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_dayLabel.numberOfLines = 0;
		_dayLabel.adjustsFontSizeToFitWidth = YES;
		_dayLabel.minimumScaleFactor = .7;
		[self.contentView addSubview:_dayLabel];
        
		
		_dotLayer = [CAShapeLayer layer];
		CGPathRef dotPath = CGPathCreateWithEllipseInRect(CGRectMake(0, 0, dotSize, dotSize), NULL);
		_dotLayer.path = dotPath;
		_dotLayer.bounds = CGPathGetBoundingBox(dotPath);
		CGPathRelease(dotPath);
		_dotLayer.fillColor = _markColor.CGColor;
		_dotLayer.hidden = YES;
		[self.contentView.layer addSublayer:_dotLayer];
		
		_leftBorder = [CALayer layer];
		[self.contentView.layer addSublayer:_leftBorder];
        
        _calendar = [NSCalendar currentCalendar];
        _hourSlotHeight = 120;
        _insetsHeight = 24;
        _font = [UIFont boldSystemFontOfSize:10];
        _timeColor = [UIColor lightGrayColor];
        _currentTimeColor = [UIColor redColor];
        _rounding = 15;
        _hourRange = NSMakeRange(0, 24);
        
        self.showsCurrentTime = YES;
        if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
            _topBorder = [CALayer layer];
            [self.contentView.layer addSublayer:_topBorder];
            
            _bottomBorder = [CALayer layer];
            [self.contentView.layer addSublayer:_bottomBorder];
            
            _isShownCurrentTime = NO;
        }
        
        if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
            _btnDay = [[UIButton alloc] initWithFrame:CGRectZero];
            [_btnDay addTarget:self action:@selector(onTapDay) forControlEvents:UIControlEventTouchUpInside];
            [self.contentView addSubview:_btnDay];
            
        }
	}
    return self;
}
- (void)onTapDay{
    if ([self.dayColumndelegate respondsToSelector:@selector(didSelectedDay:)]) {
        [self.dayColumndelegate didSelectedDay:self];
    }
}
- (void)setActivityIndicatorVisible:(BOOL)visible
{
    if (!visible) {
        [self.activityIndicatorView stopAnimating];
    }
    else if (self.headerHeight > 0) {
        if (!self.activityIndicatorView) {
            self.activityIndicatorView = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            self.activityIndicatorView.color = [UIColor blackColor];
            self.activityIndicatorView.transform = CGAffineTransformMakeScale(0.6, 0.6);
            [self.contentView addSubview:self.activityIndicatorView];
        }
        [self.activityIndicatorView startAnimating];
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.accessoryTypes = MGCDayColumnCellAccessoryNone;
    self.markColor = [UIColor blackColor];
    [self setActivityIndicatorVisible:NO];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	
	static CGFloat kSpace = 2;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	if (self.headerHeight != 0) {
		CGSize headerSize = CGSizeMake(self.contentView.bounds.size.width, self.headerHeight);
		CGSize labelSize = CGSizeMake(headerSize.width - 2*kSpace, headerSize.height - (2 * dotSize + 2 * kSpace));
		self.dayLabel.frame = (CGRect) { 2, 5, labelSize };
		
		self.dotLayer.position = CGPointMake(self.contentView.center.x, headerSize.height - 1.2 * dotSize);
		self.dotLayer.fillColor = self.dotColor.CGColor;
		self.activityIndicatorView.center = CGPointMake(self.contentView.center.x, headerSize.height - 1.2 * dotSize);
		
		if (self.accessoryTypes & MGCDayColumnCellAccessoryMark) {
			self.dayLabel.layer.cornerRadius = 6;
			self.dayLabel.layer.backgroundColor = self.markColor.CGColor;
		}
		else  {
			self.dayLabel.layer.cornerRadius = 0;
			self.dayLabel.layer.backgroundColor = [UIColor clearColor].CGColor;
		}
        
	}
	
	self.dotLayer.hidden = !(self.accessoryTypes & MGCDayColumnCellAccessoryDot) || self.headerHeight == 0;
	self.dayLabel.hidden = (self.headerHeight == 0);

    // border
    CGRect borderFrame = CGRectZero;
    if (self.accessoryTypes & MGCDayColumnCellAccessoryBorder) {
        borderFrame = CGRectMake(0, self.headerHeight, 1./[UIScreen mainScreen].scale, self.contentView.bounds.size.height-self.headerHeight);
        
    }
    else if (self.accessoryTypes & MGCDayColumnCellAccessorySeparator) {
        borderFrame = CGRectMake(0, 0, 2./[UIScreen mainScreen].scale, self.contentView.bounds.size.height);
    }
    
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        borderFrame = CGRectMake(0, self.headerHeight + 25, self.contentView.bounds.size.width,1./[UIScreen mainScreen].scale);
    } else if([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        
    }
    
    self.leftBorder.frame = borderFrame;
    self.leftBorder.borderColor = self.separatorColor.CGColor;
    self.leftBorder.borderWidth = borderFrame.size.width / 2.;

	[CATransaction commit];
    
    if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        CGRect borderFrameTopBottom = CGRectZero;
        borderFrameTopBottom = CGRectMake(0, self.headerHeight + self.insetsHeight + 25, self.contentView.bounds.size.width,1./[UIScreen mainScreen].scale);
        
        self.topBorder.frame = borderFrameTopBottom;
        self.topBorder.borderColor = self.separatorColor.CGColor;
        self.topBorder.borderWidth = borderFrameTopBottom.size.width / 2.;
        
        borderFrameTopBottom = CGRectMake(0, self.headerHeight + self.insetsHeight + 65, self.contentView.bounds.size.width,1./[UIScreen mainScreen].scale);
        self.bottomBorder.frame = borderFrameTopBottom;
        self.bottomBorder.borderColor = self.separatorColor.CGColor;
        self.bottomBorder.borderWidth = borderFrameTopBottom.size.width / 2.;
        
        
        self.coverViewMask.frame = CGRectMake(0, 0, self.contentView.bounds.size.width, self.headerHeight);
        self.btnDay.frame = CGRectMake(0, 0, self.contentView.bounds.size.width, self.headerHeight);
        [self setNeedsDisplay];
    }
}

- (void)setAccessoryTypes:(MGCDayColumnCellAccessoryType)accessoryTypes
{
    _accessoryTypes = accessoryTypes;
    [self setNeedsLayout];
}
- (void)drawRect:(CGRect)rect
{
    if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        self.hourSlotHeight = self.contentView.bounds.size.width/self.hourRange.length;
        
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGFloat lineWidth = 1. / [UIScreen mainScreen].scale;
        CGFloat cellWidth = self.contentView.bounds.size.width/4;
        
        CGSize markSizeMax = CGSizeMake(32, CGFLOAT_MAX);

        // calculate rect for current time mark
        NSDateComponents *comps = [self.calendar components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:[NSDate date]];
        NSTimeInterval currentTime = comps.hour*3600.+comps.minute*60.+comps.second;

        NSAttributedString *markAttrStr = [self attributedStringForTimeMark:MGCDayPlannerTimeMarkCurrent time:currentTime];
        CGSize markSize = [markAttrStr boundingRectWithSize:markSizeMax options:NSStringDrawingUsesLineFragmentOrigin context:nil].size;

        CGFloat y = [self yOffsetForTime:currentTime rounded:NO];
        CGRect rectCurTime = CGRectZero;

        // draw current time mark
        rectCurTime =  CGRectMake(y - markSize.width/2., self.headerHeight + self.insetsHeight + 4, markSizeMax.width, markSize.height);

        if (self.isShownCurrentTime) {
            [markAttrStr drawInRect:rectCurTime];
            CGRect lineRect = CGRectMake(y, self.headerHeight + self.insetsHeight + 23, 1, rect.size.height-23);
            
            CGContextSetFillColorWithColor(context, self.currentTimeColor.CGColor);
            UIRectFill(lineRect);
        }

        // calculate rect for the floating time mark
        NSAttributedString *floatingMarkAttrStr = [self attributedStringForTimeMark:MGCDayPlannerTimeMarkFloating time:self.timeMark];
        markSize = [floatingMarkAttrStr boundingRectWithSize:markSizeMax options:NSStringDrawingUsesLineFragmentOrigin context:nil].size;

        y = [self yOffsetForTime:self.timeMark rounded:YES];
        
        NSInteger countToTimeLine = 6;//([UIScreen mainScreen].bounds.size.width - 200.0f)/self.contentView.bounds.size.width;
        
        // draw the hour marks
        NSUInteger j = 0;
        for (NSUInteger i = self.hourRange.location; i <=  NSMaxRange(self.hourRange); i++) {
            if (i%countToTimeLine == 0 && i != 0 && i != 24) {
                j ++;
                CGFloat diffHeight = 0;
                if (j % 2 == 0) {
                    diffHeight = 12;
                }else{
                    diffHeight = 0;
                }
                markAttrStr = [self attributedStringForTimeMark:MGCDayPlannerTimeMarkHeader time:(i % 24)*3600];
                markSize = [markAttrStr boundingRectWithSize:markSizeMax options:NSStringDrawingUsesLineFragmentOrigin context:nil].size;
                
                y = MGCAlignedFloat(i * self.hourSlotHeight);
                CGRect r = MGCAlignedRectMake(y - markSize.width / 2., self.headerHeight + self.insetsHeight + 13-diffHeight, markSizeMax.width, markSize.height);
                
                if (!CGRectIntersectsRect(r, rectCurTime) || !self.showsCurrentTime || !self.isShownCurrentTime) {
                    [markAttrStr drawInRect:r];
                }
                
                CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0.85 green:0.85 blue:0.85 alpha:1.0].CGColor);
                CGContextSetLineWidth(context, lineWidth);
                CGContextSetLineDash(context, 0, NULL, 0);
                CGContextMoveToPoint(context, y, self.headerHeight + self.insetsHeight + 26-diffHeight);
                CGContextAddLineToPoint(context, y, rect.size.height);
                CGContextStrokePath(context);
                
            }
        }
    }
    
}
// time is the interval since the start of the day.
// result can be negative if hour range doesn't start at 0
- (CGFloat)yOffsetForTime:(NSTimeInterval)time rounded:(BOOL)rounded
{
    if (rounded) {
        time = roundf(time / (self.rounding * 60)) * (self.rounding * 60);
    }
    return (time / 3600. - self.hourRange.location) * self.hourSlotHeight;
}

// time is the interval since the start of the day
- (NSString*)stringForTime:(NSTimeInterval)time rounded:(BOOL)rounded minutesOnly:(BOOL)minutesOnly
{
    if (rounded) {
        time = roundf(time / (self.rounding * 60)) * (self.rounding * 60);
    }
    
    int hour = (int)(time / 3600) % 24;
    int minutes = ((int)time % 3600) / 60;
    
    if (minutesOnly) {
        return [NSString stringWithFormat:@":%02d", minutes];
    }
    return [NSString stringWithFormat:@"%02d:%02d", hour, minutes];
}

- (NSAttributedString*)attributedStringForTimeMark:(MGCDayPlannerTimeMark)mark time:(NSTimeInterval)ti
{
    NSAttributedString *attrStr = nil;
    
        BOOL rounded = (mark != MGCDayPlannerTimeMarkCurrent);
        BOOL minutesOnly = (mark == MGCDayPlannerTimeMarkFloating);
        
        NSString *str = [self stringForTime:ti rounded:rounded minutesOnly:minutesOnly];
        
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.alignment = NSTextAlignmentRight;
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
            style.alignment = NSTextAlignmentCenter;
        }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
            
        }
        
        UIColor *foregroundColor = (mark == MGCDayPlannerTimeMarkCurrent ? self.currentTimeColor : self.timeColor);
        attrStr = [[NSAttributedString alloc]initWithString:str attributes:@{ NSFontAttributeName: self.font, NSForegroundColorAttributeName: foregroundColor, NSParagraphStyleAttributeName: style }];
    
    return attrStr;
}

- (BOOL)canDisplayTime:(NSTimeInterval)ti
{
    CGFloat hour = ti/3600.;
    return hour >= self.hourRange.location && hour <= NSMaxRange(self.hourRange);
}
@end
