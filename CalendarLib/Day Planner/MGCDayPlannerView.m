//
//  MGCDayPlannerView.m
//  Graphical Calendars Library for iOS
//
//  Distributed under the MIT License
//  Get the latest version from here:
//
//    https://github.com/jumartin/Calendar
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

#import "MGCDayPlannerView.h"
#import "NSCalendar+MGCAdditions.h"
#import "MGCDateRange.h"
#import "MGCReusableObjectQueue.h"
#import "MGCTimedEventsViewLayout.h"
#import "MGCTimedEventsMeViewLayout.h"
#import "MGCAllDayEventsViewLayout.h"
#import "MGCDayColumnCell.h"
#import "MGCEventCell.h"
#import "MGCEventView.h"
#import "MGCStandardEventView.h"
#import "MGCInteractiveEventView.h"
#import "MGCTimeRowsView.h"
#import "MGCTimeColumnsView.h"
#import "MGCAlignedGeometry.h"
#import "OSCache.h"


// used to restrict scrolling to one direction / axis
typedef enum: NSUInteger
{
    ScrollDirectionUnknown = 0,
    ScrollDirectionLeft = 1 << 0,
    ScrollDirectionUp = 1 << 1,
    ScrollDirectionRight = 1 << 2,
    ScrollDirectionDown = 1 << 3,
    ScrollDirectionHorizontal = (ScrollDirectionLeft | ScrollDirectionRight),
    ScrollDirectionVertical = (ScrollDirectionUp | ScrollDirectionDown)
} ScrollDirection;


// collection views cell identifiers
static NSString* const EventCellReuseIdentifier = @"EventCellReuseIdentifier";
static NSString* const DimmingViewReuseIdentifier = @"DimmingViewReuseIdentifier";
static NSString* const DimmingViewMeReuseIdentifier = @"DimmingViewMeReuseIdentifier";
static NSString* const DayColumnCellReuseIdentifier = @"DayColumnCellReuseIdentifier";
static NSString* const TimeRowCellReuseIdentifier = @"TimeRowCellReuseIdentifier";
static NSString* const MoreEventsViewReuseIdentifier = @"MoreEventsViewReuseIdentifier";   // test


// we only load in the collection views (2 * kDaysLoadingStep + 1) pages of (numberOfVisibleDays) days each at a time.
// this value can be tweaked for performance or smoother scrolling (between 2 and 4 seems reasonable)
static const NSUInteger kDaysLoadingStep = 2;

// minimum and maximum height of a one-hour time slot
static const CGFloat kMinHourSlotHeight = 10.;
static const CGFloat kMaxHourSlotHeight = 150.;


@interface MGCDayColumnViewFlowLayout : UICollectionViewFlowLayout
@end

@implementation MGCDayColumnViewFlowLayout

- (UICollectionViewLayoutInvalidationContext *)invalidationContextForBoundsChange:(CGRect)newBounds {
    
    UICollectionViewFlowLayoutInvalidationContext *context = (UICollectionViewFlowLayoutInvalidationContext *)[super invalidationContextForBoundsChange:newBounds];
    CGRect oldBounds = self.collectionView.bounds;
    context.invalidateFlowLayoutDelegateMetrics = !CGSizeEqualToSize(newBounds.size, oldBounds.size);
    return context;
}

// we keep this for iOS 8 compatibility. As of iOS 9, this is replaced by collectionView:targetContentOffsetForProposedContentOffset:
- (CGPoint)targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset
{
    id<UICollectionViewDelegate> delegate = (id<UICollectionViewDelegate>)self.collectionView.delegate;
    return [delegate collectionView:self.collectionView targetContentOffsetForProposedContentOffset:proposedContentOffset];
}


@end


@interface MGCDayPlannerView () <UICollectionViewDataSource, MGCTimedEventsViewLayoutDelegate, MGCAllDayEventsViewLayoutDelegate, UICollectionViewDelegateFlowLayout, MGCTimeRowsViewDelegate, UIGestureRecognizerDelegate, MGCTimedEventsMeViewLayoutDelegate, MGCDayColumnCellDelegate>

// subviews
@property (nonatomic, readonly) UICollectionView *timedEventsView;
@property (nonatomic, readonly) UIView *maskViewForHideMeOnTimedEventsView;
@property (nonatomic, readonly) UICollectionView *timedEventsMeView;
@property (nonatomic, readonly) UICollectionView *allDayEventsView;
@property (nonatomic, readonly) UIView *allDayEventsBackgroundView;
@property (nonatomic, readonly) UICollectionView *dayColumnsView;
@property (nonatomic, readonly) UIScrollView *timeScrollView;
@property (nonatomic, readonly) MGCTimeRowsView *timeRowsView;

@property (nonatomic, readonly) UIScrollView *timeHorizontalScrollView;
@property (nonatomic, readonly) MGCTimeColumnsView *timeColumnsView;


@property (nonatomic, readonly) UIView *timeLabelCV;
@property (nonatomic, readonly) UIView *viewToGetDateOfDayColumnView;

// collection view layouts
@property (nonatomic, readonly) MGCTimedEventsViewLayout *timedEventsViewLayout;
@property (nonatomic, readonly) MGCAllDayEventsViewLayout *allDayEventsViewLayout;
@property (nonatomic, readonly) MGCTimedEventsMeViewLayout *timedEventsMeViewLayout;

@property (nonatomic) MGCReusableObjectQueue *reuseQueue;        // reuse queue for event views (MGCEventView)

@property (nonatomic, copy) NSDate *currentSelectedDate;
@property (nonatomic, copy) NSDate *startDate;                    // first currently loaded day in the collection views (might not be visible)
@property (nonatomic, readonly) NSDate *maxStartDate;            // maximum date for the start of a loaded page of the collection view - set with dateRange, nil for infinite scrolling
@property (nonatomic, readonly) NSUInteger numberOfLoadedDays;    // number of days loaded at once in the collection views
@property (nonatomic, readonly) MGCDateRange* loadedDaysRange;    // date range of all days currently loaded in the collection views
@property (nonatomic) MGCDateRange* previousVisibleDays;        // used by updateVisibleDaysRange to inform delegate about appearing / disappearing days

@property (nonatomic) NSMutableOrderedSet *loadingDays;            // set of dates with running activity indicator

@property (nonatomic, readonly) NSDate *firstVisibleDate;        // first fully visible day (!= visibleDays.start)

@property (nonatomic) CGFloat allDayEventCellHeight;            // height of an event cell in the all-day event view
@property (nonatomic) CGFloat eventsViewInnerMargin;            // distance between top and first time line and between last line and bottom

@property (nonatomic) CGFloat zoomScaleWithPich;
@property (nonatomic) BOOL isZoomingIn;

@property (nonatomic) UIScrollView *controllingScrollView;        // the collection view which initiated scrolling - used for proper synchronization between the different collection views
@property (nonatomic) CGPoint scrollStartOffset;                // content offset in the controllingScrollView where scrolling started - used to lock scrolling in one direction
@property (nonatomic) ScrollDirection scrollDirection;            // direction or axis of the scroll movement
@property (nonatomic) NSDate *scrollTargetDate;                 // target date after scrolling (initiated programmatically or following pan or swipe gesture)

@property (nonatomic) MGCInteractiveEventView *interactiveCell;    // view used when dragging event around
@property (nonatomic) CGPoint interactiveCellTouchPoint;        // point where touch occured in interactiveCell coordinates
@property (nonatomic) MGCEventType interactiveCellType;            // current type of interactive cell
@property (nonatomic, copy) NSDate *interactiveCellDate;        // current date of interactice cell
@property (nonatomic) CGFloat interactiveCellTimedEventHeight;    // height of the dragged event
@property (nonatomic) BOOL isInteractiveCellForNewEvent;        // is the interactive cell for new event or existing one

@property (nonatomic) MGCEventType movingEventType;                // origin type of the event being moved
@property (nonatomic) NSUInteger movingEventIndex;                // origin index of the event being moved
@property (nonatomic, copy) NSDate *movingEventDate;            // origin date of the event being moved
@property (nonatomic) BOOL acceptsTarget;                        // are the current date and type accepted for new event or existing one

@property (nonatomic, assign) NSTimer *dragTimer;                // timer used when scrolling while dragging

@property (nonatomic, copy) NSIndexPath *selectedCellIndexPath; // index path of the currently selected event cell
@property (nonatomic) MGCEventType selectedCellType;            // type of the currently selected event

@property (nonatomic) CGFloat hourSlotHeightForGesture;
@property (copy, nonatomic) dispatch_block_t scrollViewAnimationCompletionBlock;

@property (nonatomic) OSCache *dimmedTimeRangesCache;          // cache for dimmed time ranges (indexed by date)

@property (nonatomic) BOOL isTouchFirstTimedEvents;
@property (nonatomic) BOOL performFromGestureScrolling;

@property (nonatomic) BOOL isSelectedNextPrewBtn;
@property (nonatomic) BOOL isScrolledPreDateWithScrolling;


@end


@implementation MGCDayPlannerView

// readonly properties whose getter's defined are not auto-synthesized
@synthesize timedEventsView = _timedEventsView;
@synthesize timedEventsMeView = _timedEventsMeView;
@synthesize allDayEventsView = _allDayEventsView;
@synthesize dayColumnsView = _dayColumnsView;
//@synthesize backgroundView = _backgroundView;
@synthesize timeScrollView = _timeScrollView;
@synthesize allDayEventsBackgroundView = _allDayEventsBackgroundView;
@synthesize timedEventsViewLayout = _timedEventsViewLayout;
@synthesize timedEventsMeViewLayout = _timedEventsMeViewLayout;
@synthesize allDayEventsViewLayout = _allDayEventsViewLayout;
@synthesize startDate = _startDate;
@synthesize timeHorizontalScrollView = _timeHorizontalScrollView;
@synthesize timeLabelCV = _timeLabelCV;
@synthesize maskViewForHideMeOnTimedEventsView = _maskViewForHideMeOnTimedEventsView;
@synthesize viewToGetDateOfDayColumnView = _viewToGetDateOfDayColumnView;

#pragma mark - Initialization

- (void)setup
{
    _numberOfVisibleDays = 7;
    _hourSlotHeight = 65.;
    _hourRange = NSMakeRange(0, 24);
    _dayHeaderHeight = 40.;
    _timeColumnWidth = 60.;
    _daySeparatorsColor = [UIColor lightGrayColor];
    _timeSeparatorsColor = [UIColor lightGrayColor];
    _currentTimeColor = [UIColor redColor];
    _eventIndicatorDotColor = [UIColor blueColor];
    _showsAllDayEvents = YES;
    _eventsViewInnerMargin = 20.;
    _allDayEventCellHeight = 20;
    _dimmingColor = [UIColor colorWithWhite:.9 alpha:.5];
    _pagingEnabled = YES;
    _zoomingEnabled = YES;
    _canCreateEvents = YES;
    _canMoveEvents = YES;
    _allowsSelection = YES;
    _eventCoveringType = TimedEventCoveringTypeClassic;
    _isTouchFirstTimedEvents = NO;
    _reuseQueue = [[MGCReusableObjectQueue alloc] init];
    _loadingDays = [NSMutableOrderedSet orderedSetWithCapacity:14];
    
    _dimmedTimeRangesCache = [[OSCache alloc]init];
    _dimmedTimeRangesCache.countLimit = 200;
    
    _durationForNewTimedEvent = 60 * 60;
    
    _zoomScaleWithPich = 0;
    _isZoomingIn = NO;
    
    _isSelectedNextPrewBtn = NO;
    _isScrolledPreDateWithScrolling = NO;

    
    self.backgroundColor = [UIColor whiteColor];
    self.autoresizesSubviews = NO;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillChangeStatusBarOrientation:) name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
    
    
    if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        _hourSlotHeight = ([UIScreen mainScreen].bounds.size.width-200) / (_numberOfVisibleDays * NSMaxRange(self.hourRange));
    }
    
}

- (id)initWithCoder:(NSCoder*)coder
{
    if (self = [super initWithCoder:coder]) {
        [self setup];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self setup];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];  // for UIApplicationDidReceiveMemoryWarningNotification
}
- (void)applicationDidReceiveMemoryWarning:(NSNotification*)notification
{
    [self reloadAllEvents];
}

- (void)applicationWillChangeStatusBarOrientation:(NSNotification*)notification
{
    [self endInteraction];
    
    if ([self.delegate respondsToSelector:@selector(dayPlannerViewDidZoom:)]) {
        [self.delegate dayPlannerViewDidZoom:self];
    }
    
    // cancel eventual pan gestures
    self.timedEventsView.panGestureRecognizer.enabled = NO;
    self.timedEventsView.panGestureRecognizer.enabled = YES;
    
    self.allDayEventsView.panGestureRecognizer.enabled = NO;
    self.allDayEventsView.panGestureRecognizer.enabled = YES;
    
    self.timedEventsMeView.panGestureRecognizer.enabled = NO;
    self.timedEventsMeView.panGestureRecognizer.enabled = YES;
}

#pragma mark - Layout

// public
- (void)setNumberOfVisibleDays:(NSUInteger)numberOfVisibleDays
{
    NSAssert(numberOfVisibleDays > 0, @"numberOfVisibleDays in day planner view cannot be set to 0");
    
    if (_numberOfVisibleDays != numberOfVisibleDays) {
        NSDate* date = self.visibleDays.start;
        
        _numberOfVisibleDays = numberOfVisibleDays;
        
        if (self.dateRange && [self.dateRange components:NSCalendarUnitDay forCalendar:self.calendar].day < numberOfVisibleDays)
            return;
        
        [self reloadCollectionViews];
        [self scrollToDate:date options:MGCDayPlannerScrollDate animated:NO  fromTap:NO];
    }
}
- (void)reloadTimeSlotsWithOrienteNotification{
    self.hourSlotHeight = self.hourSlotHeight;
    [self setupSubviews];
}
// public
- (void)setHourSlotHeight:(CGFloat)hourSlotHeight
{
    CGFloat yCenterOffset = self.timeScrollView.contentOffset.y + self.timeScrollView.bounds.size.height / 2.;
    NSTimeInterval ti = [self timeFromOffset:yCenterOffset rounding:0];
    
    CGFloat xCenterOffset = self.timeScrollView.contentOffset.x + self.timeScrollView.bounds.size.width / 2.;
    NSTimeInterval tiDay = [self timeFromOffset:xCenterOffset rounding:0];
    
    CGFloat minHourSlotWidthForDay = (self.bounds.size.width - 2*self.eventsViewInnerMargin)/self.hourRange.length;
    
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        _hourSlotHeight = fminf(fmaxf(MGCAlignedFloat(hourSlotHeight), minHourSlotWidthForDay), kMaxHourSlotHeight);
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        NSUInteger numberOfDays = MIN(self.numberOfVisibleDays, self.numberOfLoadedDays);
        _hourSlotHeight = ([UIScreen mainScreen].bounds.size.width-200) / (numberOfDays * NSMaxRange(self.hourRange));
    }else{
    }
    
    [self.dayColumnsView.collectionViewLayout invalidateLayout];
    
    self.timedEventsViewLayout.dayColumnSize = self.dayColumnSize;
    [self.timedEventsViewLayout invalidateLayout];
    
    CGSize dayColumnSizeMe = CGSizeMake(self.dayColumnSize.width, 40.0f);
    self.timedEventsMeViewLayout.dayColumnSize = dayColumnSizeMe;
    [self.timedEventsMeViewLayout invalidateLayout];
    
    self.timeRowsView.hourSlotHeight = _hourSlotHeight;
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        self.timeScrollView.contentSize = CGSizeMake(self.dayColumnSize.width, self.bounds.size.height - self.dayHeaderHeight);
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        self.timeScrollView.contentSize = CGSizeMake(self.bounds.size.width, self.dayColumnSize.height);
    }else{
        self.timeScrollView.contentSize = CGSizeMake(self.bounds.size.width, self.dayColumnSize.height);
    }
    self.timeRowsView.frame = CGRectMake(0, 0, self.timeScrollView.contentSize.width, self.timeScrollView.contentSize.height);
    
    CGFloat yOffset = [self offsetFromTime:ti rounding:0] - self.timeScrollView.bounds.size.height / 2.;
    yOffset = fmaxf(0, fminf(yOffset, self.timeScrollView.contentSize.height - self.timeScrollView.bounds.size.height));
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        CGFloat xOffset = [self offsetFromTime:tiDay rounding:0] - self.timeScrollView.bounds.size.width / 2.;
        xOffset = fmaxf(0, fminf(xOffset, self.timeScrollView.contentSize.width - self.timeScrollView.bounds.size.width));
        self.timeScrollView.contentOffset = CGPointMake(xOffset, 0);
        NSUInteger section = [self dayOffsetFromDate:self.currentSelectedDate];
        CGPoint ptDayColumnsView = [self convertPoint:CGPointMake(xOffset, 0) toView:self.timedEventsView];
        self.timedEventsView.contentOffset = CGPointMake(section*self.dayColumnSize.width + xOffset, self.timedEventsView.contentOffset.y);
        self.timedEventsMeView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, 0);
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        self.timeScrollView.contentOffset = CGPointMake(0, yOffset);
        self.timedEventsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, yOffset);
    }else{
        self.timeScrollView.contentOffset = CGPointMake(0, yOffset);
        self.timedEventsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, yOffset);
    }
}

// public
- (CGSize)dayColumnSize
{
    CGFloat height = self.hourSlotHeight * self.hourRange.length + 2 * self.eventsViewInnerMargin;
    
    // if the number of days in dateRange is less than numberOfVisibleDays, spread the days over the view
    NSUInteger numberOfDays = MIN(self.numberOfVisibleDays, self.numberOfLoadedDays);
    CGFloat width = (self.bounds.size.width - self.timeColumnWidth) / numberOfDays;
    
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        width = self.hourSlotHeight * self.hourRange.length + 2 * self.eventsViewInnerMargin;
        height =self.bounds.size.height-self.dayHeaderHeight-25;
        if (self.heightOfScrollViewFromResources>height) {
            height = self.heightOfScrollViewFromResources;
        }
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        width = self.bounds.size.width / numberOfDays;
        height =self.bounds.size.height-self.dayHeaderHeight-50;
        if (self.heightOfScrollViewFromResources>height) {
            height = self.heightOfScrollViewFromResources;
        }
    }
    return MGCAlignedSizeMake(width, height);
}

// public
- (void)setShowsAllDayEvents:(BOOL)showsAllDayEvents
{
    if (_showsAllDayEvents != showsAllDayEvents) {
        _showsAllDayEvents = showsAllDayEvents;
        
        [self.allDayEventsView reloadData];
        [self.dayColumnsView reloadData];   // for dots indicating events
        
        [self.dayColumnsView performBatchUpdates:^{} completion:^(BOOL finished){
            [self setupSubviews];
        }];
    }
}

// public
- (NSCalendar*)calendar
{
    if (_calendar == nil) {
        _calendar = [NSCalendar currentCalendar];
    }
    return _calendar;
}

// public
- (void)setDateRange:(MGCDateRange*)dateRange
{
    if (dateRange != _dateRange && ![dateRange isEqual:_dateRange]) {
        NSDate *firstDate = self.visibleDays.start;
        
        _dateRange = nil;
        
        if (dateRange) {
            
            // adjust start and end date of new range on day boundaries
            NSDate *start = [self.calendar mgc_startOfDayForDate:dateRange.start];
            NSDate *end = [self.calendar mgc_startOfDayForDate:dateRange.end];
            _dateRange = [MGCDateRange dateRangeWithStart:start end:end];
            
            // adjust startDate so that it falls inside new range
            if (![_dateRange includesDateRange:self.loadedDaysRange]) {
                self.startDate = _dateRange.start;
            }
            
            if (![_dateRange containsDate:firstDate]) {
                firstDate = [NSDate date];
                if (![_dateRange containsDate:firstDate]) {
                    firstDate = _dateRange.start;
                }
            }
        }
        
        [self reloadCollectionViews];
        [self scrollToDate:firstDate options:MGCDayPlannerScrollDate animated:NO  fromTap:NO];
    }
}

