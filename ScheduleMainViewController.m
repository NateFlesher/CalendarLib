//
//  ScheduleMainViewController.m
//  FlightDesk
//
//  Created by stepanekdavid on 11/1/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import "ScheduleMainViewController.h"
#import "WeekViewController.h"
#import "MonthViewController.h"
#import "YearViewController.h"
#import "DayViewController.h"
#import "NSCalendar+MGCAdditions.h"
#import "WeekSettingsViewController.h"
#import "MonthSettingsViewController.h"
#import "AddReservationViewController.h"

#import "ResourcesCell.h"

#import <EventKitUI/EventKitUI.h>

#import "DashboardView.h"
#import "SettingViewController.h"
#import "UIView+Badge.h"

typedef enum : NSUInteger
{
    CalendarViewWeekType  = 1,
    CalendarViewMonthType = 2,
    CalendarViewYearType = 3,
    CalendarViewDayType = 0
} CalendarViewType;

@interface ScheduleMainViewController ()<YearViewControllerDelegate, WeekViewControllerDelegate, DayViewControllerDelegate,MonthViewControllerDelegate, UIScrollViewDelegate,UIPopoverPresentationControllerDelegate>
{
    NSMutableArray *usersArray;
    NSMutableArray *aircraftArray;
    NSMutableArray *classroomsArray;
    
    NSMutableArray *arrayUsersCalendarsSelected;
    NSMutableArray *arrayAircraftsCalendarsSelected;
    NSMutableArray *arrayClassroomsCalendarsSelected;
    
    BOOL isDragOnFoucesScreen;
    
    BOOL isStartedInialReservation;
    
}
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic) EKCalendarChooser *calendarChooser;
@property (nonatomic) BOOL firstTimeAppears;

@property (nonatomic) DayViewController *dayViewController;
@property (nonatomic) WeekViewController *weekViewController;
@property (nonatomic) MonthViewController *monthViewController;
@property (nonatomic) YearViewController *yearViewController;


@property (nonatomic, strong) UIView *containViewOfEventAdding;
@property (nonatomic, strong) UIButton *eventAddingBtn;
@end

