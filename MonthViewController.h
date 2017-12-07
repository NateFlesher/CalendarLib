//
//  MonthViewController.h
//  CalendarDemo - Graphical Calendars Library for iOS
//
//  Copyright (c) 2014-2015 Julien Martin. All rights reserved.
//

#import "MGCMonthPlannerEKViewController.h"
#import "ScheduleMainViewController.h"

@class MonthViewController;

@protocol MonthViewControllerDelegate<CalendarViewControllerDelegate>

@optional

- (void)monthViewController:(MonthViewController*)controller didSelectDayCellAtDate:(NSDate*)date;

@end

@interface MonthViewController : MGCMonthPlannerEKViewController <CalendarViewControllerNavigation>

@property (nonatomic, weak) id<CalendarViewControllerDelegate> delegate;

@property (nonatomic, weak) id<MonthViewControllerDelegate> monthDelegate;
@end
