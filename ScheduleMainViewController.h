//
//  ScheduleMainViewController.h
//  FlightDesk
//
//  Created by stepanekdavid on 11/1/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SecureViewController.h"
#import <EventKitUI/EventKitUI.h>

@protocol CalendarViewControllerNavigation <NSObject>

@property (nonatomic, readonly) NSDate* centerDate;

- (void)moveToDate:(NSDate*)date animated:(BOOL)animated;
- (void)moveToNextPageAnimated:(BOOL)animated;
- (void)moveToPreviousPageAnimated:(BOOL)animated;
- (NSDate*)getCurrentDate;

@optional

@property (nonatomic) NSSet* visibleCalendars;

@end


typedef  UIViewController<CalendarViewControllerNavigation> CalendarViewController;


@protocol CalendarViewControllerDelegate <NSObject>

@optional

- (void)calendarViewController:(CalendarViewController*)controller didShowDate:(NSDate*)date;
- (void)calendarViewController:(CalendarViewController*)controller didSelectEvent:(EKEvent*)event;

@end

@interface ScheduleMainViewController : SecureViewController<CalendarViewControllerDelegate, EKCalendarChooserDelegate>
{
    __weak IBOutlet NSLayoutConstraint *toolbarBottomCons;
    __weak IBOutlet NSLayoutConstraint *resourcesBottomCons;
    __weak IBOutlet NSLayoutConstraint *leftPaddingRecourcesCons;
    __weak IBOutlet NSLayoutConstraint *leftPaddingContainerCons;
    
    __weak IBOutlet UIButton *btnCalendarEdit;
    __weak IBOutlet UIButton *btnCalendarSwitch;
    __weak IBOutlet UIButton *btnCalendarSetting;
    
    __weak IBOutlet UITableView *UsersTableView;
    __weak IBOutlet UITableView *AircraftTableView;
    __weak IBOutlet UITableView *ClassRoomsTableView;
    
    __weak IBOutlet UIImageView *imageUsers;
    __weak IBOutlet UIImageView *imageAircraft;
    __weak IBOutlet UIImageView *imageClassroom;
    __weak IBOutlet UILabel *lblUserType;
    
    __weak IBOutlet UIScrollView *scrLeftNavCV;
    __weak IBOutlet UIView *usersCoverView;
    __weak IBOutlet UIView *aircraftCoverView;
    __weak IBOutlet UIView *classroomsCoverView;
    
    __weak IBOutlet NSLayoutConstraint *usersCVHeightCons;
    __weak IBOutlet NSLayoutConstraint *aircraftCVHeightCons;
    __weak IBOutlet NSLayoutConstraint *classroomsCVHeightCons;
    
    __weak IBOutlet NSLayoutConstraint *topConstrainsResources;
    __weak IBOutlet NSLayoutConstraint *heightResourcesTitleConstrains;
    
}
@property (nonatomic) CalendarViewController* calendarViewController;

@property (nonatomic, weak) IBOutlet UIView *containerView;
@property (nonatomic, weak) IBOutlet UILabel *currentDateLabel;
@property (nonatomic, weak) IBOutlet UISegmentedControl *viewChooser;

@property (nonatomic) CGPoint preNavScrPoint;


- (IBAction)onEditCalendar:(id)sender;
- (IBAction)onSwitchCalendar:(id)sender;
- (IBAction)onSettingCalendar:(id)sender;
- (IBAction)onToday:(id)sender;

@property (nonatomic) NSCalendar *calendar;
@property (nonatomic) EKEventStore *eventStore;

- (void)getInitialDataFromLocal;

@end
