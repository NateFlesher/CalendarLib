//
//  WeekViewController.h
//  CalendarDemo - Graphical Calendars Library for iOS
//
//  Copyright (c) 2014-2015 Julien Martin. All rights reserved.
//

#import "MGCDayPlannerEKViewController.h"
#import "ScheduleMainViewController.h"

@class WeekViewController;
@protocol WeekViewControllerDelegate <MGCDayPlannerEKViewControllerDelegate, CalendarViewControllerDelegate, UIViewControllerTransitioningDelegate>
@optional

- (void)dayViewController:(WeekViewController*)controller didSelectDayCellAtDate:(NSDate*)date;
- (void)dayViewController:(WeekViewController*)controller didScrolledFromMGCDayView:(CGPoint)_point;
@end


@interface WeekViewController : MGCDayPlannerEKViewController <CalendarViewControllerNavigation>

@property (nonatomic, weak) id<WeekViewControllerDelegate> delegate;
@property (nonatomic) BOOL showDimmedTimeRanges;

@end