// public
- (MGCDateRange*)visibleDays
{
    CGFloat dayWidth = self.dayColumnSize.width;
    
    NSUInteger first = floorf(self.timedEventsView.contentOffset.x / dayWidth);
    NSDate *firstDay = [self dateFromDayOffset:first];
    if (self.dateRange && [firstDay compare:self.dateRange.start] == NSOrderedAscending)
        firstDay = self.dateRange.start;
    
    // since the day column width is rounded, there can be a difference of a few points between
    // the right side of the view bounds and the limit of the last column, causing last visible day
    // to be one more than expected. We have to take this in account
    CGFloat diff = self.timedEventsView.bounds.size.width - self.dayColumnSize.width * self.numberOfVisibleDays;
    
    NSUInteger last = ceilf((CGRectGetMaxX(self.timedEventsView.bounds) - diff) / dayWidth);
    NSDate *lastDay = [self dateFromDayOffset:last];
    if (self.dateRange && [lastDay compare:self.dateRange.end] != NSOrderedAscending)
        lastDay = self.dateRange.end;
    
    return [MGCDateRange dateRangeWithStart:firstDay end:lastDay];
}

// public
- (NSTimeInterval)firstVisibleTime
{
    NSTimeInterval ti = [self timeFromOffset:self.timedEventsView.contentOffset.y rounding:0];
    return fmax(self.hourRange.location * 3600., ti);
}

// public
- (NSTimeInterval)lastVisibleTime
{
    NSTimeInterval ti = [self timeFromOffset:CGRectGetMaxY(self.timedEventsView.bounds) rounding:0];
    return fmin(NSMaxRange(self.hourRange) * 3600., ti);
}

// public
- (void)setHourRange:(NSRange)hourRange
{
    NSAssert(hourRange.length >= 1 && NSMaxRange(hourRange) <= 24, @"Invalid hour range %@", NSStringFromRange(hourRange));
    
    CGFloat yCenterOffset = self.timeScrollView.contentOffset.y + self.timeScrollView.bounds.size.height / 2.;
    NSTimeInterval ti = [self timeFromOffset:yCenterOffset rounding:0];
    
    _hourRange = hourRange;
    
    [self.dimmedTimeRangesCache removeAllObjects];
    
    self.timedEventsViewLayout.dayColumnSize = self.dayColumnSize;
    [self.timedEventsViewLayout invalidateLayout];
    
    CGSize dayColumnSizeMe = CGSizeMake(self.dayColumnSize.width, 40.0f);
    self.timedEventsMeViewLayout.dayColumnSize = dayColumnSizeMe;
    [self.timedEventsMeViewLayout invalidateLayout];
    
    self.timeRowsView.hourRange = hourRange;
    self.timeScrollView.contentSize = CGSizeMake(self.bounds.size.width, self.dayColumnSize.height);
    self.timeRowsView.frame = CGRectMake(0, 0, self.timeScrollView.contentSize.width, self.timeScrollView.contentSize.height);
    
    CGFloat yOffset = [self offsetFromTime:ti rounding:0] - self.timeScrollView.bounds.size.height / 2.;
    yOffset = fmaxf(0, fminf(yOffset, self.timeScrollView.contentSize.height - self.timeScrollView.bounds.size.height));
    
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        self.timeScrollView.contentOffset = CGPointMake(yOffset, 0 );
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        self.timeScrollView.contentOffset = CGPointMake(0, yOffset);
    }else{
        self.timeScrollView.contentOffset = CGPointMake(0, yOffset);
    }
    self.timedEventsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, yOffset);
    self.timedEventsMeView.contentOffset = CGPointMake(self.timedEventsMeView.contentOffset.x, 0);
}

// public
- (void)setDateFormat:(NSString*)dateFormat
{
    if (dateFormat != _dateFormat || ![dateFormat isEqualToString:_dateFormat]) {
        _dateFormat = [dateFormat copy];
        [self.dayColumnsView reloadData];
    }
}

// public
- (void)setDaySeparatorsColor:(UIColor *)daySeparatorsColor
{
    _daySeparatorsColor = daySeparatorsColor;
    [self.dayColumnsView reloadData];
}

// public
- (void)setTimeSeparatorsColor:(UIColor *)timeSeparatorsColor
{
    _timeSeparatorsColor = timeSeparatorsColor;
    self.timeRowsView.timeColor = timeSeparatorsColor;
    [self.timeRowsView setNeedsDisplay];
}

// public
- (void)setCurrentTimeColor:(UIColor *)currentTimeColor
{
    _currentTimeColor = currentTimeColor;
    self.timeRowsView.currentTimeColor = currentTimeColor;
    [self.timeRowsView setNeedsDisplay];
}

// public
- (void)setEventIndicatorDotColor:(UIColor *)eventIndicatorDotColor
{
    _eventIndicatorDotColor = eventIndicatorDotColor;
    [self.dayColumnsView reloadData];
}

// public
- (void)setDimmingColor:(UIColor *)dimmingColor
{
    _dimmingColor = dimmingColor;
    for (UIView *v in [self.timedEventsView visibleSupplementaryViewsOfKind:DimmingViewKind]) {
        v.backgroundColor = dimmingColor;
    }
    for (UIView *v in [self.timedEventsMeView visibleSupplementaryViewsOfKind:DimmingMeViewKind]) {
        v.backgroundColor = dimmingColor;
    }
}

// public
- (void)setEventCoveringType:(MGCDayPlannerCoveringType)eventCoveringType {
    _eventCoveringType = eventCoveringType;
    self.timedEventsViewLayout.coveringType = eventCoveringType == MGCDayPlannerCoveringTypeComplex ? TimedEventCoveringTypeComplex : TimedEventCoveringTypeClassic;
    self.timedEventsMeViewLayout.coveringType = eventCoveringType == MGCDayPlannerCoveringTypeComplex ? TimedEventMeCoveringTypeComplex:TimedEventMeCoveringTypeClassic;
    [self.dayColumnsView setNeedsDisplay];
}

#pragma mark - Private properties

// startDate is the first currently loaded day in the collection views - time is set to 00:00
- (NSDate*)startDate
{
    if (_startDate == nil) {
        _startDate = [self.calendar mgc_startOfDayForDate:[NSDate date]];
        
        if (self.dateRange && ![self.dateRange containsDate:_startDate]) {
            _startDate = self.dateRange.start;
        }
    }
    return _startDate;
}

- (void)setStartDate:(NSDate*)startDate
{
    startDate = [self.calendar mgc_startOfDayForDate:startDate];
    
    NSAssert([startDate compare:self.dateRange.start] !=  NSOrderedAscending, @"start date not in the scrollable date range");
    NSAssert([startDate compare:self.maxStartDate] != NSOrderedDescending, @"start date not in the scrollable date range");
    
    _startDate = startDate;
    
    //NSLog(@"Loaded days range: %@", self.loadedDaysRange);
}

- (NSDate*)maxStartDate
{
    NSDate *date = nil;
    
    if (self.dateRange) {
        NSDateComponents *comps = [NSDateComponents new];
        comps.day = -(2 * kDaysLoadingStep + 1) * self.numberOfVisibleDays;
        date = [self.calendar dateByAddingComponents:comps toDate:self.dateRange.end options:0];
        
        if ([date compare:self.dateRange.start] == NSOrderedAscending) {
            date = self.dateRange.start;
        }
    }
    return date;
}

- (NSUInteger)numberOfLoadedDays
{
    NSUInteger numDays = (2 * kDaysLoadingStep + 1) * self.numberOfVisibleDays;
    if (self.dateRange) {
        NSInteger diff = [self.dateRange components:NSCalendarUnitDay forCalendar:self.calendar].day;
        numDays = MIN(numDays, diff);  // cannot load more than the total number of scrollable days
    }
    return numDays;
}

- (MGCDateRange*)loadedDaysRange
{
    NSDateComponents *comps = [NSDateComponents new];
    comps.day = self.numberOfLoadedDays;
    NSDate *endDate = [self.calendar dateByAddingComponents:comps toDate:self.startDate options:0];
    return [MGCDateRange dateRangeWithStart:self.startDate end:endDate];
}

// first fully visible day (!= visibleDays.start)
- (NSDate*)firstVisibleDate
{
    CGFloat xOffset = self.timedEventsView.contentOffset.x;
    NSUInteger section = ceilf(xOffset / self.dayColumnSize.width);
    return [self dateFromDayOffset:section];
}

#pragma mark - Utilities

// dayOffset is the offset from the first loaded day in the view (ie startDate)
- (CGFloat)xOffsetFromDayOffset:(NSInteger)dayOffset
{
    return (dayOffset * self.dayColumnSize.width);
}

// dayOffset is the offset from the first loaded day in the view (ie startDate)
- (NSDate*)dateFromDayOffset:(NSInteger)dayOffset
{
    NSDateComponents *comp = [NSDateComponents new];
    comp.day = dayOffset;
    return [self.calendar dateByAddingComponents:comp toDate:self.startDate options:0];
}

// returns the day offset from the first loaded day in the view (ie startDate)
- (NSInteger)dayOffsetFromDate:(NSDate*)date
{
    NSAssert(date, @"dayOffsetFromDate: was passed nil date");
    
    NSDateComponents *comps = [self.calendar components:NSCalendarUnitDay fromDate:self.startDate toDate:date options:0];
    return comps.day;
}

// returns the time interval corresponding to a vertical offset in the timedEventsView coordinates,
// rounded according to given parameter (in minutes)
- (NSTimeInterval)timeFromOffset:(CGFloat)yOffset rounding:(NSUInteger)rounding
{
    rounding = MAX(rounding % 60, 1);
    
    CGFloat hour = fmax(0, (yOffset - self.eventsViewInnerMargin) / self.hourSlotHeight) + self.hourRange.location;
    if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        hour = fmax(0, yOffset / self.hourSlotHeight) + self.hourRange.location;
    }
    NSTimeInterval ti = roundf((hour * 3600) / (rounding * 60)) * (rounding * 60);
    
    return ti;
}

// returns the vertical offset in the timedEventsView coordinates corresponding to given time interval
// previously rounded according to parameter (in minutes)
- (CGFloat)offsetFromTime:(NSTimeInterval)ti rounding:(NSUInteger)rounding
{
    rounding = MAX(rounding % 60, 1);
    ti = roundf(ti / (rounding * 60)) * (rounding * 60);
    CGFloat hour = ti / 3600. - self.hourRange.location;
    if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        return MGCAlignedFloat(hour * self.hourSlotHeight);
    }else{
        return MGCAlignedFloat(hour * self.hourSlotHeight + self.eventsViewInnerMargin);
    }
}

- (CGFloat)offsetFromDate:(NSDate*)date
{
    NSDateComponents *comp = [self.calendar components:(NSCalendarUnitHour|NSCalendarUnitMinute) fromDate:date];
    CGFloat y = roundf((comp.hour + comp.minute / 60. - self.hourRange.location) * self.hourSlotHeight + self.eventsViewInnerMargin);
    if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        y = roundf((comp.hour + comp.minute / 60. - self.hourRange.location) * self.hourSlotHeight);
    }
    // when the following line is commented, event cells and dimming views are not constrained to the visible hour range
    // (ie cells can show past the edge of content)
    //y = fmax(self.eventsViewInnerMargin, fmin(self.dayColumnSize.height - self.eventsViewInnerMargin, y));
    return MGCAlignedFloat(y);
}

// returns the offset for a given event date and type in self coordinates
- (CGPoint)offsetFromDate:(NSDate*)date eventType:(MGCEventType)type
{
    CGFloat x = [self xOffsetFromDayOffset:[self dayOffsetFromDate:date]];
    if(type == MGCAllDayEventType) {
        CGPoint pt = CGPointMake(x, 0);
        return [self convertPoint:pt fromView:self.allDayEventsView];
    }
    else {
        NSTimeInterval ti = [date timeIntervalSinceDate:[self.calendar mgc_startOfDayForDate:date]];
        CGFloat y = [self offsetFromTime:ti rounding:1];
        CGPoint pt = CGPointMake(x, y);
        return [self convertPoint:pt fromView:self.timedEventsView];
    }
}

// returns the scrollable time range for the day at date, depending on hourRange
- (MGCDateRange*)scrollableTimeRangeForDate:(NSDate*)date
{
    NSDate *dayRangeStart = [self.calendar dateBySettingHour:self.hourRange.location minute:0 second:0 ofDate:date options:0];
    NSDate *dayRangeEnd = [self.calendar dateBySettingHour:NSMaxRange(self.hourRange) - 1 minute:59 second:0 ofDate:date options:0];
    return [MGCDateRange dateRangeWithStart:dayRangeStart end:dayRangeEnd];
}

#pragma mark - Locating days and events

// public
- (NSDate*)dateAtPoint:(CGPoint)point rounded:(BOOL)rounded
{
    if (self.dayColumnsView.contentSize.width == 0) return nil;
    
    CGPoint ptDayColumnsView = [self convertPoint:point toView:self.dayColumnsView];
    NSIndexPath *dayPath = [self.dayColumnsView indexPathForItemAtPoint:ptDayColumnsView];
    
    if (dayPath) {
        // get the day/month/year portion of the date
        NSDate *date = [self dateFromDayOffset:dayPath.section];
        
        // get the time portion
        CGPoint ptTimedEventsView = [self convertPoint:point toView:self.timedEventsView];
        if ([self.timedEventsView pointInside:ptTimedEventsView withEvent:nil]) {
            // max time for is 23:59
            NSTimeInterval ti = fminf([self timeFromOffset:ptTimedEventsView.y rounding:15], 24 * 3600. - 60);
            if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
                ti = fminf([self timeFromOffset:(ptTimedEventsView.x - floorf(ptTimedEventsView.x/self.dayColumnSize.width)*self.dayColumnSize.width) rounding:15], 24 * 3600. - 60);
            }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
                ti = fminf([self timeFromOffset:(ptTimedEventsView.x - floorf(ptTimedEventsView.x/self.dayColumnSize.width)*self.dayColumnSize.width) rounding:15], 24 * 3600. - 60);
            }
            date = [date dateByAddingTimeInterval:ti];
        }
        return date;
    }
    return nil;
}

// public
- (MGCEventView*)eventViewAtPoint:(CGPoint)point type:(MGCEventType*)type index:(NSUInteger*)index date:(NSDate**)date
{
    CGPoint ptTimedEventsView = [self convertPoint:point toView:self.timedEventsView];
    CGPoint ptAllDayEventsView = [self convertPoint:point toView:self.allDayEventsView];
    
    if ([self.timedEventsView pointInside:ptTimedEventsView withEvent:nil]) {
        NSIndexPath *path = [self.timedEventsView indexPathForItemAtPoint:ptTimedEventsView];
        if (path) {
            MGCEventCell *cell = (MGCEventCell*)[self.timedEventsView cellForItemAtIndexPath:path];
            if (type) *type = MGCTimedEventType;
            if (index) *index = path.item;
            if (date) *date = [self dateFromDayOffset:path.section];
            return cell.eventView;
        }
    }
    else if ([self.allDayEventsView pointInside:ptAllDayEventsView withEvent:nil]) {
        NSIndexPath *path = [self.allDayEventsView indexPathForItemAtPoint:ptAllDayEventsView];
        if (path) {
            MGCEventCell *cell = (MGCEventCell*)[self.allDayEventsView cellForItemAtIndexPath:path];
            if (type) *type = MGCAllDayEventType;
            if (index) *index = path.item;
            if (date) *date = [self dateFromDayOffset:path.section];
            return cell.eventView;
        }
    }
    
    return nil;
}

// public
- (MGCEventView*)eventViewOfType:(MGCEventType)type atIndex:(NSUInteger)index date:(NSDate*)date
{
    NSAssert(date, @"eventViewOfType:atIndex:date: was passed nil date");
    
    NSUInteger section = [self dayOffsetFromDate:date];
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:section];
    
    return [[self collectionViewCellForEventOfType:type atIndexPath:indexPath] eventView];
}

#pragma mark - Navigation

// public
-(void)scrollToDate:(NSDate*)date options:(MGCDayPlannerScrollType)options animated:(BOOL)animated fromTap:(BOOL)isTapped
{
    self.currentSelectedDate = date;
    self.isSelectedNextPrewBtn = YES;
    NSAssert(date, @"scrollToDate:date: was passed nil date");
    
    if (self.dateRange && ![self.dateRange containsDate:date]) {
        [NSException raise:@"Invalid parameter" format:@"date %@ is not in range %@ for this day planner view", date, self.dateRange];
    }
    
    // if scrolling is already happening, let it end properly
    if (self.controllingScrollView) return;
    
    NSDate *firstVisible = date;
    NSDate *maxScrollable = [self maxScrollableDate];
    if (maxScrollable != nil && [firstVisible compare:maxScrollable] == NSOrderedDescending) {
        firstVisible = maxScrollable;
    }
    
    NSDate *dayStart = [self.calendar mgc_startOfDayForDate:firstVisible];
    self.scrollTargetDate = dayStart;
    
    NSTimeInterval ti = [date timeIntervalSinceDate:dayStart];
    
    CGFloat y = [self offsetFromTime:ti rounding:0];
    y = fmaxf(fminf(y, MGCAlignedFloat(self.timedEventsView.contentSize.height - self.timedEventsView.bounds.size.height)), 0);
    CGFloat x = [self xOffsetFromDayOffset:[self dayOffsetFromDate:dayStart]];
    
    CGPoint offset = self.timedEventsView.contentOffset;
    
    MGCDayPlannerView * __weak weakSelf = self;
    dispatch_block_t completion = ^{
        weakSelf.userInteractionEnabled = YES;
        if (!animated && [weakSelf.delegate respondsToSelector:@selector(dayPlannerView:didScroll:)]) {
            [weakSelf.delegate dayPlannerView:weakSelf didScroll:options];
        }
    };
    
    if (options == MGCDayPlannerScrollTime) {
        self.userInteractionEnabled = NO;
        offset.y = y;
        [self setTimedEventsViewContentOffset:offset animated:animated completion:completion];
    }
    else if (options == MGCDayPlannerScrollDate) {
        self.userInteractionEnabled = NO;
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking && isTapped) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"hh.mm a"];
            NSDate *date1 = [formatter dateFromString:[formatter stringFromDate:[NSDate date]]];
            NSInteger section = [self dayOffsetFromDate:date];
            NSDate *dateWithOutTime = [self dateFromDayOffset:section];
            NSDate *date2 = [formatter dateFromString:[formatter stringFromDate:dateWithOutTime]];
            NSTimeInterval interval = [date1 timeIntervalSinceDate: date2];
            CGFloat xOffsetAdd = [self offsetFromTime:interval rounding:0] - self.timedEventsView.bounds.size.width/2;
            xOffsetAdd = fmaxf(fminf(xOffsetAdd, MGCAlignedFloat(self.dayColumnSize.width - self.timedEventsView.bounds.size.width)), 0);
            offset.x = x + xOffsetAdd;
        }else{
            if (self.isScrolledPreDateWithScrolling) {
                offset.x = x + self.dayColumnSize.width - self.bounds.size.width;
            }else{
                offset.x = x;
            }
        }
        [self setTimedEventsViewContentOffset:offset animated:animated completion:completion];
    }
    else if (options == MGCDayPlannerScrollDateTime) {
        self.userInteractionEnabled = NO;
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking && isTapped) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"hh.mm a"];
            NSDate *date1 = [formatter dateFromString:[formatter stringFromDate:[NSDate date]]];
            NSInteger section = [self dayOffsetFromDate:date];
            NSDate *dateWithOutTime = [self dateFromDayOffset:section];
            NSDate *date2 = [formatter dateFromString:[formatter stringFromDate:dateWithOutTime]];
            NSTimeInterval interval = [date1 timeIntervalSinceDate: date2];
            CGFloat xOffsetAdd = [self offsetFromTime:interval rounding:0] - self.timedEventsView.bounds.size.width/2;
            xOffsetAdd = fmaxf(fminf(xOffsetAdd, MGCAlignedFloat(self.dayColumnSize.width - self.timedEventsView.bounds.size.width)), 0);
            offset.x = x + xOffsetAdd;
        }else{
            offset.x = x;
        }
        [self setTimedEventsViewContentOffset:offset animated:animated completion:^(void){
            CGPoint offset = CGPointMake(weakSelf.timedEventsView.contentOffset.x, y);
            [weakSelf setTimedEventsViewContentOffset:offset animated:animated completion:completion];
        }];
    }
}