@implementation ScheduleMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //Loaded at once
    [AppDelegate sharedDelegate].isLoadedScheduleViewAtOnce = YES;
    
    self.title = @"Schedule";
    [self.navigationController.navigationBar setTintColor:[UIColor whiteColor]];
    
    self.preNavScrPoint = CGPointMake(0, 0);
    
    scrLeftNavCV.delegate = self;
    scrLeftNavCV.showsHorizontalScrollIndicator = NO;
    scrLeftNavCV.showsVerticalScrollIndicator = NO;
    isStartedInialReservation = NO;
    UIImage *imageCalendarEdit = [[UIImage imageNamed:@"calendar_edit"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [btnCalendarEdit setImage:imageCalendarEdit forState:UIControlStateNormal];
    btnCalendarEdit.tintColor = [UIColor colorWithRed:16.0f/255.0f green:114.0f/255.0f blue:189.0f/255.0f alpha:1.0f];
    
    UIImage *imageCalendarSetting = [[UIImage imageNamed:@"calendar_settings"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [btnCalendarSetting setImage:imageCalendarSetting forState:UIControlStateNormal];
    btnCalendarSetting.tintColor = [UIColor colorWithRed:16.0f/255.0f green:114.0f/255.0f blue:189.0f/255.0f alpha:1.0f];
    
    [btnCalendarSwitch setImage:[UIImage imageNamed:@"flightdesk_calendar"] forState:UIControlStateNormal];
    
    
    btnCalendarSetting.enabled = NO;
    
    isDragOnFoucesScreen = NO;
    
    if ([[AppDelegate sharedDelegate].userLevel.lowercaseString isEqualToString:@"student"]) {
        lblUserType.text = @"Instructors";
    }else{
        lblUserType.text = @"Students";
    }
    
    usersArray = [[NSMutableArray alloc] init];
    aircraftArray = [[NSMutableArray alloc] init];
    classroomsArray = [[NSMutableArray alloc] init];
    arrayUsersCalendarsSelected = [[NSMutableArray alloc] init];
    arrayAircraftsCalendarsSelected = [[NSMutableArray alloc] init];
    arrayClassroomsCalendarsSelected = [[NSMutableArray alloc] init];
    
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = [UIScreen mainScreen] .bounds;
    gradientLayer.colors = @[ (__bridge id)[UIColor colorWithRed:240.0f/255.0f green:240.0f/255.0f blue:240.0f/255.0f alpha:1.0f].CGColor,
                              (__bridge id)[UIColor colorWithRed:190.0f/255.0f green:190.0f/255.0f blue:190.0f/255.0f alpha:1.0f].CGColor ];
    gradientLayer.startPoint = CGPointMake(0.5, 0.0);
    gradientLayer.endPoint = CGPointMake(0.5, 1.0);
    UIGraphicsBeginImageContext(gradientLayer.bounds.size);
    [gradientLayer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *gradientImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [imageUsers setImage:gradientImage];
    [imageAircraft setImage:gradientImage];
    [imageClassroom setImage:gradientImage];
    
    // Get the permission to access contacts
    if ([CNContactStore class]) {
        //ios9 or later
        CNEntityType entityType = CNEntityTypeContacts;
        if( [CNContactStore authorizationStatusForEntityType:entityType] == CNAuthorizationStatusNotDetermined)
        {
            CNContactStore * contactStore = [[CNContactStore alloc] init];
            [contactStore requestAccessForEntityType:entityType completionHandler:^(BOOL granted, NSError * _Nullable error) {
                if(granted){
                    
                }
            }];
        }
        else if( [CNContactStore authorizationStatusForEntityType:entityType]== CNAuthorizationStatusAuthorized)
        {
            
        }else {
            // Send an alert telling user to change privacy setting in settings app
            [self showAlert:@"Could not get contact info from address book, you can allow Ginko to access your contacts in Settings." :@"Oops!"];
        }
    }
    
    [AppDelegate sharedDelegate].isSelectedDayViewForBooking = YES;
    [AppDelegate sharedDelegate].isSelectedWeekViewForBooking = NO;
    
    self.eventStore = [[EKEventStore alloc]init];
    CalendarViewController *controller = [self controllerForViewType:CalendarViewDayType];
    [self addChildViewController:controller];
    [self.containerView addSubview:controller.view];
    controller.view.frame = self.containerView.bounds;
    [controller didMoveToParentViewController:self];
    self.calendarViewController = controller;
    leftPaddingContainerCons.constant = 200.0f;
    
    
    NSString *calID = [[NSUserDefaults standardUserDefaults]stringForKey:@"calendarIdentifier"];
    self.calendar = [NSCalendar mgc_calendarFromPreferenceString:calID];
    
    NSUInteger firstWeekday = [[NSUserDefaults standardUserDefaults]integerForKey:@"firstDay"];
    if (firstWeekday != 0) {
        self.calendar.firstWeekday = firstWeekday;
    } else {
        [[NSUserDefaults standardUserDefaults]registerDefaults:@{ @"firstDay" : @(self.calendar.firstWeekday) }];
    }
    
    self.dateFormatter = [NSDateFormatter new];
    self.dateFormatter.calendar = self.calendar;
    
    self.firstTimeAppears = YES;
    
    
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 11.0) {
        toolbarBottomCons.constant = 0.0f;
        resourcesBottomCons.constant = 0.0f;
    }else{
        toolbarBottomCons.constant = 50.0f;
        resourcesBottomCons.constant = 50.0f;
    }
    
    leftPaddingRecourcesCons.constant = 0.0f;
    
    ////////////////
    self.containViewOfEventAdding = [[UIView alloc] initWithFrame:CGRectMake([UIScreen mainScreen].bounds.size.width - 70, [UIScreen mainScreen].bounds.size.height-120, 50, 50)];
    self.containViewOfEventAdding.autoresizesSubviews = NO;
    self.containViewOfEventAdding.contentMode = UIViewContentModeRedraw;
    self.containViewOfEventAdding.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    
    self.containViewOfEventAdding.layer.shadowRadius = 20.0f;
    self.containViewOfEventAdding.layer.shadowOpacity = 1.0f;
    self.containViewOfEventAdding.layer.shadowOffset = CGSizeMake(0.0f, 2.0f);
    self.containViewOfEventAdding.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.containViewOfEventAdding.bounds].CGPath;
    self.containViewOfEventAdding.layer.cornerRadius = 25.0f;
    self.containViewOfEventAdding.backgroundColor = [UIColor colorWithRed:16.0f/255.0f green:114.0f/255.0f blue:189.0f/255.0f alpha:1.0f];
    
    self.eventAddingBtn = [[UIButton alloc] initWithFrame:CGRectMake(5, 5, 40, 40)];
    [self.eventAddingBtn addTarget:self action:@selector(onAddingEvent:) forControlEvents:UIControlEventTouchUpInside];
    [self.eventAddingBtn setImage:[UIImage imageNamed:@"addbtn"] forState:UIControlStateNormal];
    [self.containViewOfEventAdding addSubview:self.eventAddingBtn];
    
    
    if (!self.containViewOfEventAdding.superview) {
        [[AppDelegate sharedDelegate].window.rootViewController.view addSubview:self.containViewOfEventAdding];
    }
    
}
-(void)showAlert:(NSString*)msg :(NSString*)title
{
    UIAlertController * alert=[UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* yesButton = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action){
        NSLog(@"you pressed Yes, please button");
    }];
    [alert addAction:yesButton];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceOrientationDidChange) name:UIDeviceOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resizePostionOfResources) name:NOTIFICATION_RESOURCES_POSITION object:nil];
    if (self.firstTimeAppears) {
        NSDate *date = [self.calendar mgc_startOfWeekForDate:[NSDate date]];
        [self.calendarViewController moveToDate:[NSDate date] animated:NO];
        self.firstTimeAppears = NO;
    }
}
- (void)resizePostionOfResources{
    topConstrainsResources.constant = topConstrainsResources.constant + [AppDelegate sharedDelegate].deviationOfResources;
    heightResourcesTitleConstrains.constant = heightResourcesTitleConstrains.constant + [AppDelegate sharedDelegate].deviationOfResources;
}
- (void)deviceOrientationDidChange{
    [self setNavigationColorWithGradiant];
    [self superClassDeviceOrientationDidChange];
    [self initLeftNaviSizeWithData];
    
    
    self.containViewOfEventAdding.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 70, [UIScreen mainScreen].bounds.size.height-120, 50, 50);
}
- (void)setNavigationColorWithGradiant{
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = [UIScreen mainScreen] .bounds;
    gradientLayer.colors = @[ (__bridge id)[UIColor colorWithRed:210.0f/255.0f green:50.0f/255.0f blue:140.0f/255.0f alpha:1.0f].CGColor,
                              (__bridge id)[UIColor colorWithRed:80.0f/255.0f green:0 blue:80.0f/255.0f alpha:1.0f].CGColor ];
    gradientLayer.startPoint = CGPointMake(0.0, 0.5);
    gradientLayer.endPoint = CGPointMake(1.0, 0.5);
    UIGraphicsBeginImageContext(gradientLayer.bounds.size);
    [gradientLayer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *gradientImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    [self.navigationController.navigationBar setBackgroundImage:gradientImage forBarMetrics:UIBarMetricsDefault];
}
- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
    [AppDelegate sharedDelegate].isShownScheduleView = YES;
    
    [self setNavigationColorWithGradiant];
    settingsButton.badge.badgeValue = [[AppDelegate sharedDelegate] getBadgeCountForExpiredAircraft:nil];
    settingsButton.badge.badgeColor = [UIColor redColor];
    [self getInitialDataFromLocal];
    id<GAITracker> tracker = [GAI sharedInstance].defaultTracker;
    [tracker set:kGAIScreenName value:@"CKCalendarViewControllerInternal"];
    [tracker send:[[GAIDictionaryBuilder createScreenView] build]];
    
    if (!self.containViewOfEventAdding.superview) {
        [[AppDelegate sharedDelegate].window.rootViewController.view addSubview:self.containViewOfEventAdding];
    }
}
- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    [AppDelegate sharedDelegate].isShownScheduleView = NO;
    
    [[AppDelegate sharedDelegate] stopThreadToSyncData:9];
    if (self.containViewOfEventAdding.superview) {
        [self.containViewOfEventAdding removeFromSuperview];
    }
}

