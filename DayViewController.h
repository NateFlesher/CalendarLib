//
//  DayViewController.h
//  Calendar
//
//  Copyright © 2016 Julien Martin. All rights reserved.
//

#import "MGCDayPlannerEKViewController.h"
#import "ScheduleMainViewController.h"

@class DayViewController;
@protocol DayViewControllerDelegate <MGCDayPlannerEKViewControllerDelegate, CalendarViewControllerDelegate, UIViewControllerTransitioningDelegate>
@optional

- (void)dayViewController:(DayViewController*)controller didScrolledFromMGCDayView:(CGPoint)_point;

@end


@interface DayViewController : MGCDayPlannerEKViewController <CalendarViewControllerNavigation>

@property (nonatomic, weak) id<DayViewControllerDelegate> delegate;

@end