// public
- (void)pageForwardAnimated:(BOOL)animated date:(NSDate**)date
{
    NSDate *next = [self nextDateForPagingAfterDate:self.visibleDays.start];
    if (date != nil)
        *date = next;
    [self scrollToDate:next options:MGCDayPlannerScrollDate animated:animated fromTap:YES];
    self.isSelectedNextPrewBtn = YES;
}

// public
- (void)pageBackwardsAnimated:(BOOL)animated date:(NSDate**)date
{
    NSDate *prev = [self prevDateForPagingBeforeDate:self.firstVisibleDate];
    
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        NSDate *currentDate = self.currentSelectedDate;
        NSInteger section = [self dayOffsetFromDate:prev];
        NSInteger currentSection = [self dayOffsetFromDate:currentDate];
        if (section == currentSection) {
            prev = [self dateFromDayOffset:(section-1)];
        }else{
            
        }
    }
    
    if (date != nil)
        *date = prev;
    [self scrollToDate:prev options:MGCDayPlannerScrollDate animated:animated fromTap:YES];
    self.isSelectedNextPrewBtn = YES;
}

// returns the latest date to be shown on the left side of the view,
// nil if the day planner has no date range.
- (NSDate*)maxScrollableDate
{
    if (self.dateRange != nil) {
        NSUInteger numVisible = MIN(self.numberOfVisibleDays, [self.dateRange components:NSCalendarUnitDay forCalendar:self.calendar].day);
        NSDateComponents *comps = [NSDateComponents new];
        comps.day = -numVisible;
        return [self.calendar dateByAddingComponents:comps toDate:self.dateRange.end options:0];
    }
    return nil;
}

// retuns the earliest date to be shown on the left side of the view,
// nil if the day planner has no date range.
- (NSDate*)minScrollableDate
{
    return self.dateRange != nil ? self.dateRange.start : nil;
}

// if the view shows at least 7 days, returns the next start of a week after date,
// otherwise returns date plus the number of visible days, within the limits of the view day range
- (NSDate*)nextDateForPagingAfterDate:(NSDate*)date
{
    NSAssert(date, @"nextPageForPagingAfterDate: was passed nil date");
    
    NSDate *nextDate;
    if (self.numberOfVisibleDays >= 7) {
        nextDate = [self.calendar mgc_nextStartOfWeekForDate:date];
    }
    else {
        NSDateComponents *comps = [NSDateComponents new];
        comps.day = self.numberOfVisibleDays;
        nextDate = [self.calendar dateByAddingComponents:comps toDate:date options:0];
    }
    
    NSDate *maxScrollable = [self maxScrollableDate];
    if (maxScrollable != nil && [nextDate compare:maxScrollable] == NSOrderedDescending) {
        nextDate = maxScrollable;
    }
    return nextDate;
}

// If the view shows at least 7 days, returns the previous start of a week before date,
// otherwise returns date minus the number of visible days, within the limits of the view day range
- (NSDate*)prevDateForPagingBeforeDate:(NSDate*)date
{
    NSAssert(date, @"prevDateForPagingBeforeDate: was passed nil date");
    
    NSDate *prevDate;
    if (self.numberOfVisibleDays >= 7) {
        prevDate = [self.calendar mgc_startOfWeekForDate:date];
        if ([prevDate isEqualToDate:date]) {
            NSDateComponents* comps = [NSDateComponents new];
            comps.day = -7;
            prevDate = [self.calendar dateByAddingComponents:comps toDate:date options:0];
        }
    }
    else {
        NSDateComponents *comps = [NSDateComponents new];
        comps.day = -self.numberOfVisibleDays;
        prevDate = [self.calendar dateByAddingComponents:comps toDate:date options:0];
    }
    
    NSDate *minScrollable = [self minScrollableDate];
    if (minScrollable != nil && [prevDate compare:minScrollable] == NSOrderedAscending) {
        prevDate = minScrollable;
    }
    return prevDate;
    
}

#pragma mark - Subviews

- (UICollectionView*)timedEventsView
{
    if (!_timedEventsView) {
        _timedEventsView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.timedEventsViewLayout];
        //_timedEventsView.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.3];
        _timedEventsView.backgroundColor = [UIColor clearColor];
        _timedEventsView.dataSource = self;
        _timedEventsView.delegate = self;
        _timedEventsView.showsVerticalScrollIndicator = NO;
        _timedEventsView.showsHorizontalScrollIndicator = NO;
        _timedEventsView.scrollsToTop = NO;
        _timedEventsView.decelerationRate = UIScrollViewDecelerationRateFast;
        _timedEventsView.allowsSelection = NO;
        _timedEventsView.directionalLockEnabled = YES;
        
        [_timedEventsView registerClass:MGCEventCell.class forCellWithReuseIdentifier:EventCellReuseIdentifier];
        [_timedEventsView registerClass:UICollectionReusableView.class forSupplementaryViewOfKind:DimmingViewKind withReuseIdentifier:DimmingViewReuseIdentifier];
        
        UILongPressGestureRecognizer *longPress = [UILongPressGestureRecognizer new];
        [longPress addTarget:self action:@selector(handleLongPress:)];
        [_timedEventsView addGestureRecognizer:longPress];
        UIPinchGestureRecognizer *pinch = [UIPinchGestureRecognizer new];
        [pinch addTarget:self action:@selector(handlePinch:)];
        [_timedEventsView addGestureRecognizer:pinch];
        
        UITapGestureRecognizer *tap = [UITapGestureRecognizer new];
        tap.delegate = self;
        [tap addTarget:self action:@selector(handleTap:)];
        [_timedEventsView addGestureRecognizer:tap];
        
        
    }
    return _timedEventsView;
}
- (UIView *)maskViewForHideMeOnTimedEventsView{
    if (!_maskViewForHideMeOnTimedEventsView) {
        _maskViewForHideMeOnTimedEventsView = [[UIView alloc] initWithFrame:CGRectZero];
        _maskViewForHideMeOnTimedEventsView.backgroundColor = [UIColor whiteColor];
    }
    return _maskViewForHideMeOnTimedEventsView;
}
- (UICollectionView*)timedEventsMeView
{
    if (!_timedEventsMeView) {
        _timedEventsMeView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.timedEventsMeViewLayout];
        //_timedEventsMeView.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.3];
        _timedEventsMeView.backgroundColor = [UIColor whiteColor];
        _timedEventsMeView.dataSource = self;
        _timedEventsMeView.delegate = self;
        _timedEventsMeView.showsVerticalScrollIndicator = NO;
        _timedEventsMeView.showsHorizontalScrollIndicator = NO;
        _timedEventsMeView.scrollsToTop = NO;
        _timedEventsMeView.decelerationRate = UIScrollViewDecelerationRateFast;
        _timedEventsMeView.allowsSelection = NO;
        _timedEventsMeView.directionalLockEnabled = YES;
        
        [_timedEventsMeView registerClass:MGCEventCell.class forCellWithReuseIdentifier:EventCellReuseIdentifier];
        [_timedEventsMeView registerClass:UICollectionReusableView.class forSupplementaryViewOfKind:DimmingMeViewKind withReuseIdentifier:DimmingViewMeReuseIdentifier];
        
        UILongPressGestureRecognizer *longPress = [UILongPressGestureRecognizer new];
        [longPress addTarget:self action:@selector(handleLongPress:)];
        [_timedEventsMeView addGestureRecognizer:longPress];
        UIPinchGestureRecognizer *pinch = [UIPinchGestureRecognizer new];
        [pinch addTarget:self action:@selector(handlePinch:)];
        [_timedEventsMeView addGestureRecognizer:pinch];
        
        UITapGestureRecognizer *tap = [UITapGestureRecognizer new];
        tap.delegate = self;
        [tap addTarget:self action:@selector(handleTap:)];
        [_timedEventsMeView addGestureRecognizer:tap];
        
        
    }
    return _timedEventsMeView;
}

- (UICollectionView*)allDayEventsView
{
    if (!_allDayEventsView && self.showsAllDayEvents) {
        _allDayEventsView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.allDayEventsViewLayout];
        _allDayEventsView.backgroundColor = [UIColor clearColor];
        _allDayEventsView.dataSource = self;
        _allDayEventsView.delegate = self;
        _allDayEventsView.showsVerticalScrollIndicator = YES;
        _allDayEventsView.showsHorizontalScrollIndicator = NO;
        _allDayEventsView.decelerationRate = UIScrollViewDecelerationRateFast;
        _allDayEventsView.allowsSelection = NO;
        _allDayEventsView.directionalLockEnabled = YES;
        
        [_allDayEventsView registerClass:MGCEventCell.class forCellWithReuseIdentifier:EventCellReuseIdentifier];
        
        [_allDayEventsView registerClass:UICollectionReusableView.class forSupplementaryViewOfKind:MoreEventsViewKind withReuseIdentifier:MoreEventsViewReuseIdentifier];  // test
        
        UILongPressGestureRecognizer *longPress = [UILongPressGestureRecognizer new];
        [longPress addTarget:self action:@selector(handleLongPress:)];
        [_allDayEventsView addGestureRecognizer:longPress];
        UITapGestureRecognizer *tap = [UITapGestureRecognizer new];
        [tap addTarget:self action:@selector(handleTap:)];
        [_allDayEventsView addGestureRecognizer:tap];
        
    }
    return _allDayEventsView;
}
- (UIView *)viewToGetDateOfDayColumnView{
    if (!_viewToGetDateOfDayColumnView) {
        _viewToGetDateOfDayColumnView = [[UIView alloc] initWithFrame:CGRectZero];
        _viewToGetDateOfDayColumnView.backgroundColor = [UIColor clearColor];
        
        UITapGestureRecognizer *tap = [UITapGestureRecognizer new];
        tap.delegate = self;
        [tap addTarget:self action:@selector(handleTap:)];
        [_viewToGetDateOfDayColumnView addGestureRecognizer:tap];
        
    }
    return _viewToGetDateOfDayColumnView;
}
- (UICollectionView*)dayColumnsView
{
    if (!_dayColumnsView) {
        MGCDayColumnViewFlowLayout *layout = [MGCDayColumnViewFlowLayout new];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.minimumInteritemSpacing = 0;
        layout.minimumLineSpacing = 0;
        
        _dayColumnsView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _dayColumnsView.backgroundColor = [UIColor clearColor];
        _dayColumnsView.dataSource = self;
        _dayColumnsView.delegate = self;
        _dayColumnsView.showsHorizontalScrollIndicator = NO;
        _dayColumnsView.decelerationRate = UIScrollViewDecelerationRateFast;
        _dayColumnsView.scrollEnabled = NO;
        _dayColumnsView.allowsSelection = NO;
        
        [_dayColumnsView registerClass:MGCDayColumnCell.class forCellWithReuseIdentifier:DayColumnCellReuseIdentifier];
        
        
    }
    return _dayColumnsView;
}
- (UIScrollView*)timeHorizontalScrollView
{
    if (!_timeHorizontalScrollView) {
        _timeHorizontalScrollView = [[UIScrollView alloc]initWithFrame:CGRectZero];
        _timeHorizontalScrollView.backgroundColor = [UIColor clearColor];
        _timeHorizontalScrollView.delegate = self;
        _timeHorizontalScrollView.showsVerticalScrollIndicator = NO;
        _timeHorizontalScrollView.decelerationRate = UIScrollViewDecelerationRateFast;
        _timeHorizontalScrollView.scrollEnabled = NO;
        
        _timeColumnsView = [[MGCTimeColumnsView alloc]initWithFrame:CGRectZero];
        _timeColumnsView.timeColor = self.timeSeparatorsColor;
        _timeColumnsView.contentMode = UIViewContentModeRedraw;
        [_timeHorizontalScrollView addSubview:_timeColumnsView];
    }
    return _timeHorizontalScrollView;
}
- (UIView*)timeLabelCV{
    if (!_timeLabelCV) {
        _timeLabelCV = [[UIView alloc]initWithFrame:CGRectZero];
        _timeLabelCV.backgroundColor = [UIColor whiteColor];
    }
    return _timeLabelCV;
}
- (UIScrollView*)timeScrollView
{
    if (!_timeScrollView) {
        _timeScrollView = [[UIScrollView alloc]initWithFrame:CGRectZero];
        _timeScrollView.backgroundColor = [UIColor clearColor];
        _timeScrollView.delegate = self;
        _timeScrollView.showsVerticalScrollIndicator = NO;
        _timeScrollView.decelerationRate = UIScrollViewDecelerationRateFast;
        _timeScrollView.scrollEnabled = NO;
        
        _timeRowsView = [[MGCTimeRowsView alloc]initWithFrame:CGRectZero];
        _timeRowsView.delegate = self;
        _timeRowsView.timeColor = self.timeSeparatorsColor;
        _timeRowsView.currentTimeColor = self.currentTimeColor;
        _timeRowsView.hourSlotHeight = self.hourSlotHeight;
        _timeRowsView.hourRange = self.hourRange;
        _timeRowsView.insetsHeight = self.eventsViewInnerMargin;
        _timeRowsView.timeColumnWidth = self.timeColumnWidth;
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
            _timeRowsView.timeColumnWidth = 0;
        }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
            _timeRowsView.timeColumnWidth = 0;
        }
        _timeRowsView.contentMode = UIViewContentModeRedraw;
        [_timeScrollView addSubview:_timeRowsView];
    }
    return _timeScrollView;
}

- (UIView*)allDayEventsBackgroundView
{
    if (!_allDayEventsBackgroundView) {
        _allDayEventsBackgroundView = [[UIView alloc] initWithFrame:CGRectZero];
        _allDayEventsBackgroundView.backgroundColor = [UIColor colorWithRed:.8 green:.8 blue:.83 alpha:1.];
        _allDayEventsBackgroundView.clipsToBounds = YES;
        _allDayEventsBackgroundView.layer.borderColor = [UIColor lightGrayColor].CGColor;
        _allDayEventsBackgroundView.layer.borderWidth = 1;
    }
    return _allDayEventsBackgroundView;
}


#pragma mark - Layouts

- (MGCTimedEventsViewLayout*)timedEventsViewLayout
{
    if (!_timedEventsViewLayout) {
        _timedEventsViewLayout = [MGCTimedEventsViewLayout new];
        _timedEventsViewLayout.delegate = self;
        _timedEventsViewLayout.dayColumnSize = self.dayColumnSize;
        _timedEventsViewLayout.coveringType = self.eventCoveringType == TimedEventCoveringTypeComplex ? TimedEventCoveringTypeComplex : TimedEventCoveringTypeClassic;
    }
    return _timedEventsViewLayout;
}
- (MGCTimedEventsMeViewLayout*)timedEventsMeViewLayout{
    if (!_timedEventsMeViewLayout) {
        _timedEventsMeViewLayout = [MGCTimedEventsMeViewLayout new];
        _timedEventsMeViewLayout.delegate = self;
        CGSize dayColumnSizeMe = CGSizeMake(self.dayColumnSize.width, 40.0f);
        _timedEventsMeViewLayout.dayColumnSize = dayColumnSizeMe;
        _timedEventsMeViewLayout.coveringType = self.eventCoveringType == TimedEventMeCoveringTypeComplex ? TimedEventMeCoveringTypeComplex : TimedEventMeCoveringTypeClassic;
    }
    return _timedEventsMeViewLayout;
}

- (MGCAllDayEventsViewLayout*)allDayEventsViewLayout
{
    if (!_allDayEventsViewLayout && self.showsAllDayEvents) {
        _allDayEventsViewLayout = [MGCAllDayEventsViewLayout new];
        _allDayEventsViewLayout.delegate = self;
        _allDayEventsViewLayout.dayColumnWidth = self.dayColumnSize.width;
        _allDayEventsViewLayout.eventCellHeight = self.allDayEventCellHeight;
        _allDayEventsViewLayout.maxContentHeight = 45; // test
    }
    return _allDayEventsViewLayout;
}

#pragma mark - Event view manipulation

- (void)registerClass:(Class)viewClass forEventViewWithReuseIdentifier:(NSString*)identifier
{
    [self.reuseQueue registerClass:viewClass forObjectWithReuseIdentifier:identifier];
}

- (MGCEventView*)dequeueReusableViewWithIdentifier:(NSString*)identifier forEventOfType:(MGCEventType)type atIndex:(NSUInteger)index date:(NSDate*)date
{
    return (MGCEventView*)[self.reuseQueue dequeueReusableObjectWithReuseIdentifier:identifier];
}

#pragma mark - Zooming

- (void)handlePinch:(UIPinchGestureRecognizer*)gesture
{
    if (!self.zoomingEnabled) return;
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.hourSlotHeightForGesture = self.hourSlotHeight;
    }
    else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (gesture.numberOfTouches > 1) {
            CGFloat hourSlotHeight = self.hourSlotHeightForGesture * gesture.scale;
            if (hourSlotHeight != self.hourSlotHeight && self.zoomScaleWithPich != gesture.scale && self.zoomScaleWithPich != 0) {
                if (self.zoomScaleWithPich<gesture.scale) {
                    self.isZoomingIn = YES;
                }else{
                    self.isZoomingIn = NO;
                }
                self.zoomScaleWithPich = gesture.scale;
                self.hourSlotHeight = hourSlotHeight;
                
                if ([self.delegate respondsToSelector:@selector(dayPlannerViewDidZoom:)]) {
                    [self.delegate dayPlannerViewDidZoom:self];
                }
            }else{
                self.zoomScaleWithPich = gesture.scale;
            }
        }
    }
}

#pragma mark - Selection

- (void)handleTap:(UITapGestureRecognizer*)gesture
{
    if (gesture.state == UIGestureRecognizerStateEnded)
    {
        [self deselectEventWithDelegate:YES]; // deselect previous
        [self deselectEventMeWithDelegate:YES];
        
        if ([gesture.view isKindOfClass:[UICollectionView class]]) {
            UICollectionView *view = (UICollectionView*)gesture.view;
            CGPoint pt = [gesture locationInView:view];
            if (view == self.timedEventsView) {
                NSIndexPath *path = [view indexPathForItemAtPoint:pt];
                if (path)  // a cell was touched
                {
                    NSDate *date = [self dateFromDayOffset:path.section];
                    MGCEventType type = (view == self.timedEventsView) ? MGCTimedEventType : MGCAllDayEventType;
                    
                    [self selectEventWithDelegate:YES type:type atIndex:path.item date:date];
                }
            }else{
                
                NSIndexPath *path = [view indexPathForItemAtPoint:pt];
                if (path)  // a cell was touched
                {
                    NSDate *date = [self dateFromDayOffset:path.section];
                    MGCEventType type = (view == self.timedEventsMeView) ? MGCTimedEventType : MGCAllDayEventType;
                    
                    [self selectEventMeWithDelegate:YES type:type atIndex:path.item date:date];
                }
            }
        }else if ([gesture.view isKindOfClass:[UIView class]]){
            CGPoint pt = [gesture locationInView:self];
            pt.y = 0;
            NSDate *date = [self dateAtPoint:pt rounded:YES];
            NSDateFormatter *dateFormatter = [NSDateFormatter new];
            dateFormatter.dateFormat = @"d MMM eeeee";
            NSLog(@"%@", [dateFormatter stringFromDate:date]);
            if ([self.dataSource respondsToSelector:@selector(dayPlannerView:didSelectDayCellAtDate:)]) {
                [self.dataSource dayPlannerView:self didSelectDayCellAtDate:date];
            }
        }
    }
}