- (void)initLeftNaviSizeWithData{
    CGFloat titleHeight = 40.0f;
    usersCVHeightCons.constant = titleHeight + 40.0f * usersArray.count;
    aircraftCVHeightCons.constant = titleHeight + 40.0f * aircraftArray.count;
    classroomsCVHeightCons.constant = titleHeight + 40.0f * classroomsArray.count;
    if ((usersCVHeightCons.constant + aircraftCVHeightCons.constant + classroomsCVHeightCons.constant) > scrLeftNavCV.frame.size.height) {
        [scrLeftNavCV setContentSize:CGSizeMake(200.0f, 40.0f + usersCVHeightCons.constant + aircraftCVHeightCons.constant + classroomsCVHeightCons.constant)];
    }
    
    
}
- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NOTIFICATION_RESOURCES_POSITION object:nil];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (void)getInitialDataFromLocal{
    if (isStartedInialReservation) {
        return;
    }
    isStartedInialReservation = YES;
    [usersArray removeAllObjects];
    [aircraftArray removeAllObjects];
    [classroomsArray removeAllObjects];
    
    NSError *error;
    NSManagedObjectContext *context = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
    NSEntityDescription *entityDesc = [NSEntityDescription entityForName:@"Users" inManagedObjectContext:context];
    // load the remaining lesson groups
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:entityDesc];
    NSArray *objects = [context executeFetchRequest:request error:&error];
    if (objects == nil) {
        FDLogError(@"Unable to retrieve Users!");
    } else if (objects.count == 0) {
        FDLogDebug(@"No valid Users found!");
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
        FDLogError(@"Unable to retrieve Aircraft!");
    } else if (objects.count == 0) {
        FDLogDebug(@"No valid Aircrafts found!");
    } else {
        FDLogDebug(@"%lu Aircrafts found", (unsigned long)[objects count]);
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
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self updatingCalendarsWithData];
    });
    
    
    [UsersTableView reloadData];
    [AircraftTableView reloadData];
    [ClassRoomsTableView reloadData];
    [self initLeftNaviSizeWithData];
}
- (void)addOrUpdateCalendarWithString:(NSString *)calendarId withType:(NSInteger)type{
    //adding a EKCalendar
    BOOL isExitCal  =NO;
    for (EKCalendar *calToCheck in [self.eventStore calendarsForEntityType:EKEntityTypeEvent]) {
        if ([calToCheck.title isEqualToString:calendarId]) {
            isExitCal = YES;
            break;
        }
    }
    if (isExitCal == NO) {
        NSString* calendarName = calendarId;
        EKCalendar* calendar;
        
        // Get the calendar source
        EKSource* localSource;
        for (EKSource* source in self.eventStore.sources) {
            if (source.sourceType == EKSourceTypeLocal || source.sourceType == EKSourceTypeCalDAV)
            {
                localSource = source;
                break;
            }
        }
        
        if (localSource)
        {
            calendar = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:self.eventStore];
            calendar.source = localSource;
            calendar.title = calendarName;
            CGFloat red = arc4random_uniform(255) / 255.0;
            CGFloat green = arc4random_uniform(255) / 255.0;
            CGFloat blue = arc4random_uniform(255) / 255.0;
            calendar.CGColor = [UIColor colorWithRed:red green:green blue:blue alpha:1.0f].CGColor;
            
            NSError* error;
            BOOL success= [self.eventStore saveCalendar:calendar commit:YES error:&error];
            if (error != nil)
            {
                NSLog(@"%@", error.description);
                // TODO: error handling here
            }
            if (success) {
                
            }
        }
    }
}
- (void)updatingCalendarsWithData{
    for (Users *oneUser in usersArray) {
        [self addOrUpdateCalendarWithString:[NSString stringWithFormat:@"FD-U-(%@ %@ %@)", oneUser.firstName, oneUser.middleName, oneUser.lastName] withType:1];
    }
    for (Aircraft *oneAircraft in aircraftArray) {
        NSString *aircraftItems = oneAircraft.aircraftItems;
        NSData *data = [aircraftItems dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *aircraftReg = @"";
        NSString *aircraftMod = @"";
        for (NSDictionary *fieldInfo in json) {
            if ([[fieldInfo objectForKey:@"fieldName"] isEqualToString:@"Registration"]) {
                aircraftReg= [fieldInfo objectForKey:@"content"];
            }
            if ([[fieldInfo objectForKey:@"fieldName"] isEqualToString:@"Model"]) {
                aircraftMod = [fieldInfo objectForKey:@"content"];
            }
        }
        
        [self addOrUpdateCalendarWithString:[NSString stringWithFormat:@"FD-A-(%@ %@)", aircraftReg, aircraftMod]  withType:2];
    }
    for (NSString *classrooms in classroomsArray) {
        [self addOrUpdateCalendarWithString:[NSString stringWithFormat:@"FD-C-(%@)", classrooms]  withType:3];
    }
    NSError *error;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    NSManagedObjectContext *context = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"ResourcesCalendar" inManagedObjectContext:context];
    [request setEntity:entityDescription];
    NSArray *fetchedResourcesCalendars = [context executeFetchRequest:request error:&error];
    for (ResourcesCalendar *resourcesCalendarToUpdate in fetchedResourcesCalendars) {
        if ([resourcesCalendarToUpdate.event_identify isEqualToString:@""]){
            resourcesCalendarToUpdate.event_identify = [self saveCurrentEventOnCalendar:resourcesCalendarToUpdate];
        }
    }
    [context save:&error];
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSArray *calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];
        NSMutableSet *selectedCalendars = [[NSMutableSet alloc] init];
        for (EKCalendar *currentCalendar in calendars) {
            NSString *prefixOfCalendar = @"";
            if(currentCalendar.title.length > 3){
                prefixOfCalendar = [currentCalendar.title substringToIndex:3];
            }
            if ([AppDelegate sharedDelegate].isSelectedIosCalendar == NO) {
                if ([prefixOfCalendar isEqualToString:@"FD-"]) {
                    [selectedCalendars addObject:currentCalendar];
                }
            }else{
                [selectedCalendars addObject:currentCalendar];
            }
        }
        
        self.calendarViewController.visibleCalendars = selectedCalendars;
        
        if (arrayUsersCalendarsSelected.count != 0 && arrayAircraftsCalendarsSelected.count != 0 && arrayClassroomsCalendarsSelected.count != 0) {
            [self showingCalendarsSelected];
        }
        
        
        
        
        isStartedInialReservation = NO;
        [self performSelector:@selector(stopProgressWithSchedule) withObject:nil afterDelay:1];
        if ([AppDelegate sharedDelegate].isShownScheduleView) {
            [[AppDelegate sharedDelegate] startThreadToSyncData:9];
        }
    });
}
- (void)stopProgressWithSchedule{
    [MBProgressHUD hideHUDForView:[AppDelegate sharedDelegate].window animated:YES];
}
- (NSString *)saveCurrentEventOnCalendar:(ResourcesCalendar *)resourcesCalendar{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
    [dateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
    
    EKEvent *ev = [EKEvent eventWithEventStore:self.eventStore];
    ev.title = resourcesCalendar.title;
    ev.startDate = [dateFormatter dateFromString:resourcesCalendar.startDate];
    ev.endDate = [dateFormatter dateFromString:resourcesCalendar.endDate];
    
    NSArray *calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];
    for (EKCalendar *currentCalendar in calendars) {
        if ([currentCalendar.title isEqualToString:resourcesCalendar.calendar_name]) {
            ev.calendar = currentCalendar;
            break;
        }
    }
    NSError *error;
    [self.eventStore saveEvent:ev span:EKSpanThisEvent error:&error];
    if (error != nil) {
        NSLog(@"Event Saving Error : %@", error.localizedDescription);
    }
    return ev.eventIdentifier;
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    UINavigationController *nc = (UINavigationController*)self.presentedViewController;
    if (nc) {
        BOOL hide = (self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular);
        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSettings:)];
        nc.topViewController.navigationItem.rightBarButtonItem = hide ? nil : doneButton;
    }
}