// public
- (MGCEventView*)selectedEventView
{
    if (self.selectedCellIndexPath) {
        MGCEventCell *cell = [self collectionViewCellForEventOfType:self.selectedCellType atIndexPath:self.selectedCellIndexPath];
        return cell.eventView;
    }
    return nil;
}

// tellDelegate is used to distinguish between user selection (touch) where delegate is informed,
// and programmatically selected events where delegate is not informed
-(void)selectEventWithDelegate:(BOOL)tellDelegate type:(MGCEventType)type atIndex:(NSUInteger)index date:(NSDate*)date
{
    [self deselectEventWithDelegate:tellDelegate];
    
    if (self.allowsSelection) {
        NSInteger section = [self dayOffsetFromDate:date];
        NSIndexPath *path = [NSIndexPath indexPathForItem:index inSection:section];
        
        MGCEventCell *cell = [self collectionViewCellForEventOfType:type atIndexPath:path];
        if (cell)
        {
            BOOL shouldSelect = YES;
            if (tellDelegate && [self.delegate respondsToSelector:@selector(dayPlannerView:shouldSelectEventOfType:atIndex:date:)]) {
                shouldSelect = [self.delegate dayPlannerView:self shouldSelectEventOfType:type atIndex:index date:date];
            }
            
            if (shouldSelect) {
                cell.selected = YES;
                self.selectedCellIndexPath = path;
                self.selectedCellType = type;
                
                if (tellDelegate && [self.delegate respondsToSelector:@selector(dayPlannerView:didSelectEventOfType:atIndex:date:)]) {
                    [self.delegate dayPlannerView:self didSelectEventOfType:type atIndex:path.item date:date];
                }
            }
        }
    }
}
-(void)selectEventMeWithDelegate:(BOOL)tellDelegate type:(MGCEventType)type atIndex:(NSUInteger)index date:(NSDate*)date
{
    [self deselectEventMeWithDelegate:tellDelegate];
    
    if (self.allowsSelection) {
        NSInteger section = [self dayOffsetFromDate:date];
        NSIndexPath *path = [NSIndexPath indexPathForItem:index inSection:section];
        
        MGCEventCell *cell = [self collectionViewCellForEventOfType:type atIndexPath:path];
        if (cell)
        {
            BOOL shouldSelect = YES;
            if (tellDelegate && [self.delegate respondsToSelector:@selector(dayPlannerView:shouldSelectEventOfType:atIndex:date:)]) {
                shouldSelect = [self.delegate dayPlannerView:self shouldSelectEventOfType:type atIndex:index date:date];
            }
            
            if (shouldSelect) {
                cell.selected = YES;
                self.selectedCellIndexPath = path;
                self.selectedCellType = type;
                
                if (tellDelegate && [self.delegate respondsToSelector:@selector(dayPlannerView:didSelectEventOfType:atIndex:date:)]) {
                    [self.delegate dayPlannerView:self didSelectEventOfType:type atIndex:path.item date:date];
                }
            }
        }
    }
}

// public
- (void)selectEventOfType:(MGCEventType)type atIndex:(NSUInteger)index date:(NSDate*)date
{
    [self selectEventWithDelegate:NO type:type atIndex:index date:date];
}

// tellDelegate is used to distinguish between user deselection (touch) where delegate is informed,
// and programmatically deselected events where delegate is not informed
- (void)deselectEventWithDelegate:(BOOL)tellDelegate
{
    if (self.allowsSelection && self.selectedCellIndexPath)
    {
        MGCEventCell *cell = [self collectionViewCellForEventOfType:self.selectedCellType atIndexPath:self.selectedCellIndexPath];
        cell.selected = NO;
        
        NSDate *date = [self dateFromDayOffset:self.selectedCellIndexPath.section];
        if (tellDelegate && [self.delegate respondsToSelector:@selector(dayPlannerView:didDeselectEventOfType:atIndex:date:)]) {
            [self.delegate dayPlannerView:self didDeselectEventOfType:self.selectedCellType atIndex:self.selectedCellIndexPath.item date:date];
        }
        
        self.selectedCellIndexPath = nil;
    }
}
- (void)deselectEventMeWithDelegate:(BOOL)tellDelegate
{
    if (self.allowsSelection && self.selectedCellIndexPath)
    {
        MGCEventCell *cell = [self collectionViewCellForEventOfType:self.selectedCellType atIndexPath:self.selectedCellIndexPath];
        cell.selected = NO;
        
        NSDate *date = [self dateFromDayOffset:self.selectedCellIndexPath.section];
        if (tellDelegate && [self.delegate respondsToSelector:@selector(dayPlannerView:didDeselectEventOfType:atIndex:date:)]) {
            [self.delegate dayPlannerView:self didDeselectEventOfType:self.selectedCellType atIndex:self.selectedCellIndexPath.item date:date];
        }
        
        self.selectedCellIndexPath = nil;
    }
}

// public
- (void)deselectEvent
{
    [self deselectEventWithDelegate:NO];
}

#pragma mark - Event views interaction

// For non modifiable events like holy days, birthdays... for which delegate method
// shouldStartMovingEventOfType returns NO, we bounce animate the cell when user tries to move it
- (void)bounceAnimateCell:(MGCEventCell*)cell
{
    CGRect frame = cell.frame;
    
    [UIView animateWithDuration:0.2 animations:^{
        [UIView setAnimationRepeatCount:2];
        cell.frame = CGRectInset(cell.frame, -4, -2);
    } completion:^(BOOL finished){
        cell.frame = frame;
    }];
}

- (CGRect)rectForNewEventOfType:(MGCEventType)type atDate:(NSDate*)date
{
    NSUInteger section = [self dayOffsetFromDate:date];
    CGFloat x = section * self.dayColumnSize.width;
    
    if (type == MGCTimedEventType) {
        CGFloat y =  [self offsetFromTime:self.durationForNewTimedEvent rounding:0];
        CGRect rect = CGRectMake(x, y, self.dayColumnSize.width, self.interactiveCellTimedEventHeight);
        return [self convertRect:rect fromView:self.timedEventsView];
    }
    else if (type == MGCAllDayEventType) {
        CGRect rect = CGRectMake(x, 0, self.dayColumnSize.width, self.allDayEventCellHeight);
        return [self convertRect:rect fromView:self.allDayEventsView];
    }
    
    return CGRectNull;
}
- (NSDate *)getCurrentDate{
    NSDate *date = [self dateAtPoint:CGPointMake(0, 0) rounded:YES];
    return date;
}
- (void)handleLongPress:(UILongPressGestureRecognizer*)gesture
{
    CGPoint ptSelf = [gesture locationInView:self];
    
    // long press on a cell or an empty space in the view
    if (gesture.state == UIGestureRecognizerStateBegan)
    {
        [self endInteraction]; // in case previous interaction did not end properly
        
        [self setUserInteractionEnabled:NO];
        
        // where did the gesture start ?
        UICollectionView *view = (UICollectionView*)gesture.view;
        MGCEventType type = (view == self.timedEventsView) ? MGCTimedEventType : MGCAllDayEventType;
        NSIndexPath *path = [view indexPathForItemAtPoint:[gesture locationInView:view]];
        
        if (path) {    // a cell was touched
            if (![self beginMovingEventOfType:type atIndexPath:path withPoint:ptSelf]) {
                gesture.enabled = NO;
                gesture.enabled = YES;
            }
            else {
                self.interactiveCellTouchPoint = [gesture locationInView:self.interactiveCell];
            }
        }
        else {        // an empty space was touched
            CGFloat createEventSlotHeight = floor(self.durationForNewTimedEvent * self.hourSlotHeight / 60.0f / 60.0f);
            NSDate *date = [self dateAtPoint:CGPointMake(ptSelf.x, ptSelf.y - createEventSlotHeight / 2) rounded:YES];
            
            if (![self beginCreateEventOfType:type atDate:date withPoint:ptSelf]) {
                gesture.enabled = NO;
                gesture.enabled = YES;
            }
        }
    }
    // interactive cell was moved
    else if (gesture.state == UIGestureRecognizerStateChanged)
    {
        [self moveInteractiveCellAtPoint:[gesture locationInView:self]];
    }
    // finger was lifted
    else if (gesture.state == UIGestureRecognizerStateEnded)
    {
        [self.dragTimer invalidate];
        self.dragTimer = nil;
        
        NSDate *date = [self dateAtPoint:self.interactiveCell.frame.origin rounded:YES];
        
        if (!self.isInteractiveCellForNewEvent) // existing event
        {
            if (!self.acceptsTarget) {
                [self endInteraction];
            }
            else if (date && [self.dataSource respondsToSelector:@selector(dayPlannerView:moveEventOfType:atIndex:date:toType:date:)]) {
                [self.dataSource dayPlannerView:self moveEventOfType:self.movingEventType atIndex:self.movingEventIndex date:self.movingEventDate toType:self.interactiveCellType date:date];
            }
        }
        else  // new event
        {
            if (!self.acceptsTarget) {
                [self endInteraction];
            }
            else if (date && [self.dataSource respondsToSelector:@selector(dayPlannerView:createNewEventOfType:atDate:withFrame:)]) {
                [self.dataSource dayPlannerView:self createNewEventOfType:self.interactiveCellType atDate:date withFrame:self.interactiveCell.frame];
            }
        }
        
        [self setUserInteractionEnabled:YES];
        //[self endInteraction];
    }
    else if (gesture.state == UIGestureRecognizerStateCancelled)
    {
        [self setUserInteractionEnabled:YES];
    }
}

- (BOOL)beginCreateEventOfType:(MGCEventType)type atDate:(NSDate*)date withPoint:(CGPoint)currentPoint
{
    NSAssert([self.visibleDays containsDate:date], @"beginCreateEventOfType:atDate for non visible date");
    
    if (!self.canCreateEvents) return NO;
    
    self.interactiveCellTimedEventHeight = floor(self.durationForNewTimedEvent * self.hourSlotHeight / 60.0f / 60.0f);
    
    self.isInteractiveCellForNewEvent = YES;
    self.interactiveCellType = type;
    self.interactiveCellTouchPoint = CGPointMake(0, self.interactiveCellTimedEventHeight / 2);
    self.interactiveCellDate = date;
    
    self.interactiveCell = [[MGCInteractiveEventView alloc]initWithFrame:CGRectZero];
    
    if ([self.dataSource respondsToSelector:@selector(dayPlannerView:viewForNewEventOfType:atDate:)]) {
        self.interactiveCell.eventView = [self.dataSource dayPlannerView:self viewForNewEventOfType:type atDate:date];
        NSAssert(self.interactiveCell, @"dayPlannerView:viewForNewEventOfType:atDate can't return nil");
    }
    else {
        MGCStandardEventView *eventView = [[MGCStandardEventView alloc]initWithFrame:CGRectZero];
        eventView.title = NSLocalizedString(@"New Reservation", nil);
        self.interactiveCell.eventView = eventView;
    }
    
    self.acceptsTarget = YES;
    if ([self.dataSource respondsToSelector:@selector(dayPlannerView:canCreateNewEventOfType:atDate:)]) {
        if (![self.dataSource dayPlannerView:self canCreateNewEventOfType:type atDate:date]) {
            self.interactiveCell.forbiddenSignVisible = YES;
            self.acceptsTarget = NO;
        }
    }
    
    CGRect rect = [self rectForNewEventOfType:type atDate:date];
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        rect.origin.x = currentPoint.x - rect.size.height/2;
        rect.origin.y = currentPoint.y - 20.0f;
        rect.size.width = rect.size.height;
        rect.size.height = 40.0f;
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        rect.origin.x = currentPoint.x - rect.size.height/2;
        rect.origin.y = currentPoint.y - 20.0f;
        rect.size.width = rect.size.height;
        rect.size.height = 40.0f;
    }
    self.interactiveCell.frame = rect;
    [self addSubview:self.interactiveCell];
    self.interactiveCell.hidden = NO;
    
    return YES;
}

- (BOOL)beginMovingEventOfType:(MGCEventType)type atIndexPath:(NSIndexPath*)path  withPoint:(CGPoint)currentPoint
{
    if (!self.canMoveEvents) return NO;
    
    UICollectionView *view = (type == MGCTimedEventType) ? self.timedEventsView : self.allDayEventsView;
    NSDate *date = [self dateFromDayOffset:path.section];
    
    if ([self.dataSource respondsToSelector:@selector(dayPlannerView:shouldStartMovingEventOfType:atIndex:date:)]) {
        if (![self.dataSource dayPlannerView:self shouldStartMovingEventOfType:type atIndex:path.item date:date]) {
            
            MGCEventCell *cell = (MGCEventCell*)[view cellForItemAtIndexPath:path];
            [self bounceAnimateCell:cell];
            return NO;
        }
    }
    
    self.movingEventType = type;
    self.movingEventIndex = path.item;
    
    self.isInteractiveCellForNewEvent = NO;
    self.interactiveCellType = type;
    
    MGCEventCell *cell = (MGCEventCell*)[view cellForItemAtIndexPath:path];
    MGCEventView *eventView = cell.eventView;
    
    // copy the cell
    self.interactiveCell = [[MGCInteractiveEventView alloc]initWithFrame:CGRectZero];
    self.interactiveCell.eventView = [eventView copy];
    
    // adjust the frame
    CGRect frame = [self convertRect:cell.frame fromView:view];
    if (type == MGCTimedEventType) {
        frame.size.width = self.dayColumnSize.width;
    }
    //frame.size.width = cell.frame.size.width; // TODO: this is wrong for all day events
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        frame.origin.x = currentPoint.x - cell.frame.size.width/2;
        frame.origin.y = currentPoint.y - 20.0f;
        frame.size.width = cell.frame.size.width;
        frame.size.height = 40.0f;
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        frame.origin.x = currentPoint.x - cell.frame.size.width/2;
        frame.origin.y = currentPoint.y - 20.0f;
        frame.size.width = cell.frame.size.width;
        frame.size.height = 40.0f;
    }
    self.interactiveCell.frame = frame;
    self.interactiveCellDate = [self dateAtPoint:self.interactiveCell.frame.origin rounded:YES];
    self.movingEventDate = self.interactiveCellDate;
    
    // record the height of the cell (this is necessary when we move back from AllDayEventType to TimedEventType
    self.interactiveCellTimedEventHeight = (type == MGCTimedEventType ? frame.size.height : self.hourSlotHeight);
    
    self.acceptsTarget = YES;
    //[self.interactiveCell didTransitionToEventType:type];  // TODO: fix
    
    //self.interactiveCell.selected = YES;
    
    [self addSubview:self.interactiveCell];
    self.interactiveCell.hidden = NO;
    
    return YES;
}