#pragma mark - Private

- (DayViewController*)dayViewController
{
    if (_dayViewController == nil) {
        _dayViewController = [[DayViewController alloc]initWithEventStore:self.eventStore];
        _dayViewController.calendar = self.calendar;
        _dayViewController.showsWeekHeaderView = YES;
        _dayViewController.delegate = self;
        _dayViewController.dayPlannerView.eventCoveringType = MGCDayPlannerCoveringTypeComplex;
    }
    return _dayViewController;
}

- (WeekViewController*)weekViewController
{
    if (_weekViewController == nil) {
        _weekViewController = [[WeekViewController alloc]initWithEventStore:self.eventStore];
        _weekViewController.calendar = self.calendar;
        _weekViewController.delegate = self;
    }
    return _weekViewController;
}

- (MonthViewController*)monthViewController
{
    if (_monthViewController == nil) {
        _monthViewController = [[MonthViewController alloc]initWithEventStore:self.eventStore];
        _monthViewController.calendar = self.calendar;
        _monthViewController.delegate = self;
        _monthViewController.monthDelegate = self;
    }
    return _monthViewController;
}

- (YearViewController*)yearViewController
{
    if (_yearViewController == nil) {
        _yearViewController = [[YearViewController alloc]init];
        _yearViewController.calendar = self.calendar;
        _yearViewController.delegate = self;
    }
    return _yearViewController;
}

- (CalendarViewController*)controllerForViewType:(CalendarViewType)type
{
    switch (type)
    {
        case CalendarViewDayType:  return self.dayViewController;
        case CalendarViewWeekType:  return self.weekViewController;
        case CalendarViewMonthType: return self.monthViewController;
        case CalendarViewYearType:  return self.yearViewController;
    }
    return nil;
}

-(void)moveToNewController:(CalendarViewController*)newController atDate:(NSDate*)date
{
    [self.calendarViewController willMoveToParentViewController:nil];
    [self addChildViewController:newController];
    
    [self transitionFromViewController:self.calendarViewController toViewController:newController duration:.5 options:UIViewAnimationOptionTransitionFlipFromLeft animations:^
     {
         newController.view.frame = self.containerView.bounds;
         newController.view.hidden = YES;
     } completion:^(BOOL finished)
     {
         [self.calendarViewController removeFromParentViewController];
         [newController didMoveToParentViewController:self];
         self.calendarViewController = newController;
         [newController moveToDate:date animated:NO];
         newController.view.hidden = NO;
     }];
}

#pragma mark - Actions

-(IBAction)switchControllers:(UISegmentedControl*)sender
{
    btnCalendarSetting.enabled = NO;
    btnCalendarSwitch.enabled = NO;
    btnCalendarEdit.enabled = NO;
    
    
    [AppDelegate sharedDelegate].isSelectedDayViewForBooking = NO;
    [AppDelegate sharedDelegate].isSelectedWeekViewForBooking = NO;
    if (sender.selectedSegmentIndex == 0) {
        [AppDelegate sharedDelegate].isSelectedDayViewForBooking = YES;
    }else if(sender.selectedSegmentIndex == 1){
        [AppDelegate sharedDelegate].isSelectedWeekViewForBooking = YES;
    }
    
    NSDate *date = [self.calendar mgc_startOfWeekForDate:[NSDate date]];// [self.calendarViewController centerDate];
    CalendarViewController *controller = [self controllerForViewType:sender.selectedSegmentIndex];
    [self moveToNewController:controller atDate:[NSDate date]];
    
    
    if ([controller isKindOfClass:WeekViewController.class] || [controller isKindOfClass:MonthViewController.class]) {
        btnCalendarSetting.enabled = YES;
    }
    if (![controller isKindOfClass:YearViewController.class]) {
        btnCalendarSwitch.enabled = YES;
        btnCalendarEdit.enabled = YES;
    }
    
    leftPaddingContainerCons.constant = 0.0f;
    self.view.userInteractionEnabled = NO;
    if ([controller isKindOfClass:DayViewController.class]) {
        if (!self.containViewOfEventAdding.superview) {
            [[AppDelegate sharedDelegate].window.rootViewController.view addSubview:self.containViewOfEventAdding];
        }
        leftPaddingContainerCons.constant = 200.0f;
        [UIView animateWithDuration:0.5 delay:0.0 options:UIViewAnimationOptionCurveLinear
                         animations:^(void)
         {
             leftPaddingRecourcesCons.constant = 0.0f;
             [self.view layoutIfNeeded];
         }
                         completion:^(BOOL finished)
         {
             self.view.userInteractionEnabled = YES;
             [(DayViewController *)controller didScrollWithResources:self.preNavScrPoint];
         }
         ];
    }else if ([controller isKindOfClass:WeekViewController.class]) {
        if (!self.containViewOfEventAdding.superview) {
            [[AppDelegate sharedDelegate].window.rootViewController.view addSubview:self.containViewOfEventAdding];
        }
        leftPaddingContainerCons.constant = 200.0f;
        [UIView animateWithDuration:0.5 delay:0.0 options:UIViewAnimationOptionCurveLinear
                         animations:^(void)
         {
             leftPaddingRecourcesCons.constant = 0.0f;
             [self.view layoutIfNeeded];
         }
                         completion:^(BOOL finished)
         {
             self.view.userInteractionEnabled = YES;
             [(WeekViewController *)controller didScrollWithResources:self.preNavScrPoint];
         }
         ];
    }else{
        if (self.containViewOfEventAdding.superview) {
            [self.containViewOfEventAdding removeFromSuperview];
        }
        [UIView animateWithDuration:0.5 delay:0.0 options:UIViewAnimationOptionCurveLinear
                         animations:^(void)
         {
             leftPaddingRecourcesCons.constant = -200.0f;
             [self.view layoutIfNeeded];
         }
                         completion:^(BOOL finished)
         {
             self.view.userInteractionEnabled = YES;
         }
         ];
    }
}