- (void)updateMovingCellAtPoint:(CGPoint)point
{
    CGPoint ptDayColumnsView = [self convertPoint:point toView:self.dayColumnsView];
    CGPoint ptEventsView = [self.timedEventsView convertPoint:point fromView:self];
    
    NSUInteger section = ptDayColumnsView.x / self.dayColumnSize.width;
    CGPoint origin = CGPointMake(section * self.dayColumnSize.width, ptDayColumnsView.y);
    origin = [self convertPoint:origin fromView:self.dayColumnsView];
    
    CGSize size = self.interactiveCell.frame.size; // cell size
    
    MGCEventType type = MGCTimedEventType;
    if (self.showsAllDayEvents && point.y < CGRectGetMinY(self.timedEventsView.frame)) {
        type = MGCAllDayEventType;
    }
    
    BOOL didTransition = type != self.interactiveCellType;
    
    self.interactiveCellType = type;
    
    self.acceptsTarget = YES;
    
    NSDate *date = [self dateAtPoint:self.interactiveCell.frame.origin rounded:YES];
    self.interactiveCellDate = date;
    
    if (self.isInteractiveCellForNewEvent) {
        if ([self.dataSource respondsToSelector:@selector(dayPlannerView:canCreateNewEventOfType:atDate:)]) {
            if (date && ![self.dataSource dayPlannerView:self canCreateNewEventOfType:type atDate:date]) {
                self.acceptsTarget = NO;
            }
        }
    }
    else {
        if ([self.dataSource respondsToSelector:@selector(dayPlannerView:canMoveEventOfType:atIndex:date:toType:date:)]) {
            if (date && ![self.dataSource dayPlannerView:self canMoveEventOfType:self.movingEventType atIndex:self.movingEventIndex date:self.movingEventDate toType:type date:date]) {
                self.acceptsTarget = NO;
            }
        }
    }
    
    self.interactiveCell.forbiddenSignVisible = !self.acceptsTarget;
    
    if (self.interactiveCellType == MGCTimedEventType) {
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
            size.height = self.interactiveCellTimedEventHeight;
            // constraint position
            ptEventsView.x -= self.interactiveCellTouchPoint.x;
            ptEventsView.x = fmaxf(ptEventsView.x, self.eventsViewInnerMargin);
            ptEventsView.x = fminf(ptEventsView.x, self.timedEventsView.contentSize.width - self.eventsViewInnerMargin);
            
            origin.x = [self convertPoint:ptEventsView fromView:self.timedEventsView].x;
            origin.x = fmaxf(origin.x, self.timedEventsView.frame.origin.x);
            
            self.timeRowsView.timeMark = [self timeFromOffset:(ptEventsView.x - floorf(ptEventsView.x/self.dayColumnSize.width)*self.dayColumnSize.width) rounding:0];
        }else{
            size.height = self.interactiveCellTimedEventHeight;
            
            // constraint position
            ptEventsView.y -= self.interactiveCellTouchPoint.y;
            ptEventsView.y = fmaxf(ptEventsView.y, self.eventsViewInnerMargin);
            ptEventsView.y = fminf(ptEventsView.y, self.timedEventsView.contentSize.height - self.eventsViewInnerMargin);
            
            origin.y = [self convertPoint:ptEventsView fromView:self.timedEventsView].y;
            origin.y = fmaxf(origin.y, self.timedEventsView.frame.origin.y);
            
            self.timeRowsView.timeMark = [self timeFromOffset:ptEventsView.y rounding:0];
        }
    }
    else {
        size.height = self.allDayEventCellHeight;
        origin.y = self.allDayEventsView.frame.origin.y; // top of the view
    }
    
    CGRect cellFrame = self.interactiveCell.frame;
    
    NSTimeInterval animationDur = (origin.x != cellFrame.origin.x) ? .02 : .15;
    
    cellFrame.origin = origin;
    cellFrame.size = size;
    
    NSMutableArray *usersArray = [[NSMutableArray alloc] init];
    NSMutableArray *aircraftArray = [[NSMutableArray alloc] init];
    NSMutableArray *classroomsArray = [[NSMutableArray alloc] init];
    
    NSError *error;
    NSManagedObjectContext *context = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
    NSEntityDescription *entityDesc = [NSEntityDescription entityForName:@"Users" inManagedObjectContext:context];
    // load the remaining lesson groups
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:entityDesc];
    NSArray *objects = [context executeFetchRequest:request error:&error];
    if (objects == nil) {
    } else if (objects.count == 0) {
    } else {
        NSMutableArray *tempUsers= [NSMutableArray arrayWithArray:objects];
        // root groups have sub-groups & no lessons and sub-groups have lessons and no sub-groups
        NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"lastName" ascending:YES];
        NSArray *sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
        NSArray *sortedUsers = [tempUsers sortedArrayUsingDescriptors:sortDescriptors];
        for (Users *users in sortedUsers) {
            BOOL isExit = NO;
            for (Users *userToCheck in usersArray) {
                if ([userToCheck.userID integerValue] == [users.userID integerValue]) {
                    isExit = YES;
                    break;
                }
            }
            if (!isExit) {
                [usersArray addObject:users];
            }
        }
    }
    
    entityDesc = [NSEntityDescription entityForName:@"Aircraft" inManagedObjectContext:context];
    request = [[NSFetchRequest alloc] init];
    [request setEntity:entityDesc];
    objects = [context executeFetchRequest:request error:&error];
    if (objects == nil) {
    } else if (objects.count == 0) {
    } else {
        NSMutableArray *tempAircrafts = [NSMutableArray arrayWithArray:objects];
        // root groups have sub-groups & no lessons and sub-groups have lessons and no sub-groups
        NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"valueForSort" ascending:NO];
        NSArray *sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
        NSArray *sortedAircrafts = [tempAircrafts sortedArrayUsingDescriptors:sortDescriptors];
        for (Aircraft *aircraft in sortedAircrafts) {
            [aircraftArray addObject:aircraft];
        }
    }
    
    [classroomsArray addObject:@"Cirrus Room"];
    [classroomsArray addObject:@"Cessna Room"];
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        
        CGFloat originXOflimited = 115;
        CGFloat originYOflimited = self.bounds.size.height - 40;
        
        if (point.y >= 115 && point.y <= (self.timedEventsView.frame.origin.y + 60)) {
            originXOflimited = self.timedEventsView.frame.origin.y;
            originYOflimited = self.timedEventsView.frame.origin.y;
        }else if (point.y >= (self.timedEventsView.frame.origin.y + 60) && point.y <= (self.timedEventsView.frame.origin.y + 100 + usersArray.count * 40.0f)){
            originXOflimited = (self.timedEventsView.frame.origin.y + 80)<115?115:(self.timedEventsView.frame.origin.y + 80);
            originYOflimited = self.timedEventsView.frame.origin.y + 40 + usersArray.count * 40.0f;
        }else if (point.y >= (self.timedEventsView.frame.origin.y + 100 + usersArray.count * 40.0f) && point.y <= (self.timedEventsView.frame.origin.y + 140 + usersArray.count * 40.0f + aircraftArray.count*40.0f)){
            originXOflimited = self.timedEventsView.frame.origin.y + 120 + usersArray.count * 40.0f;
            originYOflimited = self.timedEventsView.frame.origin.y + 80 + usersArray.count * 40.0f + aircraftArray.count*40.0f;
        }else if (point.y >= (self.timedEventsView.frame.origin.y + 140 + usersArray.count * 40.0f + aircraftArray.count*40.0f)){
            originXOflimited = self.timedEventsView.frame.origin.y + 160 + usersArray.count * 40.0f + aircraftArray.count*40.0f;
            originYOflimited = self.timedEventsView.frame.origin.y + 120 + usersArray.count * 40.0f + aircraftArray.count*40.0f + classroomsArray.count*40.0f;
        }
        
        cellFrame.origin.x =fminf(self.bounds.size.width - self.interactiveCell.frame.size.width, fmaxf(0, point.x - self.interactiveCell.frame.size.width/2));
        cellFrame.origin.y = fminf(originYOflimited, fmaxf(originXOflimited, point.y - 20.0f));
        cellFrame.size.width = self.interactiveCell.frame.size.width;
        cellFrame.size.height = 40.0f;
        
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        
        CGFloat originXOflimited = 115;
        CGFloat originYOflimited = self.bounds.size.height - 40;
        
        if (point.y >= 115 && point.y <= (self.timedEventsView.frame.origin.y + 60)) {
            originXOflimited = self.timedEventsView.frame.origin.y;
            originYOflimited = self.timedEventsView.frame.origin.y;
        }else if (point.y >= (self.timedEventsView.frame.origin.y + 60) && point.y <= (self.timedEventsView.frame.origin.y + 100 + usersArray.count * 40.0f)){
            originXOflimited = (self.timedEventsView.frame.origin.y + 80)<115?115:(self.timedEventsView.frame.origin.y + 80);
            originYOflimited = self.timedEventsView.frame.origin.y + 40 + usersArray.count * 40.0f;
        }else if (point.y >= (self.timedEventsView.frame.origin.y + 100 + usersArray.count * 40.0f) && point.y <= (self.timedEventsView.frame.origin.y + 140 + usersArray.count * 40.0f + aircraftArray.count*40.0f)){
            originXOflimited = self.timedEventsView.frame.origin.y + 120 + usersArray.count * 40.0f;
            originYOflimited = self.timedEventsView.frame.origin.y + 80 + usersArray.count * 40.0f + aircraftArray.count*40.0f;
        }else if (point.y >= (self.timedEventsView.frame.origin.y + 140 + usersArray.count * 40.0f + aircraftArray.count*40.0f)){
            originXOflimited = self.timedEventsView.frame.origin.y + 160 + usersArray.count * 40.0f + aircraftArray.count*40.0f;
            originYOflimited = self.timedEventsView.frame.origin.y + 120 + usersArray.count * 40.0f + aircraftArray.count*40.0f + classroomsArray.count*40.0f;
        }
        
        cellFrame.origin.x =fminf(self.bounds.size.width - self.interactiveCell.frame.size.width, fmaxf(0, point.x - self.interactiveCell.frame.size.width/2));
        cellFrame.origin.y = fminf(originYOflimited, fmaxf(originXOflimited, point.y - 20.0f));
        cellFrame.size.width = self.interactiveCell.frame.size.width;
        cellFrame.size.height = 40.0f;
    }
    [UIView animateWithDuration:animationDur delay:0 options:/*UIViewAnimationOptionBeginFromCurrentState|*/UIViewAnimationOptionCurveEaseIn animations:^{
        self.interactiveCell.frame = cellFrame;
    } completion:^(BOOL finished) {
        if (didTransition) {
            [self.interactiveCell.eventView didTransitionToEventType:self.interactiveCellType];
        }
    }];
}

// point in self coordinates
- (void)moveInteractiveCellAtPoint:(CGPoint)point
{
    CGRect rightScrollRect = CGRectMake(CGRectGetMaxX(self.bounds) - 30, 0, 30, self.bounds.size.height);
    CGRect leftScrollRect = CGRectMake(0, 0, self.timeColumnWidth + 20, self.bounds.size.height);
    CGRect downScrollRect = CGRectMake(self.timeColumnWidth, CGRectGetMaxY(self.bounds) - 30, self.bounds.size.width, 30);
    CGRect upScrollRect = CGRectMake(self.timeColumnWidth, self.timedEventsView.frame.origin.y, self.bounds.size.width, 30);
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        leftScrollRect = CGRectMake(0, 0, 0 + 20, self.bounds.size.height);
        downScrollRect = CGRectMake(0, CGRectGetMaxY(self.bounds) - 30, self.bounds.size.width, 30);
        upScrollRect = CGRectMake(0, self.timedEventsView.frame.origin.y, self.bounds.size.width, 30);
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        leftScrollRect = CGRectMake(0, 0, 0 + 20, self.bounds.size.height);
        downScrollRect = CGRectMake(0, CGRectGetMaxY(self.bounds) - 30, self.bounds.size.width, 30);
        upScrollRect = CGRectMake(0, self.timedEventsView.frame.origin.y, self.bounds.size.width, 30);
    }
    
    if (self.dragTimer) {
        [self.dragTimer invalidate];
        self.dragTimer = nil;
    }
    if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        if (point.x < 0) {
            point.x = 0;
        }
    }
    // speed depends on day column width
    NSTimeInterval ti = (self.dayColumnSize.width / 100.) * 0.05;
    
    if (CGRectContainsPoint(rightScrollRect, point)) {
        // progressive speed
        
        ti /= (point.x - rightScrollRect.origin.x) / 30;
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
            ti = (self.dayColumnSize.height / 100.) * 0.05;
            ti /= (point.y - rightScrollRect.origin.x) * 30;
        }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
            
        }
        self.dragTimer = [NSTimer scheduledTimerWithTimeInterval:ti target:self selector:@selector(dragTimerDidFire:) userInfo:@{@"direction": @(ScrollDirectionLeft)} repeats:YES];
    }
    else if (CGRectContainsPoint(leftScrollRect, point)) {
        ti /= (CGRectGetMaxX(leftScrollRect) - point.x) / 30;
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
            ti = (self.dayColumnSize.height / 100.) * 0.05;
            ti /= (CGRectGetMaxX(leftScrollRect) - point.y) * 30;
        }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
            
        }
        self.dragTimer = [NSTimer scheduledTimerWithTimeInterval:ti target:self selector:@selector(dragTimerDidFire:) userInfo:@{@"direction": @(ScrollDirectionRight)} repeats:YES];
    }
    else if (CGRectContainsPoint(downScrollRect, point)) {
        self.dragTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(dragTimerDidFire:) userInfo:@{@"direction": @(ScrollDirectionDown)} repeats:YES];
    }
    else if (CGRectContainsPoint(upScrollRect, point)) {
        self.dragTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(dragTimerDidFire:) userInfo:@{@"direction": @(ScrollDirectionUp)} repeats:YES];
    }
    
    [self updateMovingCellAtPoint:point];
}

- (void)dragTimerDidFire:(NSTimer*)timer
{
    //NSLog(@"dragTimerDidFire");
    
    ScrollDirection direction = [[timer.userInfo objectForKey:@"direction"] unsignedIntegerValue];
    
    CGPoint offset = self.timedEventsView.contentOffset;
    if (direction == ScrollDirectionLeft) {
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
            offset.x += 20;
            offset.x = fminf(offset.x, self.timedEventsView.contentSize.width - self.timedEventsView.bounds.size.width);
        }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
            offset.x += self.dayColumnSize.width;
            offset.x = fminf(offset.x, self.timedEventsView.contentSize.width - self.timedEventsView.bounds.size.width);
        }else{
            offset.x += self.dayColumnSize.width;
            offset.x = fminf(offset.x, self.timedEventsView.contentSize.width - self.timedEventsView.bounds.size.width);
        }
    }
    else if (direction == ScrollDirectionRight) {
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
            offset.x -= 20;
            offset.x = fmaxf(offset.x, 0);
        }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
            offset.x -= self.dayColumnSize.width;
            offset.x = fmaxf(offset.x, 0);
        }else{
            offset.x -= self.dayColumnSize.width;
            offset.x = fmaxf(offset.x, 0);
        }
    }
    else if (direction == ScrollDirectionDown) {
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
            
        }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
            offset.y += 20;
            offset.y = fminf(offset.y, self.timedEventsView.contentSize.height - self.timedEventsView.bounds.size.height);
        }else{
            offset.y += 20;
            offset.y = fminf(offset.y, self.timedEventsView.contentSize.height - self.timedEventsView.bounds.size.height);
        }
    }
    else if (direction == ScrollDirectionUp) {
        if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
            
        }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
            offset.y -= 20;
            offset.y = fmaxf(offset.y, 0);
        }else{
            offset.y -= 20;
            offset.y = fmaxf(offset.y, 0);
        }
    }
    
    // This test is important, because if we can't move (at the start or end of content),
    // setContentOffset will have no effect, and will not send scrollViewDidEndScrollingAnimation:
    // so we won't get any chance to reset everything
    if (!CGPointEqualToPoint(self.timedEventsView.contentOffset, offset)) {
        [self setTimedEventsViewContentOffset:offset animated:NO completion:nil];
        
        // scrolling will be enabled again in scrollViewDidEndScrolling:
    }
}

- (void)endInteraction
{
    if (self.interactiveCell) {
        self.interactiveCell.hidden = YES;
        [self.interactiveCell removeFromSuperview];
        self.interactiveCell = nil;
        
        [self.dragTimer invalidate];
        self.dragTimer = nil;
    }
    self.interactiveCellTouchPoint = CGPointZero;
    self.timeRowsView.timeMark = 0;
}

#pragma mark - Reloading content

// this is called whenever we recenter the views during scrolling
// or when the number of visible days or the date range changes
- (void)reloadCollectionViews
{
    //NSLog(@"reloadCollectionsViews");
    if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        _hourSlotHeight = ([UIScreen mainScreen].bounds.size.width-200) / (_numberOfVisibleDays * NSMaxRange(self.hourRange));
    }
    
    [self deselectEventWithDelegate:YES];
    
    CGSize dayColumnSize = self.dayColumnSize;
    
    self.timedEventsViewLayout.dayColumnSize = dayColumnSize;
    
    CGSize dayColumnSizeMe = CGSizeMake(self.dayColumnSize.width, 40.0f);
    self.timedEventsMeViewLayout.dayColumnSize = dayColumnSizeMe;
    self.allDayEventsViewLayout.dayColumnWidth = dayColumnSize.width;
    self.allDayEventsViewLayout.eventCellHeight = self.allDayEventCellHeight;
    
    [self.dayColumnsView reloadData];
    [self.timedEventsView reloadData];
    [self.timedEventsMeView reloadData];
    [self.allDayEventsView reloadData];
    
    if (!self.controllingScrollView) {  // only if we're not scrolling
        dispatch_async(dispatch_get_main_queue(), ^{ [self setupSubviews]; });
    }
}

// public
- (void)reloadAllEvents
{
    //NSLog(@"reloadAllEvents");
    
    [self deselectEventWithDelegate:YES];
    
    [self.allDayEventsView reloadData];
    [self.timedEventsView reloadData];
    [self.timedEventsMeView reloadData];
    
    if (!self.controllingScrollView) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setupSubviews]; });
    }
    
    [self.loadedDaysRange enumerateDaysWithCalendar:self.calendar usingBlock:^(NSDate *date, BOOL *stop) {
        [self refreshEventMarkForColumnAtDate:date];
    }];
}

- (void)refreshEventMarkForColumnAtDate:(NSDate*)date
{
    NSInteger section = [self dayOffsetFromDate:date];
    NSIndexPath *path = [NSIndexPath indexPathForItem:0 inSection:section];
    if (self.numberOfLoadedDays > path.section) {
        MGCDayColumnCell *cell = (MGCDayColumnCell*)[self.dayColumnsView cellForItemAtIndexPath:path];
        if (cell) {
            NSUInteger count = [self numberOfAllDayEventsAtDate:date] + [self numberOfTimedEventsAtDate:date];
            if (count > 0) {
                cell.accessoryTypes |= MGCDayColumnCellAccessoryDot;
            }
            else {
                cell.accessoryTypes &= ~MGCDayColumnCellAccessoryDot;
            }
        }
    }else{
        NSLog(@"crash issue");
    }
}

// public
- (void)reloadEventsAtDate:(NSDate*)date
{
    //NSLog(@"reloadEventsAtDate %@", date);
    
    [self deselectEventWithDelegate:YES];
    
    if ([self.loadedDaysRange containsDate:date]) {
        
        // we have to reload everything for the all-day events view because some events might span several days
        [self.allDayEventsView reloadData];
        
        if (!self.controllingScrollView) {
            // only if we're not scrolling
            [self setupSubviews];
        }
        NSInteger section = [self dayOffsetFromDate:date];
        
        if (section < self.numberOfLoadedDays) {
            // for some reason, reloadSections: does not work properly. See comment for ignoreNextInvalidation
            self.timedEventsViewLayout.ignoreNextInvalidation = YES;
            self.timedEventsMeViewLayout.ignoreNextInvalidation = YES;
            [self.timedEventsView reloadData];
            [self.timedEventsMeView reloadData];
            if (section > 0) {
                MGCTimedEventsViewLayoutInvalidationContext *context = [MGCTimedEventsViewLayoutInvalidationContext new];
                context.invalidatedSections = (NSMutableIndexSet*) [NSIndexSet indexSetWithIndex:section];
                [self.timedEventsView.collectionViewLayout invalidateLayoutWithContext:context];
                
                MGCTimedEventsMeViewLayoutInvalidationContext *contextMe = [MGCTimedEventsMeViewLayoutInvalidationContext new];
                contextMe.invalidatedSections = (NSMutableIndexSet*)[NSIndexSet indexSetWithIndex:section];
                [self.timedEventsMeView.collectionViewLayout invalidateLayoutWithContext:contextMe];
                
            }
            
            [self refreshEventMarkForColumnAtDate:date];
        }
    }
}

// public
- (void)reloadDimmedTimeRanges
{
    [self.dimmedTimeRangesCache removeAllObjects];
    
    MGCTimedEventsViewLayoutInvalidationContext *context = [MGCTimedEventsViewLayoutInvalidationContext new];
    context.invalidatedSections = (NSMutableIndexSet*)[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.numberOfLoadedDays)];
    context.invalidateEventCells = NO;
    context.invalidateDimmingViews = YES;
    [self.timedEventsView.collectionViewLayout invalidateLayoutWithContext:context];
    
    MGCTimedEventsMeViewLayoutInvalidationContext *contextMe = [MGCTimedEventsMeViewLayoutInvalidationContext new];
    contextMe.invalidatedSections = (NSMutableIndexSet*)[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.numberOfLoadedDays)];
    contextMe.invalidateEventCells = NO;
    contextMe.invalidateDimmingViews = YES;
    [self.timedEventsMeView.collectionViewLayout invalidateLayoutWithContext:context];
    
}

// public
- (void)insertEventOfType:(MGCEventType)type withDateRange:(MGCDateRange*)range
{
    NSInteger start = MAX([self dayOffsetFromDate:range.start], 0);
    NSInteger end = MIN([self dayOffsetFromDate:range.end], self.numberOfLoadedDays);
    
    NSMutableArray *indexPaths = [NSMutableArray array];
    for (NSInteger section = start; section <= end; section++) {
        NSDate *date = [self dateFromDayOffset:section];
        NSInteger num = [self.dataSource dayPlannerView:self numberOfEventsOfType:type atDate:date];
        NSIndexPath *path = [NSIndexPath indexPathForItem:num inSection:section];
        
        [indexPaths addObject:path];
    }
    
    
    if (type == MGCAllDayEventType) {
        //[self.allDayEventsView reloadSections:[NSIndexSet indexSetWithIndex:section]];
        [self.allDayEventsView insertItemsAtIndexPaths:indexPaths];
    }
    else if (type == MGCTimedEventType) {
        //[self.timedEventsView reloadSections:[NSIndexSet indexSetWithIndex:section]];
        [self.timedEventsView insertItemsAtIndexPaths:indexPaths];
        [self.timedEventsMeView insertItemsAtIndexPaths:indexPaths];
    }
}

// public
- (BOOL)setActivityIndicatorVisible:(BOOL)visible forDate:(NSDate*)date
{
    if (visible) {
        [self.loadingDays addObject:date];
    }
    else {
        [self.loadingDays removeObject:date];
    }
    
    if ([self.loadedDaysRange containsDate:date]) {
        NSIndexPath *path = [NSIndexPath indexPathForItem:0 inSection:[self dayOffsetFromDate:date]];
        if (self.numberOfLoadedDays > path.section) {
            MGCDayColumnCell *cell = (MGCDayColumnCell*)[self.dayColumnsView cellForItemAtIndexPath:path];
            if (cell) {
                [cell setActivityIndicatorVisible:visible];
                return YES;
            }
        }else{
            NSLog(@"crash issue");
        }
    }
    return NO;
}