- (IBAction)nextPage:(id)sender
{
    [self.calendarViewController moveToNextPageAnimated:YES];
}

- (IBAction)previousPage:(id)sender
{
    [self.calendarViewController moveToPreviousPageAnimated:YES];
}

- (void)dismissSettings:(UIBarButtonItem*)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)calendarChooserStartEdit
{
    self.calendarChooser.editing = YES;
    self.calendarChooser.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(calendarChooserEndEdit)];
}

- (void)calendarChooserEndEdit
{
    self.calendarChooser.editing = NO;
    self.calendarChooser.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(calendarChooserStartEdit)];
}

#pragma mark - YearViewControllerDelegate
- (void)yearViewController:(YearViewController*)controller didSelectMonthAtDate:(NSDate*)date
{
    CalendarViewController *controllerNew = [self controllerForViewType:CalendarViewMonthType];
    [self moveToNewController:controllerNew atDate:date];
    self.viewChooser.selectedSegmentIndex = CalendarViewMonthType;
    btnCalendarSetting.enabled = YES;
    btnCalendarSwitch.enabled = YES;
    btnCalendarEdit.enabled = YES;
}
#pragma mark - MonthViewControllerDelegate

- (void)monthViewController:(MonthViewController *)controller didSelectDayCellAtDate:(NSDate *)date
{
    CalendarViewController *controllerNew = [self controllerForViewType:CalendarViewDayType];
    [self moveToNewController:controllerNew atDate:date];
    self.viewChooser.selectedSegmentIndex = CalendarViewDayType;
    self.view.userInteractionEnabled = NO;
    leftPaddingContainerCons.constant = 200.0f;
    [AppDelegate sharedDelegate].isSelectedDayViewForBooking = YES;
    [AppDelegate sharedDelegate].isSelectedWeekViewForBooking = NO;
    [UIView animateWithDuration:0.5 delay:0.0 options:UIViewAnimationOptionCurveLinear
                     animations:^(void)
     {
         leftPaddingRecourcesCons.constant = 0.0f;
         [self.view layoutIfNeeded];
     }
                     completion:^(BOOL finished)
     {
         self.view.userInteractionEnabled = YES;
     }
     ];
}
#pragma mark - WeekViewControllerDelegate
- (void)dayViewController:(WeekViewController*)controller didSelectDayCellAtDate:(NSDate*)date
{
    CalendarViewController *controllerNew = [self controllerForViewType:CalendarViewDayType];
    [self moveToNewController:controllerNew atDate:date];
    self.viewChooser.selectedSegmentIndex = CalendarViewDayType;
    self.view.userInteractionEnabled = NO;
    leftPaddingContainerCons.constant = 200.0f;
    [AppDelegate sharedDelegate].isSelectedDayViewForBooking = YES;
    [AppDelegate sharedDelegate].isSelectedWeekViewForBooking = NO;
    [UIView animateWithDuration:0.5 delay:0.0 options:UIViewAnimationOptionCurveLinear
                     animations:^(void)
     {
         leftPaddingRecourcesCons.constant = 0.0f;
         [self.view layoutIfNeeded];
     }
                     completion:^(BOOL finished)
     {
         self.view.userInteractionEnabled = YES;
     }
     ];
}
#pragma mark - CalendarViewControllerDelegate

- (void)calendarViewController:(CalendarViewController*)controller didShowDate:(NSDate*)date
{
    if (controller.class == YearViewController.class)
        [self.dateFormatter setDateFormat:@"yyyy"];
    else
        [self.dateFormatter setDateFormat:@"MMMM yyyy"];
    
    NSString *str = [self.dateFormatter stringFromDate:date];
    self.currentDateLabel.text = str;
    [self.currentDateLabel sizeToFit];
}

- (void)calendarViewController:(CalendarViewController*)controller didSelectEvent:(EKEvent*)event
{
    //NSLog(@"calendarViewController:didSelectEvent");
}

#pragma mark - MGCDayPlannerEKViewControllerDelegate

- (UINavigationController*)navigationControllerForEKEventViewController
{
    //    if (!isiPad) {
    //        return self.navigationController;
    //    }
    return nil;
}
- (EKCalendar *)getCalendarFromFrame:(CGRect)rect{
    NSInteger indexOfArray = 0;
    NSString *calendarName = @"";
    
    CGFloat topOffset = scrLeftNavCV.frame.origin.y + UsersTableView.frame.origin.y;
    CGFloat bottomOffset = topOffset + usersArray.count * 40.0f;
    
    CGFloat yOffset = rect.origin.y + scrLeftNavCV.contentOffset.y;
    
    if (topOffset<=yOffset && yOffset<=bottomOffset) {
        indexOfArray = floor((yOffset-topOffset)/40.0f);
        Users *userInfo = [usersArray objectAtIndex:indexOfArray];
        calendarName = [NSString stringWithFormat:@"FD-U-(%@ %@ %@)", userInfo.firstName, userInfo.middleName, userInfo.lastName];
    }else{
        topOffset = bottomOffset + 40.0f;
        bottomOffset = topOffset + aircraftArray.count*40.0f;
        
        if(topOffset<=yOffset && yOffset<=bottomOffset){
            indexOfArray = floor((yOffset - topOffset)/40.0f);
            Aircraft *aircraft = [aircraftArray objectAtIndex:indexOfArray];
            NSString *aircraftItems = aircraft.aircraftItems;
            NSData *data = [aircraftItems dataUsingEncoding:NSUTF8StringEncoding];
            NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *aircraftReg = @"";
            NSString *aircraftMod = @"";
            for (NSDictionary *fieldInfo in json) {
                if ([[fieldInfo objectForKey:@"fieldName"] isEqualToString:@"Registration"]) {
                    aircraftReg= [fieldInfo objectForKey:@"content"];
                }
                if ([[fieldInfo objectForKey:@"fieldName"] isEqualToString:@"Model"]) {
                    aircraftMod = [fieldInfo objectForKey:@"content"];
                }
            }
            
            calendarName = [NSString stringWithFormat:@"FD-A-(%@ %@)", aircraftReg, aircraftMod];
        }else {
            topOffset = bottomOffset + 40.0f;
            bottomOffset = topOffset + classroomsArray.count*40.0f;
            
            if(topOffset<=yOffset && yOffset<=bottomOffset){
                indexOfArray = floor((yOffset - topOffset)/40.0f);
                calendarName = [NSString stringWithFormat:@"FD-C-(%@)", [classroomsArray objectAtIndex:indexOfArray]];
            }else {
                
            }
        }
    }
    NSArray *calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];
    EKCalendar *calendarToChecked;
    for (EKCalendar *currentCalendar in calendars) {
        if ([currentCalendar.title isEqualToString:calendarName]) {
            calendarToChecked = currentCalendar;
            break;
        }
    }
    
    return calendarToChecked;
}

#pragma mark - EKCalendarChooserDelegate

- (void)calendarChooserSelectionDidChange:(EKCalendarChooser*)calendarChooser
{
    if ([self.calendarViewController respondsToSelector:@selector(setVisibleCalendars:)]) {
        self.calendarViewController.visibleCalendars = calendarChooser.selectedCalendars;
    }
}

- (void)calendarChooserDidFinish:(EKCalendarChooser*)calendarChooser
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)onEditCalendar:(id)sender {
    
    EKCalendarChooserDisplayStyle displayStyle = EKCalendarChooserDisplayAllCalendars;
    if (@available(iOS 11.1, *)) {
        displayStyle = EKCalendarChooserDisplayWritableCalendarsOnly;
    }
    
    if ([self.calendarViewController respondsToSelector:@selector(visibleCalendars)]) {
        self.calendarChooser = [[EKCalendarChooser alloc] initWithSelectionStyle:EKCalendarChooserSelectionStyleMultiple displayStyle:displayStyle eventStore:self.eventStore];
        self.calendarChooser.delegate = self;
        self.calendarChooser.showsDoneButton = YES;
        self.calendarChooser.selectedCalendars = self.calendarViewController.visibleCalendars;
    }
    
    if (self.calendarChooser) {
        UINavigationController *nc = [[UINavigationController alloc]initWithRootViewController:self.calendarChooser];
        //        self.calendarChooser.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(calendarChooserStartEdit)];
        nc.modalPresentationStyle = UIModalPresentationPopover;
        
        [self showDetailViewController:nc sender:self];
        
        UIPopoverPresentationController *popController = nc.popoverPresentationController;
        popController.permittedArrowDirections = UIPopoverArrowDirectionUp;
        popController.sourceView = (UIButton*)sender;
    }
}

- (IBAction)onSwitchCalendar:(id)sender {
    [AppDelegate sharedDelegate].isSelectedIosCalendar = ![AppDelegate sharedDelegate].isSelectedIosCalendar;
    
    NSArray *calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];
    NSMutableSet *selectedCalendars = [[NSMutableSet alloc] init];
    selectedCalendars = [self.calendarViewController.visibleCalendars mutableCopy];
    if ([AppDelegate sharedDelegate].isSelectedIosCalendar == NO) {
        [btnCalendarSwitch setImage:[UIImage imageNamed:@"flightdesk_calendar"] forState:UIControlStateNormal];
        for (EKCalendar *currentCalendar in calendars) {
            NSString *prefixOfCalendar = @"";
            if(currentCalendar.title.length > 3){
                prefixOfCalendar = [currentCalendar.title substringToIndex:3];
            }
            if (![prefixOfCalendar isEqualToString:@"FD-"]) {
                if ([selectedCalendars containsObject:currentCalendar]) {
                    [selectedCalendars removeObject:currentCalendar];
                }
            }
        }
        [UsersTableView reloadData];
        [AircraftTableView reloadData];
        [ClassRoomsTableView reloadData];
    }else{
        [btnCalendarSwitch setImage:[UIImage imageNamed:@"non_flightdesk_calendar"] forState:UIControlStateNormal];
        for (EKCalendar *currentCalendar in calendars) {
            NSString *prefixOfCalendar = @"";
            if(currentCalendar.title.length > 3){
                prefixOfCalendar = [currentCalendar.title substringToIndex:3];
            }
            if (![prefixOfCalendar isEqualToString:@"FD-"]) {
                if (![selectedCalendars containsObject:currentCalendar]) {
                    [selectedCalendars addObject:currentCalendar];
                }
            }
        }
        [UsersTableView reloadData];
        [AircraftTableView reloadData];
        [ClassRoomsTableView reloadData];
    }
    
    self.calendarViewController.visibleCalendars = selectedCalendars;
}