- (void)setupSubviews
{
    CGFloat allDayEventsViewHeight = 2;
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        
        if (self.showsAllDayEvents) {
            allDayEventsViewHeight = fmaxf(self.allDayEventCellHeight + 4, self.allDayEventsView.contentSize.height);
            allDayEventsViewHeight = fminf(allDayEventsViewHeight, self.allDayEventCellHeight * 2.5 + 6);
        }
        if ([AppDelegate sharedDelegate].preallDayEventsViewHeight != allDayEventsViewHeight) {
            [AppDelegate sharedDelegate].deviationOfResources = allDayEventsViewHeight - [AppDelegate sharedDelegate].preallDayEventsViewHeight;
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_RESOURCES_POSITION object:nil userInfo:nil];
            [AppDelegate sharedDelegate].preallDayEventsViewHeight = allDayEventsViewHeight;
        }
        
        CGFloat timedEventsViewHeight = self.bounds.size.height - self.dayHeaderHeight;
        
        self.backgroundView.frame = CGRectMake(0, self.dayHeaderHeight, self.bounds.size.width, timedEventsViewHeight);
        if (!self.backgroundView.superview) {
            [self addSubview:self.backgroundView];
        }
        
        // x pos and width are adjusted in order to "hide" left and rigth borders
        self.allDayEventsBackgroundView.frame = CGRectMake(-1, self.dayHeaderHeight, self.bounds.size.width + 2,0);
        if (!self.allDayEventsBackgroundView.superview) {
            [self addSubview:self.allDayEventsBackgroundView];
        }
        
        self.allDayEventsView.frame = CGRectMake(0, self.dayHeaderHeight, self.bounds.size.width, 0);
        if (!self.allDayEventsView.superview) {
            [self addSubview:self.allDayEventsView];
        }
        
        CGFloat tmpContentOffsetY = self.timedEventsView.contentOffset.y;
        CGFloat tmpContentOffsetx = self.timedEventsView.contentOffset.x;
        CGFloat timedEventViewYPosition = self.dayHeaderHeight+25;
        if (self.timedEventsView == nil) {
            timedEventViewYPosition = self.dayHeaderHeight+25;
        }else{
            if (self.timedEventsView.frame.origin.y > (self.dayHeaderHeight+25)) {
                timedEventViewYPosition = self.dayHeaderHeight+25;
            }else{
                if (self.timeHorizontalScrollView.contentOffset.y == 0) {
                    timedEventViewYPosition = self.dayHeaderHeight+25;
                }else{
                    timedEventViewYPosition = self.timedEventsView.frame.origin.y;
                }
            }
        }
        self.timedEventsView.frame = CGRectMake(0, timedEventViewYPosition, self.bounds.size.width, timedEventsViewHeight-25);
        self.timedEventsMeView.frame = CGRectMake(0, self.dayHeaderHeight + 25, self.bounds.size.width, 40);
        self.maskViewForHideMeOnTimedEventsView.frame = CGRectMake(0, timedEventViewYPosition, self.bounds.size.width, 40);
        if (self.heightOfScrollViewFromResources > (timedEventsViewHeight-25)) {
            self.timedEventsView.frame = CGRectMake(0, timedEventViewYPosition, self.bounds.size.width, self.heightOfScrollViewFromResources);
        }
        self.timedEventsView.contentOffset = CGPointMake(tmpContentOffsetx, tmpContentOffsetY);
        self.timedEventsMeView.contentOffset = CGPointMake(self.timedEventsMeView.contentOffset.x, 0);
        self.timeScrollView.contentSize = CGSizeMake(self.dayColumnSize.width, timedEventsViewHeight);
        if (!self.timedEventsView.superview) {
            [self addSubview:self.timedEventsView];
            //self.timedEventsView.transform = CGAffineTransformMakeRotation(-90 * M_PI / 180.0);
        }
        if (!self.maskViewForHideMeOnTimedEventsView.superview) {
            [self addSubview:self.maskViewForHideMeOnTimedEventsView];
        }
        
        CGFloat contentOffsetYOfTimeHorizontalSV = self.timeHorizontalScrollView.contentOffset.y;
        self.timeHorizontalScrollView.contentSize = CGSizeMake(self.dayColumnSize.width, timedEventsViewHeight);
        if ((timedEventsViewHeight-25)<self.heightOfScrollViewFromResources) {
            self.timeHorizontalScrollView.contentSize = CGSizeMake(self.dayColumnSize.width, self.heightOfScrollViewFromResources+25);
        }
        self.timeColumnsView.frame = CGRectMake(0, 0, self.timeHorizontalScrollView.contentSize.width, self.timeHorizontalScrollView.contentSize.height);
        [self.timeColumnsView reDrawFromOtherView];
        self.timeHorizontalScrollView.frame = CGRectMake(0, self.dayHeaderHeight, self.bounds.size.width, timedEventsViewHeight);
        if (!self.timeHorizontalScrollView.superview) {
            [self addSubview:self.timeHorizontalScrollView];
        }
        self.timeHorizontalScrollView.userInteractionEnabled = NO;
        
        
        if (!self.timedEventsMeView.superview) {
            [self addSubview:self.timedEventsMeView];
        }
        self.timedEventsMeView.scrollEnabled = NO;
        
        self.timeLabelCV.frame = CGRectMake(0, self.dayHeaderHeight, self.bounds.size.width, 25.0f);
        if (!self.timeLabelCV.superview) {
            [self addSubview:self.timeLabelCV];
        }
        
        self.timeRowsView.frame = CGRectMake(0, 0, self.timeScrollView.contentSize.width, self.timeScrollView.contentSize.height);
        self.timeScrollView.frame = CGRectMake(0, self.dayHeaderHeight, self.bounds.size.width, timedEventsViewHeight);
        if (!self.timeScrollView.superview) {
            [self addSubview:self.timeScrollView];
        }
        self.timeRowsView.showsCurrentTime = [self.visibleDays containsDate:[NSDate date]];
        
        self.timeScrollView.userInteractionEnabled = NO;
        
        self.dayColumnsView.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
        if (!self.dayColumnsView.superview) {
            [self addSubview:self.dayColumnsView];
        }
        self.dayColumnsView.userInteractionEnabled = NO;
        
        self.viewToGetDateOfDayColumnView.frame = CGRectMake(0, 0, self.bounds.size.width, self.dayHeaderHeight);
        if (self.viewToGetDateOfDayColumnView.superview) {
            [self.viewToGetDateOfDayColumnView removeFromSuperview];
        }
        
        // make sure collection views are synchronized
        self.dayColumnsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, 0);
        self.timeScrollView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x - floorf(self.timedEventsView.contentOffset.x/self.dayColumnSize.width) * self.dayColumnSize.width ,0);
        self.allDayEventsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, self.allDayEventsView.contentOffset.y);
        self.timeHorizontalScrollView.contentOffset = CGPointMake(0, contentOffsetYOfTimeHorizontalSV);
        if (self.dragTimer == nil && self.interactiveCell && self.interactiveCellDate) {
            CGRect frame = self.interactiveCell.frame;
            frame.origin = [self offsetFromDate:self.interactiveCellDate eventType:self.interactiveCellType];
            frame.size.width = self.dayColumnSize.width;
        }
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        if (self.showsAllDayEvents) {
            allDayEventsViewHeight = fmaxf(self.allDayEventCellHeight + 4, self.allDayEventsView.contentSize.height);
            allDayEventsViewHeight = fminf(allDayEventsViewHeight, self.allDayEventCellHeight * 2.5 + 6);
        }
        
        CGFloat timedEventViewTop = self.dayHeaderHeight + allDayEventsViewHeight + 26.0f;
        CGFloat timedEventsViewHeight = self.bounds.size.height - timedEventViewTop;
        
        self.backgroundView.frame = CGRectMake(0, self.dayHeaderHeight + allDayEventsViewHeight + 25.0f, self.bounds.size.width, timedEventsViewHeight);
        if (!self.backgroundView.superview) {
            [self addSubview:self.backgroundView];
        }
        
        
        CGFloat timedEventViewYPosition = self.dayHeaderHeight+allDayEventsViewHeight + 26.0f;
        if (self.timedEventsView == nil) {
            timedEventViewYPosition = self.dayHeaderHeight+allDayEventsViewHeight + 26.0f;
        }else{
            if (self.timedEventsView.frame.origin.y > (self.dayHeaderHeight+allDayEventsViewHeight + 26.0f)) {
                timedEventViewYPosition = self.dayHeaderHeight+allDayEventsViewHeight + 26.0f;
            }else{
                if (self.timeHorizontalScrollView.contentOffset.y == 0) {
                    timedEventViewYPosition = self.dayHeaderHeight+allDayEventsViewHeight + 26.0f;
                }else{
                    timedEventViewYPosition = self.timedEventsView.frame.origin.y;
                }
            }
        }
        
        self.timedEventsView.frame = CGRectMake(0, timedEventViewYPosition, self.bounds.size.width, timedEventsViewHeight);
        self.timedEventsMeView.frame = CGRectMake(0, timedEventViewTop, self.bounds.size.width, 40);
        self.maskViewForHideMeOnTimedEventsView.frame = CGRectMake(0, timedEventViewYPosition, self.bounds.size.width, 40);
        if (self.heightOfScrollViewFromResources > (timedEventsViewHeight-25)) {
            self.timedEventsView.frame = CGRectMake(0, timedEventViewYPosition, self.bounds.size.width, self.heightOfScrollViewFromResources);
        }
        if (!self.timedEventsView.superview) {
            [self addSubview:self.timedEventsView];
        }
        if (!self.maskViewForHideMeOnTimedEventsView.superview) {
            [self addSubview:self.maskViewForHideMeOnTimedEventsView];
        }
        
        CGFloat contentOffsetYOfTimeHorizontalSV = self.timeHorizontalScrollView.contentOffset.y;
        self.timeHorizontalScrollView.contentSize = CGSizeMake(self.bounds.size.width, timedEventsViewHeight);
        if (timedEventsViewHeight<self.heightOfScrollViewFromResources) {
            self.timeHorizontalScrollView.contentSize = CGSizeMake(self.bounds.size.width, self.heightOfScrollViewFromResources+25);
        }
        self.timeColumnsView.frame = CGRectMake(0, 0, self.timeHorizontalScrollView.contentSize.width, self.timeHorizontalScrollView.contentSize.height);
        [self.timeColumnsView reDrawFromOtherView];
        self.timeHorizontalScrollView.frame = CGRectMake(0, timedEventViewTop-25, self.bounds.size.width, timedEventsViewHeight+25);
        if (!self.timeHorizontalScrollView.superview) {
            [self addSubview:self.timeHorizontalScrollView];
        }
        self.timeHorizontalScrollView.userInteractionEnabled = NO;
        
        if (!self.timedEventsMeView.superview) {
            [self addSubview:self.timedEventsMeView];
        }
        self.timedEventsMeView.userInteractionEnabled = NO;
        
        self.timeLabelCV.frame = CGRectMake(0, self.dayHeaderHeight+allDayEventsViewHeight, self.bounds.size.width, 25.0f);
        if (!self.timeLabelCV.superview) {
            [self addSubview:self.timeLabelCV];
        }
        
        self.timeRowsView.frame = CGRectMake(0, 0, self.timeScrollView.contentSize.width, self.timeScrollView.contentSize.height);
        self.timeScrollView.frame = CGRectMake(0, timedEventViewTop, self.bounds.size.width, timedEventsViewHeight);
        if (self.timeScrollView.superview) {
            [self.timeScrollView removeFromSuperview];
        }
        self.timeRowsView.showsCurrentTime = [self.visibleDays containsDate:[NSDate date]];
        self.timeScrollView.userInteractionEnabled = NO;
        
        
        // x pos and width are adjusted in order to "hide" left and rigth borders
        self.allDayEventsBackgroundView.frame = CGRectMake(-1, self.dayHeaderHeight, self.bounds.size.width + 2, allDayEventsViewHeight);
        if (!self.allDayEventsBackgroundView.superview) {
            [self addSubview:self.allDayEventsBackgroundView];
        }
        self.allDayEventsView.frame = CGRectMake(0, self.dayHeaderHeight, self.bounds.size.width, allDayEventsViewHeight);
        if (!self.allDayEventsView.superview) {
            [self addSubview:self.allDayEventsView];
        }
        
        self.dayColumnsView.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
        if (!self.dayColumnsView.superview) {
            [self addSubview:self.dayColumnsView];
        }
        self.dayColumnsView.userInteractionEnabled = NO;
        
        self.viewToGetDateOfDayColumnView.frame = CGRectMake(0, 0, self.bounds.size.width, self.dayHeaderHeight);
        if (!self.viewToGetDateOfDayColumnView.superview) {
            [self addSubview:self.viewToGetDateOfDayColumnView];
        }
        
        self.dayColumnsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, 0);
        self.timeScrollView.contentOffset = CGPointMake(0, self.timedEventsView.contentOffset.y);
        self.allDayEventsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, self.allDayEventsView.contentOffset.y);
        self.timeHorizontalScrollView.contentOffset = CGPointMake(0, contentOffsetYOfTimeHorizontalSV);
        if (self.dragTimer == nil && self.interactiveCell && self.interactiveCellDate) {
            CGRect frame = self.interactiveCell.frame;
            frame.origin = [self offsetFromDate:self.interactiveCellDate eventType:self.interactiveCellType];
            frame.size.width = self.dayColumnSize.width;
            //self.interactiveCell.frame = frame;
            //self.interactiveCell.hidden = (self.interactiveCellType == MGCTimedEventType && !CGRectIntersectsRect(self.timedEventsView.frame, frame));
        }
        
        if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking && [AppDelegate sharedDelegate].preallDayEventsViewHeight != allDayEventsViewHeight) {
            [AppDelegate sharedDelegate].deviationOfResources = allDayEventsViewHeight - [AppDelegate sharedDelegate].preallDayEventsViewHeight;
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_RESOURCES_POSITION object:nil userInfo:nil];
            [AppDelegate sharedDelegate].preallDayEventsViewHeight = allDayEventsViewHeight;
            [self.dayColumnsView reloadData];
        }
        
    }else{
        if (self.showsAllDayEvents) {
            allDayEventsViewHeight = fmaxf(self.allDayEventCellHeight + 4, self.allDayEventsView.contentSize.height);
            allDayEventsViewHeight = fminf(allDayEventsViewHeight, self.allDayEventCellHeight * 2.5 + 6);
        }
        CGFloat timedEventViewTop = self.dayHeaderHeight + allDayEventsViewHeight;
        CGFloat timedEventsViewWidth = self.bounds.size.width - self.timeColumnWidth;
        CGFloat timedEventsViewHeight = self.bounds.size.height - (self.dayHeaderHeight + allDayEventsViewHeight);
        
        //self.backgroundView.frame = CGRectMake(0, self.dayHeaderHeight, self.bounds.size.width, self.bounds.size.height - self.dayHeaderHeight);
        self.backgroundView.frame = CGRectMake(self.timeColumnWidth, self.dayHeaderHeight + allDayEventsViewHeight, timedEventsViewWidth, timedEventsViewHeight);
        self.backgroundView.frame = CGRectMake(0, timedEventViewTop, self.bounds.size.width, timedEventsViewHeight);
        if (!self.backgroundView.superview) {
            [self addSubview:self.backgroundView];
        }
        
        // x pos and width are adjusted in order to "hide" left and rigth borders
        self.allDayEventsBackgroundView.frame = CGRectMake(-1, self.dayHeaderHeight, self.bounds.size.width + 2, allDayEventsViewHeight);
        if (!self.allDayEventsBackgroundView.superview) {
            [self addSubview:self.allDayEventsBackgroundView];
        }
        
        //    self.dayColumnsView.frame = CGRectMake(self.timeColumnWidth, 0, timedEventsViewWidth, self.bounds.size.height);
        //    if (!self.dayColumnsView.superview) {
        //        [self addSubview:self.dayColumnsView];
        //    }
        
        self.allDayEventsView.frame = CGRectMake(self.timeColumnWidth, self.dayHeaderHeight, timedEventsViewWidth, allDayEventsViewHeight);
        if (!self.allDayEventsView.superview) {
            [self addSubview:self.allDayEventsView];
        }
        
        self.timedEventsView.frame = CGRectMake(self.timeColumnWidth, timedEventViewTop, timedEventsViewWidth, timedEventsViewHeight);
        if (!self.timedEventsView.superview) {
            [self addSubview:self.timedEventsView];
        }
        
        self.timeScrollView.contentSize = CGSizeMake(self.bounds.size.width, self.dayColumnSize.height);
        self.timeRowsView.frame = CGRectMake(0, 0, self.timeScrollView.contentSize.width, self.timeScrollView.contentSize.height);
        
        self.timeScrollView.frame = CGRectMake(0, timedEventViewTop, self.bounds.size.width, timedEventsViewHeight);
        if (!self.timeScrollView.superview) {
            [self addSubview:self.timeScrollView];
        }
        
        self.timeRowsView.showsCurrentTime = [self.visibleDays containsDate:[NSDate date]];
        
        self.timeScrollView.userInteractionEnabled = NO;
        
        
        self.dayColumnsView.frame = CGRectMake(self.timeColumnWidth, 0, timedEventsViewWidth, self.bounds.size.height);
        if (!self.dayColumnsView.superview) {
            [self addSubview:self.dayColumnsView];
        }
        
        self.dayColumnsView.userInteractionEnabled = NO;
        //    self.timedEventsView.frame = CGRectMake(self.timeColumnWidth, timedEventViewTop, timedEventsViewWidth, timedEventsViewHeight);
        //    if (!self.timedEventsView.superview) {
        //        [self addSubview:self.timedEventsView];
        //    }
        self.viewToGetDateOfDayColumnView.frame = CGRectMake(0, 0, self.bounds.size.width, self.dayHeaderHeight);
        if (self.viewToGetDateOfDayColumnView.superview) {
            [self.viewToGetDateOfDayColumnView removeFromSuperview];
        }
        // make sure collection views are synchronized
        self.dayColumnsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, 0);
        self.timeScrollView.contentOffset = CGPointMake(0, self.timedEventsView.contentOffset.y);
        self.allDayEventsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x, self.allDayEventsView.contentOffset.y);
        
        if (self.dragTimer == nil && self.interactiveCell && self.interactiveCellDate) {
            CGRect frame = self.interactiveCell.frame;
            frame.origin = [self offsetFromDate:self.interactiveCellDate eventType:self.interactiveCellType];
            frame.size.width = self.dayColumnSize.width;
            self.interactiveCell.frame = frame;
            self.interactiveCell.hidden = (self.interactiveCellType == MGCTimedEventType && !CGRectIntersectsRect(self.timedEventsView.frame, frame));
        }
    }
    
    
    [self.allDayEventsView flashScrollIndicators];
    
    
}

#pragma mark - UIView

- (void)layoutSubviews
{
    //NSLog(@"layout subviews");
    
    [super layoutSubviews];
    
    CGSize dayColumnSize = self.dayColumnSize;
    
    self.timeRowsView.hourSlotHeight = self.hourSlotHeight;
    self.timeRowsView.timeColumnWidth = self.timeColumnWidth;
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        self.timeRowsView.timeColumnWidth = 0;
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
        self.timeRowsView.timeColumnWidth = 0;
    }
    self.timeRowsView.insetsHeight = self.eventsViewInnerMargin;
    
    self.timedEventsViewLayout.dayColumnSize = dayColumnSize;
    CGSize dayColumnSizeMe = CGSizeMake(self.dayColumnSize.width, 40.0f);
    self.timedEventsMeViewLayout.dayColumnSize = dayColumnSizeMe;
    self.allDayEventsViewLayout.dayColumnWidth = dayColumnSize.width;
    self.allDayEventsViewLayout.eventCellHeight = self.allDayEventCellHeight;
    
    [self setupSubviews];
    [self updateVisibleDaysRange];
}

#pragma mark - MGCTimeRowsViewDelegate

- (NSAttributedString*)timeRowsView:(MGCTimeRowsView *)view attributedStringForTimeMark:(MGCDayPlannerTimeMark)mark time:(NSTimeInterval)ti
{
    if ([self.delegate respondsToSelector:@selector(dayPlannerView:attributedStringForTimeMark:time:)]) {
        return [self.delegate dayPlannerView:self attributedStringForTimeMark:mark time:ti];
    }
    return nil;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView*)collectionView
{
    return self.numberOfLoadedDays;
}

// public
- (NSInteger)numberOfTimedEventsAtDate:(NSDate*)date
{
    NSInteger section = [self dayOffsetFromDate:date];
    return [self.timedEventsView numberOfItemsInSection:section];
}

// public
- (NSInteger)numberOfAllDayEventsAtDate:(NSDate*)date
{
    if (!self.showsAllDayEvents) return 0;
    
    NSInteger section = [self dayOffsetFromDate:date];
    return [self.allDayEventsView numberOfItemsInSection:section];
}

// public
- (NSArray*)visibleEventViewsOfType:(MGCEventType)type
{
    NSMutableArray *views = [NSMutableArray array];
    if (type == MGCTimedEventType) {
        NSArray *visibleCells = [self.timedEventsView visibleCells];
        for (MGCEventCell *cell in visibleCells) {
            [views addObject:cell.eventView];
        }
    }
    else if (type == MGCAllDayEventType) {
        NSArray *visibleCells = [self.allDayEventsView visibleCells];
        for (MGCEventCell *cell in visibleCells) {
            [views addObject:cell.eventView];
        }
    }
    return views;
}

- (MGCEventCell*)collectionViewCellForEventOfType:(MGCEventType)type atIndexPath:(NSIndexPath*)indexPath
{
    MGCEventCell *cell = nil;
    if (type == MGCTimedEventType) {
        cell = (MGCEventCell*)[self.timedEventsView cellForItemAtIndexPath:indexPath];
    }
    else if (type == MGCAllDayEventType) {
        cell = (MGCEventCell*)[self.allDayEventsView cellForItemAtIndexPath:indexPath];
    }
    return cell;
}
- (MGCEventCell*)collectionViewCellForEventMeOfType:(MGCEventType)type atIndexPath:(NSIndexPath*)indexPath
{
    MGCEventCell *cell = nil;
    if (type == MGCTimedEventType) {
        cell = (MGCEventCell*)[self.timedEventsMeView cellForItemAtIndexPath:indexPath];
    }
    else if (type == MGCAllDayEventType) {
        cell = (MGCEventCell*)[self.allDayEventsView cellForItemAtIndexPath:indexPath];
    }
    return cell;
}
- (NSInteger)collectionView:(UICollectionView*)collectionView numberOfItemsInSection:(NSInteger)section
{
    if (collectionView == self.timedEventsMeView) {
        NSDate *date = [self dateFromDayOffset:section];
        return [self.dataSource dayPlannerView:self numberOfEventsOfType:MGCTimedEventType atDate:date];
    }
    else if (collectionView == self.timedEventsView) {
        NSDate *date = [self dateFromDayOffset:section];
        return [self.dataSource dayPlannerView:self numberOfEventsOfType:MGCTimedEventType atDate:date];
    }
    else if (collectionView == self.allDayEventsView) {
        if (!self.showsAllDayEvents) return 0;
        NSDate *date = [self dateFromDayOffset:section];
        return [self.dataSource dayPlannerView:self numberOfEventsOfType:MGCAllDayEventType atDate:date];
    }
    return 1; // for dayColumnView
}
#pragma mark MGCDayColumnCellDelegate
- (void)didSelectedDay:(MGCDayColumnCell *)_cell{
    NSIndexPath *indexPath = [self.dayColumnsView indexPathForCell:_cell];
    NSDate *date = [self dateFromDayOffset:indexPath.section];
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    dateFormatter.dateFormat = @"d MMM eeeee";
    NSLog(@"%@", [dateFormatter stringFromDate:date]);
    if ([self.dataSource respondsToSelector:@selector(dayPlannerView:didSelectDayCellAtDate:)]) {
        [self.dataSource dayPlannerView:self didSelectDayCellAtDate:date];
    }
}
/////////////////
- (UICollectionViewCell*)dayColumnCellAtIndexPath:(NSIndexPath*)indexPath
{
    MGCDayColumnCell *dayCell = [self.dayColumnsView dequeueReusableCellWithReuseIdentifier:DayColumnCellReuseIdentifier forIndexPath:indexPath];
    dayCell.headerHeight = self.dayHeaderHeight;
    dayCell.separatorColor = self.daySeparatorsColor;
    dayCell.dotColor = self.eventIndicatorDotColor;
    dayCell.dayColumndelegate = self;
    CGFloat allDayEventsViewHeight = 2;
    allDayEventsViewHeight = fmaxf(self.allDayEventCellHeight + 4, self.allDayEventsView.contentSize.height);
    allDayEventsViewHeight = fminf(allDayEventsViewHeight, self.allDayEventCellHeight * 2.5 + 6);
    dayCell.insetsHeight = allDayEventsViewHeight;
    
    
    NSDate *date = [self dateFromDayOffset:indexPath.section];
    if ([self.calendar mgc_isDate:date sameDayAsDate:[NSDate date]]) {
        dayCell.isShownCurrentTime = YES;
    }else{
        dayCell.isShownCurrentTime = NO;
    }
    
    NSUInteger weekDay = [self.calendar components:NSCalendarUnitWeekday fromDate:date].weekday;
    NSUInteger accessoryTypes = weekDay == self.calendar.firstWeekday ? MGCDayColumnCellAccessorySeparator : MGCDayColumnCellAccessoryBorder;
    
    NSAttributedString *attrStr = nil;
    if ([self.delegate respondsToSelector:@selector(dayPlannerView:attributedStringForDayHeaderAtDate:)]) {
        attrStr = [self.delegate dayPlannerView:self attributedStringForDayHeaderAtDate:date];
    }
    
    if (attrStr) {
        dayCell.dayLabel.attributedText = attrStr;
    }
    else {
        
        static NSDateFormatter *dateFormatter = nil;
        if (dateFormatter == nil) {
            dateFormatter = [NSDateFormatter new];
        }
        dateFormatter.dateFormat = self.dateFormat ?: @"d MMM\neeeee";
        
        NSString *s = [dateFormatter stringFromDate:date];
        
        NSMutableParagraphStyle *para = [NSMutableParagraphStyle new];
        para.alignment = NSTextAlignmentCenter;
        
        UIFont *font = [UIFont systemFontOfSize:14];
        UIColor *color = [self.calendar isDateInWeekend:date] ? [UIColor lightGrayColor] : [UIColor blackColor];
        
        if ([self.calendar mgc_isDate:date sameDayAsDate:[NSDate date]]) {
            accessoryTypes |= MGCDayColumnCellAccessoryMark;
            dayCell.markColor = self.tintColor;
            color = [UIColor whiteColor];
            font = [UIFont boldSystemFontOfSize:14];
        }
        
        NSAttributedString *as = [[NSAttributedString alloc]initWithString:s attributes:@{ NSParagraphStyleAttributeName: para, NSFontAttributeName: font, NSForegroundColorAttributeName: color }];
        dayCell.dayLabel.attributedText = as;
    }
    
    if ([self.loadingDays containsObject:date]) {
        [dayCell setActivityIndicatorVisible:YES];
    }
    
    NSUInteger count = [self numberOfAllDayEventsAtDate:date] + [self numberOfTimedEventsAtDate:date];
    if (count > 0) {
        accessoryTypes |= MGCDayColumnCellAccessoryDot;
    }
    
    dayCell.accessoryTypes = accessoryTypes;
    return dayCell;
}

- (UICollectionViewCell*)dequeueCellForEventOfType:(MGCEventType)type atIndexPath:(NSIndexPath*)indexPath
{
    NSDate *date = [self dateFromDayOffset:indexPath.section];
    NSUInteger index = indexPath.item;
    MGCEventView *cell = [self.dataSource dayPlannerView:self viewForEventOfType:type atIndex:index date:date];
    
    MGCEventCell *cvCell = nil;
    if (type == MGCTimedEventType) {
        cvCell = (MGCEventCell*)[self.timedEventsView dequeueReusableCellWithReuseIdentifier:EventCellReuseIdentifier forIndexPath:indexPath];
    }
    else if (type == MGCAllDayEventType) {
        cvCell = (MGCEventCell*)[self.allDayEventsView dequeueReusableCellWithReuseIdentifier:EventCellReuseIdentifier forIndexPath:indexPath];
    }
    
    cvCell.eventView = cell;
    if ([self.selectedCellIndexPath isEqual:indexPath] && self.selectedCellType == type) {
        cvCell.selected = YES;
    }
    
    return cvCell;
}
- (UICollectionViewCell*)dequeueCellForEventMeOfType:(MGCEventType)type atIndexPath:(NSIndexPath*)indexPath
{
    NSDate *date = [self dateFromDayOffset:indexPath.section];
    NSUInteger index = indexPath.item;
    MGCEventView *cell = [self.dataSource dayPlannerView:self viewForEventOfType:type atIndex:index date:date];
    
    MGCEventCell *cvCell = nil;
    if (type == MGCTimedEventType) {
        cvCell = (MGCEventCell*)[self.timedEventsMeView dequeueReusableCellWithReuseIdentifier:EventCellReuseIdentifier forIndexPath:indexPath];
    }
    else if (type == MGCAllDayEventType) {
        cvCell = (MGCEventCell*)[self.allDayEventsView dequeueReusableCellWithReuseIdentifier:EventCellReuseIdentifier forIndexPath:indexPath];
    }
    
    cvCell.eventView = cell;
    if ([self.selectedCellIndexPath isEqual:indexPath] && self.selectedCellType == type) {
        cvCell.selected = YES;
    }
    
    return cvCell;
}
- (UICollectionViewCell*)collectionView:(UICollectionView*)collectionView cellForItemAtIndexPath:(NSIndexPath*)indexPath
{
    if (collectionView == self.timedEventsMeView) {
        return [self dequeueCellForEventMeOfType:MGCTimedEventType atIndexPath:indexPath];
    }
    else if (collectionView == self.timedEventsView) {
        return [self dequeueCellForEventOfType:MGCTimedEventType atIndexPath:indexPath];
    }
    else if (collectionView == self.allDayEventsView) {
        return [self dequeueCellForEventOfType:MGCAllDayEventType atIndexPath:indexPath];
    }
    else if (collectionView == self.dayColumnsView) {
        return [self dayColumnCellAtIndexPath:indexPath];
    }
    return nil;
}

- (UICollectionReusableView*)collectionView:(UICollectionView*)collectionView viewForSupplementaryElementOfKind:(NSString*)kind atIndexPath:(NSIndexPath*)indexPath
{
    if ([kind isEqualToString:DimmingViewKind]) {
        UICollectionReusableView *view = [self.timedEventsView dequeueReusableSupplementaryViewOfKind:DimmingViewKind withReuseIdentifier:DimmingViewReuseIdentifier forIndexPath:indexPath];
        view.backgroundColor = self.dimmingColor;
        
        return view;
    }else if ([kind isEqualToString:DimmingMeViewKind]) {
        UICollectionReusableView *view = [self.timedEventsMeView dequeueReusableSupplementaryViewOfKind:DimmingMeViewKind withReuseIdentifier:DimmingViewMeReuseIdentifier forIndexPath:indexPath];
        view.backgroundColor = self.dimmingColor;
        
        return view;
    }
    ///// test
    else if ([kind isEqualToString:MoreEventsViewKind]) {
        UICollectionReusableView *view = [self.allDayEventsView dequeueReusableSupplementaryViewOfKind:MoreEventsViewKind withReuseIdentifier:MoreEventsViewReuseIdentifier forIndexPath:indexPath];
        
        view.autoresizesSubviews = YES;
        
        NSUInteger hiddenCount = [self.allDayEventsViewLayout numberOfHiddenEventsInSection:indexPath.section];
        UILabel *label = [[UILabel alloc]initWithFrame:view.bounds];
        label.text = [NSString stringWithFormat:NSLocalizedString(@"%d more...", nil), hiddenCount];
        label.textColor = [UIColor blackColor];
        label.font = [UIFont systemFontOfSize:11];
        label.autoresizingMask = UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
        
        [view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [view addSubview:label];
        
        return view;
    }
    return nil;
}
#pragma mark - MGCTimedEventsViewLayoutDelegate
- (EKEvent *)collectionView:(UICollectionView *)collectionView layout:(MGCTimedEventsViewLayout *)layout getEvent:(NSIndexPath *)indexPath
{
    NSDate *date = [self dateFromDayOffset:indexPath.section];
    NSUInteger index = indexPath.item;
    EKEvent *ev = nil;
    if (collectionView == self.timedEventsView) {
        ev = [self.dataSource dayPlannerView:self getEventWithType:MGCTimedEventType atIndex:index date:date];
    }
    else if (collectionView == self.allDayEventsView) {
        ev = [self.dataSource dayPlannerView:self getEventWithType:MGCAllDayEventType atIndex:index date:date];
    }
    return ev;
}
- (CGRect)collectionView:(UICollectionView *)collectionView layout:(MGCTimedEventsViewLayout *)layout rectForEventAtIndexPath:(NSIndexPath *)indexPath
{
    NSDate *date = [self dateFromDayOffset:indexPath.section];
    
    MGCDateRange *dayRange = [self scrollableTimeRangeForDate:date];
    
    MGCDateRange* eventRange = [self.dataSource dayPlannerView:self dateRangeForEventOfType:MGCTimedEventType atIndex:indexPath.item date:date];
    NSAssert(eventRange, @"[AllDayEventsViewLayoutDelegate dayPlannerView:dateRangeForEventOfType:atIndex:date:] cannot return nil!");
    
    [eventRange intersectDateRange:dayRange];
    
    if (!eventRange.isEmpty) {
        CGFloat y1 = [self offsetFromDate:eventRange.start];
        CGFloat y2 = [self offsetFromDate:eventRange.end];
        
        return CGRectMake(0, y1, 0, y2 - y1);
    }
    return CGRectNull;
}

- (NSArray*)dimmedTimeRangesAtDate:(NSDate*)date
{
    NSMutableArray *ranges = [NSMutableArray array];
    
    if ([self.delegate respondsToSelector:@selector(dayPlannerView:numberOfDimmedTimeRangesAtDate:)]) {
        NSInteger count = [self.delegate dayPlannerView:self numberOfDimmedTimeRangesAtDate:date];
        
        if (count > 0 && [self.delegate respondsToSelector:@selector(dayPlannerView:dimmedTimeRangeAtIndex:date:)]) {
            MGCDateRange *dayRange = [self scrollableTimeRangeForDate:date];
            
            for (NSUInteger i = 0; i < count; i++) {
                MGCDateRange *range = [self.delegate dayPlannerView:self dimmedTimeRangeAtIndex:i date:date];
                
                [range intersectDateRange:dayRange];
                
                if (!range.isEmpty) {
                    [ranges addObject:range];
                }
            }
        }
    }
    return ranges;
}

- (NSArray*)collectionView:(UICollectionView *)collectionView layout:(MGCTimedEventsViewLayout *)layout dimmingRectsForSection:(NSUInteger)section
{
    NSDate *date = [self dateFromDayOffset:section];
    
    NSArray *ranges = [self.dimmedTimeRangesCache objectForKey:date];
    if (!ranges) {
        ranges = [self dimmedTimeRangesAtDate:date];
        [self.dimmedTimeRangesCache setObject:ranges forKey:date];
    }
    
    NSMutableArray *rects = [NSMutableArray arrayWithCapacity:ranges.count];
    
    for (MGCDateRange *range in ranges) {
        if (!range.isEmpty) {
            CGFloat y1 = [self offsetFromDate:range.start];
            CGFloat y2 = [self offsetFromDate:range.end];
            
            [rects addObject:[NSValue valueWithCGRect:CGRectMake(0, y1, 0, y2 - y1)]];
        }
    }
    return rects;
}

#pragma mark - MGCTimedEventsMeViewLayoutDelegate
- (EKEvent *)collectionView:(UICollectionView *)collectionView layout:(MGCTimedEventsMeViewLayout *)layout getEventMe:(NSIndexPath *)indexPath
{
    NSDate *date = [self dateFromDayOffset:indexPath.section];
    NSUInteger index = indexPath.item;
    EKEvent *ev = nil;
    if (collectionView == self.timedEventsMeView){
        ev = [self.dataSource dayPlannerView:self getEventWithType:MGCTimedEventType atIndex:index date:date];
    }
    else if (collectionView == self.allDayEventsView) {
        ev = [self.dataSource dayPlannerView:self getEventWithType:MGCAllDayEventType atIndex:index date:date];
    }
    return ev;
}
- (CGRect)collectionView:(UICollectionView *)collectionView layout:(MGCTimedEventsMeViewLayout *)layout rectForEventAtIndexPathMe:(NSIndexPath *)indexPath
{
    NSDate *date = [self dateFromDayOffset:indexPath.section];
    
    MGCDateRange *dayRange = [self scrollableTimeRangeForDate:date];
    
    MGCDateRange* eventRange = [self.dataSource dayPlannerView:self dateRangeForEventOfType:MGCTimedEventType atIndex:indexPath.item date:date];
    NSAssert(eventRange, @"[AllDayEventsViewLayoutDelegate dayPlannerView:dateRangeForEventOfType:atIndex:date:] cannot return nil!");
    
    [eventRange intersectDateRange:dayRange];
    
    if (!eventRange.isEmpty) {
        CGFloat y1 = [self offsetFromDate:eventRange.start];
        CGFloat y2 = [self offsetFromDate:eventRange.end];
        
        return CGRectMake(0, y1, 0, y2 - y1);
    }
    return CGRectNull;
}

- (NSArray*)collectionView:(UICollectionView *)collectionView layout:(MGCTimedEventsMeViewLayout *)layout dimmingRectsForSectionMe:(NSUInteger)section
{
    NSDate *date = [self dateFromDayOffset:section];
    
    NSArray *ranges = [self.dimmedTimeRangesCache objectForKey:date];
    if (!ranges) {
        ranges = [self dimmedTimeRangesAtDate:date];
        [self.dimmedTimeRangesCache setObject:ranges forKey:date];
    }
    
    NSMutableArray *rects = [NSMutableArray arrayWithCapacity:ranges.count];
    
    for (MGCDateRange *range in ranges) {
        if (!range.isEmpty) {
            CGFloat y1 = [self offsetFromDate:range.start];
            CGFloat y2 = [self offsetFromDate:range.end];
            
            [rects addObject:[NSValue valueWithCGRect:CGRectMake(0, y1, 0, y2 - y1)]];
        }
    }
    return rects;
}

#pragma mark - MGCAllDayEventsViewLayoutDelegate

- (NSRange)collectionView:(UICollectionView*)view layout:(MGCAllDayEventsViewLayout*)layout dayRangeForEventAtIndexPath:(NSIndexPath*)indexPath
{
    NSDate *date = [self dateFromDayOffset:indexPath.section];
    MGCDateRange *dateRange = [self.dataSource dayPlannerView:self dateRangeForEventOfType:MGCAllDayEventType atIndex:indexPath.item date:date];
    NSAssert(dateRange, @"[AllDayEventsViewLayoutDelegate dayPlannerView:dateRangeForEventOfType:atIndex:date:] cannot return nil!");
    
    if ([dateRange.start compare:self.startDate] == NSOrderedAscending)
        dateRange.start = self.startDate;
    
    NSUInteger startSection = [self dayOffsetFromDate:dateRange.start];
    NSUInteger length = [dateRange components:NSCalendarUnitDay forCalendar:self.calendar].day;
    
    return NSMakeRange(startSection, length);
}

// TODO: implement
- (AllDayEventInset)collectionView:(UICollectionView*)view layout:(MGCAllDayEventsViewLayout*)layout insetsForEventAtIndexPath:(NSIndexPath*)indexPath
{
    return AllDayEventInsetNone;
}

#pragma mark - UICollectionViewDelegate

//- (void)collectionView:(UICollectionView*)collectionView willDisplayCell:(UICollectionViewCell*)cell forItemAtIndexPath:(NSIndexPath*)indexPath
//{
//}
//
//- (void)collectionView:(UICollectionView*)collectionView didEndDisplayingCell:(UICollectionViewCell*)cell forItemAtIndexPath:(NSIndexPath*)indexPath
//{
//}

// this is only supported on iOS 9 and above
- (CGPoint)collectionView:(UICollectionView *)collectionView targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset
{
    if (self.scrollTargetDate) {
        NSInteger targetSection = [self dayOffsetFromDate:self.scrollTargetDate];
        proposedContentOffset.x  = targetSection * self.dayColumnSize.width;
    }
    return proposedContentOffset;
}

#pragma mark - Scrolling utilities

// The difficulty with scrolling is that:
// - we have to synchronize between the different collection views
// - we have to restrict dragging to one direction at a time
// - we have to recenter the views when needed to make the infinite scrolling possible
// - we have to deal with possibly nested scrolls (animating or tracking while decelerating...)


// this is a single entry point for scrolling, called by scrollViewWillBeginDragging: when dragging starts,
// and before any "programmatic" scrolling outside of an already started scroll operation, like scrollToDate:animated:
// If direction is ScrollDirectionUnknown, it will be determined on first scrollViewDidScroll: received
- (void)scrollViewWillStartScrolling:(UIScrollView*)scrollView direction:(ScrollDirection)direction
{
    NSAssert(scrollView == self.timedEventsView || scrollView == self.allDayEventsView || scrollView == self.timedEventsMeView, @"For synchronizing purposes, only timedEventsView or allDayEventsView are allowed to scroll");
    
    if (self.controllingScrollView) {
        NSAssert(scrollView == self.controllingScrollView, @"Scrolling on two different views at the same time is not allowed");
        
        // we might be dragging while decelerating on the same view, but scrolling will be
        // locked according to the initial axis
    }
    
    //NSLog(@"scrollViewWillStartScrolling direction: %d", (int)direction);
    
    //[self deselectEventWithDelegate:YES];
    
    if (self.controllingScrollView == nil) {
        // we have to restrict dragging to one view at a time
        // until the whole scroll operation finishes.
        
        if (scrollView == self.timedEventsView || scrollView == self.timedEventsMeView) {
            self.allDayEventsView.scrollEnabled = NO;
        }
        else if (scrollView == self.allDayEventsView) {
            self.timedEventsView.scrollEnabled = NO;
        }
        
        // note which view started scrolling - for synchronizing,
        // and the start offset in order to determine direction
        self.controllingScrollView = scrollView;
        self.scrollStartOffset = scrollView.contentOffset;
        self.scrollDirection = direction;
    }
}

// even though directionalLockEnabled is set on both scrolling-enabled scrollviews,
// one can still scroll diagonally if the scrollview is dragged in both directions at the same time.
// This is not what we want!
- (void)lockScrollingDirection
{
    NSAssert(self.controllingScrollView, @"Trying to lock scrolling direction while no scroll operation has started");
    
    CGPoint contentOffset = self.controllingScrollView.contentOffset;
    if (self.scrollDirection == ScrollDirectionUnknown) {
        // determine direction
        if (fabs(self.scrollStartOffset.x - contentOffset.x) < fabs(self.scrollStartOffset.y - contentOffset.y)) {
            self.scrollDirection = ScrollDirectionVertical;
        }
        else {
            self.scrollDirection = ScrollDirectionHorizontal;
        }
    }
    
    // lock scroll position of the scrollview according to detected direction
    if (self.scrollDirection & ScrollDirectionVertical) {
        [self.controllingScrollView    setContentOffset:CGPointMake(self.scrollStartOffset.x, contentOffset.y)];
    }
    else if (self.scrollDirection & ScrollDirectionHorizontal) {
        [self.controllingScrollView setContentOffset:CGPointMake(contentOffset.x, self.scrollStartOffset.y)];
    }
}

// calculates the new start date, given a date to be the first visible on the left.
// if offset is not nil, it contains on return the number of days between this new start date
// and the first visible date.
- (NSDate*)startDateForFirstVisibleDate:(NSDate*)date dayOffset:(NSUInteger*)offset
{
    NSAssert(date, @"startDateForFirstVisibleDate:dayOffset: was passed nil date");
    
    date = [self.calendar mgc_startOfDayForDate:date];
    
    NSDateComponents *comps = [NSDateComponents new];
    comps.day = -kDaysLoadingStep * self.numberOfVisibleDays;
    NSDate *start = [self.calendar dateByAddingComponents:comps toDate:date options:0];
    
    // stay within the limits of our date range
    if (self.dateRange && [start compare:self.dateRange.start] == NSOrderedAscending) {
        start = self.dateRange.start;
    }
    else if (self.maxStartDate && [start compare:self.maxStartDate] == NSOrderedDescending) {
        start = self.maxStartDate;
    }
    
    if (offset) {
        *offset = abs((int)[self.calendar components:NSCalendarUnitDay fromDate:start toDate:date options:0].day);
    }
    return start;
}

// if necessary, recenters horizontally the controlling scroll view to permit infinite scrolling.
// this is called by scrollViewDidScroll:
// returns YES if we loaded new pages, NO otherwise
- (BOOL)recenterIfNeeded
{
    NSAssert(self.controllingScrollView, @"Trying to recenter with no controlling scroll view");
    
    CGFloat xOffset = self.controllingScrollView.contentOffset.x;
    CGFloat xContentSize = self.controllingScrollView.contentSize.width;
    CGFloat xPageSize = self.controllingScrollView.bounds.size.width;
    
    // this could eventually be tweaked - for now we recenter when we have less than a page on one or the other side
    if (xOffset < xPageSize || xOffset + 2 * xPageSize > xContentSize) {
        NSDate *newStart = [self startDateForFirstVisibleDate:self.visibleDays.start dayOffset:nil];
        NSInteger diff = [self.calendar components:NSCalendarUnitDay fromDate:self.startDate toDate:newStart options:0].day;
        
        if (diff != 0) {
            self.startDate = newStart;
            [self reloadCollectionViews];
            
            CGFloat newXOffset = -diff * self.dayColumnSize.width + self.controllingScrollView.contentOffset.x;
            [self.controllingScrollView setContentOffset:CGPointMake(newXOffset, self.controllingScrollView.contentOffset.y)];
            return YES;
        }
    }
    return NO;
}

// this is called by scrollViewDidScroll: to synchronize the collections views
// vertically (timedEventsView with timeRowsView), and horizontally (allDayEventsView with timedEventsView and dayColumnsView)
- (void)synchronizeScrolling
{
    NSAssert(self.controllingScrollView, @"Synchronizing scrolling with no controlling scroll view");
    
    CGPoint contentOffset = self.controllingScrollView.contentOffset;
    
    if (self.controllingScrollView == self.allDayEventsView && self.scrollDirection & ScrollDirectionHorizontal) {
        
        self.dayColumnsView.contentOffset = CGPointMake(contentOffset.x, 0);
        self.timedEventsView.contentOffset = CGPointMake(contentOffset.x, self.timedEventsView.contentOffset.y);
        self.timedEventsMeView.contentOffset = CGPointMake(contentOffset.x, 0);
    }
    else if (self.controllingScrollView == self.timedEventsView || self.controllingScrollView == self.timedEventsMeView) {
        
        if (self.scrollDirection & ScrollDirectionHorizontal) {
            self.dayColumnsView.contentOffset = CGPointMake(contentOffset.x, 0);
            self.allDayEventsView.contentOffset = CGPointMake(contentOffset.x, self.allDayEventsView.contentOffset.y);
            if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
                self.timeScrollView.contentOffset = CGPointMake(contentOffset.x - floorf(contentOffset.x/self.dayColumnSize.width) * self.dayColumnSize.width ,0);
            }
        }
        else {
            if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
                self.timeScrollView.contentOffset = CGPointMake(contentOffset.x - floorf(contentOffset.x/self.dayColumnSize.width) * self.dayColumnSize.width ,0);
            }else{
                self.timeScrollView.contentOffset = CGPointMake(0, contentOffset.y);
            }
        }
    }
}
//scrolled from ScheduleViewController
- (void)didScrolledFromDayView:(CGPoint)scrolledPoint{
    if (self.performFromGestureScrolling) {
        return;
    }
    //self.timedEventsView.contentOffset = CGPointMake(self.timedEventsView.contentOffset.x + self.timeHorizontalScrollView.contentOffset.y-scrolledPoint.y, 0);
    CGRect rectOfTimedEvent = self.timedEventsView.frame;
    rectOfTimedEvent.origin.y = rectOfTimedEvent.origin.y - scrolledPoint.y + self.timeHorizontalScrollView.contentOffset.y;
    
    self.timedEventsView.frame = rectOfTimedEvent;
    rectOfTimedEvent.size.height = 40;
    self.maskViewForHideMeOnTimedEventsView.frame = rectOfTimedEvent;
    //self.timedEventsMeView.frame = rectOfTimedEvent;
    self.timeHorizontalScrollView.contentOffset = scrolledPoint;
}
// this is called at the end of every scrolling operation, initiated by user or programatically
- (void)scrollViewDidEndScrolling:(UIScrollView*)scrollView
{
    
    // reset everything
    if (scrollView == self.controllingScrollView) {
        ScrollDirection direction = self.scrollDirection;
        
        self.scrollDirection = ScrollDirectionUnknown;
        self.timedEventsView.scrollEnabled = YES;
        self.allDayEventsView.scrollEnabled = YES;
        self.controllingScrollView = nil;
        
        if (self.scrollViewAnimationCompletionBlock) {
            dispatch_async(dispatch_get_main_queue(), self.scrollViewAnimationCompletionBlock);
            self.scrollViewAnimationCompletionBlock =  nil;
        }
        
        if (direction == ScrollDirectionHorizontal) {
            [self setupSubviews];  // allDayEventsView might need to be resized
        }
        
        if ([self.delegate respondsToSelector:@selector(dayPlannerView:didEndScrolling:withTappedNextPrew:)]) {
            MGCDayPlannerScrollType type = direction == ScrollDirectionHorizontal ? MGCDayPlannerScrollDate : MGCDayPlannerScrollTime;
            [self.delegate dayPlannerView:self didEndScrolling:type withTappedNextPrew:self.isSelectedNextPrewBtn];
            
        }
        self.isSelectedNextPrewBtn = NO;
    }
}