- (IBAction)onSettingCalendar:(id)sender {
    if ([self.calendarViewController isKindOfClass:WeekViewController.class]) {
        UIStoryboard *sb = [UIStoryboard storyboardWithName:@"settings" bundle:nil];
        WeekSettingsViewController *vc = (WeekSettingsViewController*)[sb instantiateViewControllerWithIdentifier:@"dayPlannerSettingsSegue"];
        WeekViewController *weekController = (WeekViewController*)self.calendarViewController;
        vc.weekViewController = weekController;
        vc.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
        UINavigationController *nc = [[UINavigationController alloc]initWithRootViewController:vc];
        nc.modalPresentationStyle = UIModalPresentationPopover;
        BOOL doneButton = (self.traitCollection.verticalSizeClass != UIUserInterfaceSizeClassRegular || self.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassRegular);
        if (doneButton) {
            nc.topViewController.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSettings:)];
        }
        [self showDetailViewController:nc sender:self];
        UIPopoverPresentationController *popController = nc.popoverPresentationController;
        popController.permittedArrowDirections = UIPopoverArrowDirectionUp;
        popController.sourceView = (UIButton*)sender;
    }
    else if ([self.calendarViewController isKindOfClass:MonthViewController.class]) {
        UIStoryboard *sb = [UIStoryboard storyboardWithName:@"settings" bundle:nil];
        MonthSettingsViewController *vc = (MonthSettingsViewController*)[sb instantiateViewControllerWithIdentifier:@"monthPlannerSettingsSegue"];
        MonthViewController *monthController = (MonthViewController*)self.calendarViewController;
        vc.monthPlannerView = monthController.monthPlannerView;
        vc.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
        UINavigationController *nc = [[UINavigationController alloc]initWithRootViewController:vc];
        nc.modalPresentationStyle = UIModalPresentationPopover;
        BOOL doneButton = (self.traitCollection.verticalSizeClass != UIUserInterfaceSizeClassRegular || self.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassRegular);
        if (doneButton) {
            nc.topViewController.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSettings:)];
        }
        [self showDetailViewController:nc sender:self];
        UIPopoverPresentationController *popController = nc.popoverPresentationController;
        popController.permittedArrowDirections = UIPopoverArrowDirectionUp;
        popController.sourceView = (UIButton*)sender;
    }
}

- (IBAction)onToday:(id)sender {
    [self.calendarViewController moveToDate:[NSDate date] animated:YES];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == UsersTableView) {
        return [usersArray count];
    }else if(tableView == AircraftTableView){
        return [aircraftArray count];
    }else{
        return [classroomsArray count];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    return 40.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *simpleTableIdentifier = @"ResourcesItem";
    ResourcesCell *cell = (ResourcesCell *)[tableView dequeueReusableCellWithIdentifier:simpleTableIdentifier];
    if (cell == nil) {
        cell = [ResourcesCell sharedCell];
    }
    NSString *strLabel = @"";
    if (tableView == UsersTableView) {
        Users *userInfo = [usersArray objectAtIndex:indexPath.row];
        strLabel = [NSString stringWithFormat:@"%@ %@ %@",userInfo.firstName,userInfo.middleName,userInfo.lastName];
        if ([arrayUsersCalendarsSelected containsObject:userInfo]) {
            [cell.contentView setBackgroundColor:[UIColor colorWithRed:212.0f/255.0f green:229.0f/255.0f blue:248.0f/255.0f alpha:1.0f]];
        }else{
            [cell.contentView setBackgroundColor:[UIColor clearColor]];
        }
    }else if(tableView == AircraftTableView){
        Aircraft *aircraft = [aircraftArray objectAtIndex:indexPath.row];
        
        NSString *aircraftItems = aircraft.aircraftItems;
        NSData *data = [aircraftItems dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *aircraftReg = @"";
        NSString *aircraftMod = @"";
        for (NSDictionary *fieldInfo in json) {
            if ([[fieldInfo objectForKey:@"fieldName"] isEqualToString:@"Registration"]) {
                aircraftReg= [fieldInfo objectForKey:@"content"];
            }
            if ([[fieldInfo objectForKey:@"fieldName"] isEqualToString:@"Model"]) {
                aircraftMod = [fieldInfo objectForKey:@"content"];
            }
        }
        strLabel = [NSString stringWithFormat:@"%@ %@", aircraftReg, aircraftMod];
        if ([arrayAircraftsCalendarsSelected containsObject:aircraft]) {
            [cell.contentView setBackgroundColor:[UIColor colorWithRed:212.0f/255.0f green:229.0f/255.0f blue:248.0f/255.0f alpha:1.0f]];
        }else{
            [cell.contentView setBackgroundColor:[UIColor clearColor]];
        }
    }else{
        NSString *classroomName = [classroomsArray objectAtIndex:indexPath.row];
        strLabel = classroomName;
        if ([arrayClassroomsCalendarsSelected containsObject:classroomName]) {
            [cell.contentView setBackgroundColor:[UIColor colorWithRed:212.0f/255.0f green:229.0f/255.0f blue:248.0f/255.0f alpha:1.0f]];
        }else{
            [cell.contentView setBackgroundColor:[UIColor clearColor]];
        }
    }
    cell.lblResourceTitle.text = strLabel;
    return cell;
    
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    
    if (tableView == UsersTableView) {
        Users *userInfo = [usersArray objectAtIndex:indexPath.row];
        if ([arrayUsersCalendarsSelected containsObject:userInfo]) {
            [arrayUsersCalendarsSelected removeObject:userInfo];
        }else{
            [arrayUsersCalendarsSelected addObject:userInfo];
        }
        [UsersTableView reloadData];
        
    }else if(tableView == AircraftTableView){
        Aircraft *aircraft = [aircraftArray objectAtIndex:indexPath.row];
        if ([arrayAircraftsCalendarsSelected containsObject:aircraft]) {
            [arrayAircraftsCalendarsSelected removeObject:aircraft];
        }else{
            [arrayAircraftsCalendarsSelected addObject:aircraft];
        }
        [AircraftTableView reloadData];
    }else{
        NSString *classroomName = [classroomsArray objectAtIndex:indexPath.row];
        if ([arrayClassroomsCalendarsSelected containsObject:classroomName]) {
            [arrayClassroomsCalendarsSelected removeObject:classroomName];
        }else{
            [arrayClassroomsCalendarsSelected addObject:classroomName];
        }
        [ClassRoomsTableView reloadData];
    }
    
    [self showingCalendarsSelected];
}
- (void)showingCalendarsSelected{
    NSArray *calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];
    NSMutableSet *selectedCalendars = [[NSMutableSet alloc] init];
    selectedCalendars  = [self.calendarViewController.visibleCalendars mutableCopy];
    for (Users *userInfo in usersArray) {
        for (EKCalendar *currentCalendar in calendars) {
            if ([currentCalendar.title isEqualToString:[NSString stringWithFormat:@"FD-U-(%@ %@ %@)", userInfo.firstName, userInfo.middleName, userInfo.lastName]]) {
                
                BOOL isExit = NO;
                for (EKCalendar *calendarToCheck in selectedCalendars) {
                    if ([calendarToCheck.calendarIdentifier isEqualToString:currentCalendar.calendarIdentifier]) {
                        isExit = YES;
                        break;
                    }
                }
                
                if ([arrayUsersCalendarsSelected containsObject:userInfo]) {
                    if (!isExit) {
                        [selectedCalendars addObject:currentCalendar];
                    }
                }else{
                    if (isExit) {
                        [selectedCalendars removeObject:currentCalendar];
                    }
                }
                break;
            }
        }
    }
    
    for (Aircraft *aircraft in aircraftArray) {
        NSString *aircraftItems = aircraft.aircraftItems;
        NSData *data = [aircraftItems dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *aircraftReg = @"";
        NSString *aircraftMod = @"";
        for (NSDictionary *fieldInfo in json) {
            if ([[fieldInfo objectForKey:@"fieldName"] isEqualToString:@"Registration"]) {
                aircraftReg= [fieldInfo objectForKey:@"content"];
            }
            if ([[fieldInfo objectForKey:@"fieldName"] isEqualToString:@"Model"]) {
                aircraftMod = [fieldInfo objectForKey:@"content"];
            }
        }
        for (EKCalendar *currentCalendar in calendars) {
            
            if ([currentCalendar.title isEqualToString:[NSString stringWithFormat:@"FD-A-(%@ %@)", aircraftReg, aircraftMod]]) {
                
                BOOL isExit = NO;
                for (EKCalendar *calendarToCheck in selectedCalendars) {
                    if ([calendarToCheck.calendarIdentifier isEqualToString:currentCalendar.calendarIdentifier]) {
                        isExit = YES;
                        break;
                    }
                }
                
                if ([arrayAircraftsCalendarsSelected containsObject:aircraft]) {
                    if (!isExit) {
                        [selectedCalendars addObject:currentCalendar];
                    }
                }else{
                    if (isExit) {
                        [selectedCalendars removeObject:currentCalendar];
                    }
                }
                break;
            }
        }
    }
    
    for (NSString *classroom in classroomsArray) {
        for (EKCalendar *currentCalendar in calendars) {
            if ([currentCalendar.title isEqualToString:[NSString stringWithFormat:@"FD-C-(%@)", classroom]]) {
                
                BOOL isExit = NO;
                for (EKCalendar *calendarToCheck in selectedCalendars) {
                    if ([calendarToCheck.calendarIdentifier isEqualToString:currentCalendar.calendarIdentifier]) {
                        isExit = YES;
                        break;
                    }
                }
                
                if ([arrayClassroomsCalendarsSelected containsObject:classroom]) {
                    if (!isExit) {
                        [selectedCalendars addObject:currentCalendar];
                    }
                }else{
                    if (isExit) {
                        [selectedCalendars removeObject:currentCalendar];
                    }
                }
                break;
            }
        }
    }
    
    self.calendarViewController.visibleCalendars = selectedCalendars;
}

#pragma mark UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView*)scrollView
{
    isDragOnFoucesScreen = YES;
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollview
{
    //    if (scrollview.contentOffset.y<0) {
    //        scrLeftNavCV.contentOffset = CGPointMake(0, 0);
    //        return;
    //    }
    //    if ((scrollview.contentSize.height - scrLeftNavCV.frame.size.height)<scrollview.contentOffset.y) {
    //        scrLeftNavCV.contentOffset = CGPointMake(0, scrollview.contentSize.height - scrLeftNavCV.frame.size.height);
    //        return;
    //    }
    self.preNavScrPoint = scrollview.contentOffset;
    if (scrollview == scrLeftNavCV) {
        if ([self.calendarViewController isKindOfClass:DayViewController.class]) {
            [(DayViewController *)self.calendarViewController didScrollWithResources:scrollview.contentOffset];
        }else if ([self.calendarViewController isKindOfClass:WeekViewController.class]) {
            [(WeekViewController *)self.calendarViewController didScrollWithResources:scrollview.contentOffset];
        }
    }
}
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset{
    
    isDragOnFoucesScreen = NO;
}

#pragma mark - DayViewControllerDelegate
- (void)dayViewController:(DayViewController *)controller didScrolledFromMGCDayView:(CGPoint)_point{
    if (_point.y<0 || isDragOnFoucesScreen) {
        return;
    }
    if ((_point.y < 0 && fabs(_point.y) >= scrLeftNavCV.frame.size.height) || (_point.y > 0 && fabs(_point.y) >= scrLeftNavCV.contentSize.height)) {
        scrLeftNavCV.contentOffset = CGPointMake(0, 0);
    }else{
        scrLeftNavCV.contentOffset = _point;
    }
    
}

- (void)onAddingEvent:(id)sender{
    Reachability *reachability = [Reachability reachabilityForInternetConnection];
    [reachability startNotifier];
    NetworkStatus status = [reachability currentReachabilityStatus];
    if (status == NotReachable) {
        // you must be connected to the internet to download documents
        UIAlertController * alert=[UIAlertController alertControllerWithTitle:@"Error" message:@"You have Read-Only status. Conect to the internet." preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* yesButton = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action){
            NSLog(@"you pressed Yes, please button");
        }];
        [alert addAction:yesButton];
        [self presentViewController:alert animated:YES completion:nil];
        
        return;        
    }
    
    AddReservationViewController *vc = [[AddReservationViewController alloc] init];
    NSDate *startDate = [self.calendarViewController getCurrentDate];
    vc.startDate = startDate;
    NSTimeInterval secondsInEightHours = 60 * 60;
    NSDate *dateEightHoursAhead = [startDate dateByAddingTimeInterval:secondsInEightHours];
    vc.endDate = dateEightHoursAhead;
    vc.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
    UINavigationController *nc = [[UINavigationController alloc]initWithRootViewController:vc];
    nc.modalPresentationStyle = UIModalPresentationPopover;
    [self showDetailViewController:nc sender:self];
    UIPopoverPresentationController *popController = nc.popoverPresentationController;
    popController.permittedArrowDirections = UIPopoverArrowDirectionDown;
    popController.delegate = self;
    popController.sourceView = self.containViewOfEventAdding;
}
#pragma mark - UIPopoverPresentationControllerDelegate
- (BOOL)popoverPresentationControllerShouldDismissPopover:(UIPopoverPresentationController *)popoverPresentationController{
    return NO;
}

@end