// this is the entry point for every programmatic scrolling of the timed events view
- (void)setTimedEventsViewContentOffset:(CGPoint)offset animated:(BOOL)animated completion:(void (^)(void))completion
{
    // animated programmatic scrolling is prohibited while another scrolling operation is in progress
    if (self.controllingScrollView)  return;
    
    CGPoint prevOffset = self.timedEventsView.contentOffset;
    
    if (animated && !CGPointEqualToPoint(offset, prevOffset)) {
        [[UIDevice currentDevice]endGeneratingDeviceOrientationNotifications];
    }
    
    self.scrollViewAnimationCompletionBlock = completion;
    
    [self scrollViewWillStartScrolling:self.timedEventsView direction:ScrollDirectionUnknown];
    //[self scrollViewWillStartScrolling:self.timedEventsMeView direction:ScrollDirectionUnknown];
    [self.timedEventsView setContentOffset:offset animated:animated];
    CGPoint offSetme = CGPointMake(offset.x, 0);
    [self.timedEventsMeView setContentOffset:offSetme animated:animated];
    
    if (!animated || CGPointEqualToPoint(offset, prevOffset)) {
        [self scrollViewDidEndScrolling:self.timedEventsView];
        //[self scrollViewDidEndScrolling:self.timedEventsMeView];
    }
    
}

- (void)updateVisibleDaysRange
{
    MGCDateRange *oldRange = self.previousVisibleDays;
    MGCDateRange *newRange = self.visibleDays;
    
    if ([oldRange isEqual:newRange]) return;
    
    if ([oldRange intersectsDateRange:newRange]) {
        MGCDateRange *range = [oldRange copy];
        [range unionDateRange:newRange];
        
        [range enumerateDaysWithCalendar:self.calendar usingBlock:^(NSDate *date, BOOL *stop){
            if ([oldRange containsDate:date] && ![newRange containsDate:date] &&
                [self.delegate respondsToSelector:@selector(dayPlannerView:didEndDisplayingDate:)])
            {
                [self.delegate dayPlannerView:self didEndDisplayingDate:date];
            }
            else if ([newRange containsDate:date] && ![oldRange containsDate:date] &&
                     [self.delegate respondsToSelector:@selector(dayPlannerView:willDisplayDate:)])
            {
                [self.delegate dayPlannerView:self willDisplayDate:date];
            }
        }];
    }
    else {
        [oldRange enumerateDaysWithCalendar:self.calendar usingBlock:^(NSDate *date, BOOL *stop){
            if ([self.delegate respondsToSelector:@selector(dayPlannerView:didEndDisplayingDate:)]) {
                [self.delegate dayPlannerView:self didEndDisplayingDate:date];
            }
        }];
        [newRange enumerateDaysWithCalendar:self.calendar usingBlock:^(NSDate *date, BOOL *stop){
            if ([self.delegate respondsToSelector:@selector(dayPlannerView:willDisplayDate:)]) {
                [self.delegate dayPlannerView:self willDisplayDate:date];
            }
        }];
    }
    
    self.previousVisibleDays = newRange;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView*)scrollView
{
    //NSLog(@"scrollViewWillBeginDragging");
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking && (scrollView == self.timedEventsView || scrollView == self.timedEventsMeView)) {
        self.performFromGestureScrolling = YES;
    }
    // direction will be determined on first scrollViewDidScroll: received
    [self scrollViewWillStartScrolling:scrollView direction:ScrollDirectionUnknown];
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollview
{
    // avoid looping
    if (scrollview != self.controllingScrollView)
        return;
    
    [self lockScrollingDirection];
    
    if (self.scrollDirection & ScrollDirectionHorizontal) {
        [self recenterIfNeeded];
    }
    
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking && scrollview == self.timedEventsView) {
        self.timedEventsMeView.contentOffset = CGPointMake(scrollview.contentOffset.x, 0);
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking && scrollview == self.timedEventsView) {
        self.timedEventsMeView.contentOffset = CGPointMake(scrollview.contentOffset.x, 0);
    }
    
    [self synchronizeScrolling];
    
    [self updateVisibleDaysRange];
    
    if ([self.delegate respondsToSelector:@selector(dayPlannerView:didScroll:)]) {
        MGCDayPlannerScrollType type = self.scrollDirection == ScrollDirectionHorizontal ? MGCDayPlannerScrollDate : MGCDayPlannerScrollTime;
        [self.delegate dayPlannerView:self didScroll:type];
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView*)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint*)targetContentOffset
{
    
    self.isScrolledPreDateWithScrolling = NO;
    self.isTouchFirstTimedEvents = NO;
    
    //NSLog(@"horzVelocity: %f", velocity.x);
    
    if (!(self.scrollDirection & ScrollDirectionHorizontal)) return;
    
    CGFloat xOffset = targetContentOffset->x;
    
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        //calculate current visiable section
        NSInteger visiableSection = floorf(self.scrollStartOffset.x / self.dayColumnSize.width);
        
        //NSLog(@"visiableSection: %ld", (long)visiableSection);
        
        if (fabs(velocity.x) < 0.7f || !self.pagingEnabled) {
            
            if ((visiableSection * self.dayColumnSize.width) < targetContentOffset->x && ((visiableSection+1) * self.dayColumnSize.width - self.bounds.size.width) > targetContentOffset->x) {
                
            }else if (((visiableSection+1) * self.dayColumnSize.width - self.bounds.size.width) < targetContentOffset->x && ((visiableSection+1) * self.dayColumnSize.width) > targetContentOffset->x) {
                xOffset = (visiableSection+1) * self.dayColumnSize.width - self.bounds.size.width;
            }else {
                // stick to nearest section
                NSInteger section = roundf(targetContentOffset->x / self.dayColumnSize.width);
                xOffset = section * self.dayColumnSize.width;
                self.scrollTargetDate = [self dateFromDayOffset:section];
            }
            
            
        }
        else if (self.pagingEnabled) {
            NSDate *date;
            if ((visiableSection * self.dayColumnSize.width) < targetContentOffset->x && ((visiableSection+1) * self.dayColumnSize.width - self.bounds.size.width) > targetContentOffset->x) {
                
            }else {
                // scroll to next page
                NSInteger section;
                if (velocity.x > 0) {
                    date = [self nextDateForPagingAfterDate:self.visibleDays.start];
                    section = [self dayOffsetFromDate:date];
                    xOffset = [self xOffsetFromDayOffset:section];
                }
                // scroll to previous page
                else {
                    date = [self prevDateForPagingBeforeDate:self.firstVisibleDate];
                    NSDate *currentDate = self.currentSelectedDate;
                    section = [self dayOffsetFromDate:date];
                    NSInteger currentSection = [self dayOffsetFromDate:currentDate];
                    if (section == currentSection) {
                        xOffset = [self xOffsetFromDayOffset:(section-1)] + self.dayColumnSize.width - self.bounds.size.width;
                    }else{
                        xOffset = [self xOffsetFromDayOffset:section] + self.dayColumnSize.width - self.bounds.size.width;
                    }
                    self.isScrolledPreDateWithScrolling = YES;
                }
                self.scrollTargetDate = [self dateFromDayOffset:section];
            }
        }else{
            NSLog(@"No Checking............");
        }
        xOffset = fminf(fmax(xOffset, 0), scrollView.contentSize.width - scrollView.bounds.size.width);
        targetContentOffset->x = xOffset;
        
    }else{
        if (fabs(velocity.x) < .7 || !self.pagingEnabled) {
            // stick to nearest section
            NSInteger section = roundf(targetContentOffset->x / self.dayColumnSize.width);
            xOffset = section * self.dayColumnSize.width;
            self.scrollTargetDate = [self dateFromDayOffset:section];
        }
        else if (self.pagingEnabled) {
            NSDate *date;
            
            // scroll to next page
            if (velocity.x > 0) {
                date = [self nextDateForPagingAfterDate:self.visibleDays.start];
            }
            // scroll to previous page
            else {
                date = [self prevDateForPagingBeforeDate:self.firstVisibleDate];
            }
            NSInteger section = [self dayOffsetFromDate:date];
            xOffset = [self xOffsetFromDayOffset:section];
            self.scrollTargetDate = [self dateFromDayOffset:section];
        }
        xOffset = fminf(fmax(xOffset, 0), scrollView.contentSize.width - scrollView.bounds.size.width);
        targetContentOffset->x = xOffset;
    }
    
    
}


- (void)scrollViewDidEndDragging:(UIScrollView*)scrollView willDecelerate:(BOOL)decelerate
{
    self.isTouchFirstTimedEvents = NO;
    self.performFromGestureScrolling = NO;
    
    //NSLog(@"scrollViewDidEndDragging decelerate: %d", decelerate);
    
    // (decelerate = NO and scrollView.decelerating = YES) means that a second scroll operation
    // started on the same scrollview while decelerating.
    // in that (rare) case, don't end up the operation, which could mess things up.
    // ex: swipe vertically and soon after swipe forward
    
    if (!decelerate && !scrollView.decelerating) {
        [self scrollViewDidEndScrolling:scrollView];
    }
    
    if (decelerate) {
        [[UIDevice currentDevice]endGeneratingDeviceOrientationNotifications];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView*)scrollView
{
    self.isTouchFirstTimedEvents = NO;
    self.performFromGestureScrolling = NO;
    
    [self scrollViewDidEndScrolling:scrollView];
    
    [[UIDevice currentDevice]beginGeneratingDeviceOrientationNotifications];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView*)scrollView
{
    self.isTouchFirstTimedEvents = NO;
    
    [self scrollViewDidEndScrolling:scrollView];
    
    [[UIDevice currentDevice]beginGeneratingDeviceOrientationNotifications];
}


#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGSize dayColumnSize = self.dayColumnSize;
    if (collectionView == self.timedEventsMeView) {
        return CGSizeMake(dayColumnSize.width, 40);
    }
    return CGSizeMake(dayColumnSize.width, self.bounds.size.height);
}

#pragma mark UIGestureRecognizer
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch{
    self.isTouchFirstTimedEvents = YES;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceivePress:(UIPress *)press{
    self.isTouchFirstTimedEvents = YES;
    return YES;
}

@end

