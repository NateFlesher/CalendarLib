//
//  AddReservationViewController.m
//  FlightDesk
//
//  Created by jellaliu on 11/10/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import "AddReservationViewController.h"
#import "AlertSelectTableViewController.h"
#import "DateFlightCell.h"

@interface AddReservationViewController ()<HVTableViewDataSource, HVTableViewDelegate, DateFlightCellDelegate, AlertSelectTableViewControllerDelegate, UITextFieldDelegate>
{
    NSMutableArray *arrayUsersCalendarsSelected;
    NSMutableArray *arrayAircraftsCalendarsSelected;
    NSMutableArray *arrayClassroomsCalendarsSelected;
    
    NSMutableArray *usersArray;
    NSMutableArray *aircraftArray;
    NSMutableArray *classroomsArray;
    
    NSMutableArray *preEventsFromLocalIdentify;
    
    NSDate *startDate;
    NSDate *endDate;
    
    NSNumber *groupIDToUpdate;
    
    BOOL isEditableOfEvent;
    
    BOOL isUpdatedSome;
    
}
@end

@implementation AddReservationViewController

@synthesize startDate, endDate;
@synthesize editEvent;
@synthesize doneButton;
@synthesize alertVal;

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Add Reservation";
    if (editEvent) {
        self.title = @"Edit Reservation";
    }
    
    self.calendar = [NSCalendar currentCalendar];
    isUpdatedSome = NO;
    arrayUsersCalendarsSelected = [[NSMutableArray alloc] init];
    arrayAircraftsCalendarsSelected = [[NSMutableArray alloc] init];
    arrayClassroomsCalendarsSelected = [[NSMutableArray alloc] init];
    isEditableOfEvent = YES;
    usersArray = [[NSMutableArray alloc] init];
    aircraftArray = [[NSMutableArray alloc] init];
    classroomsArray = [[NSMutableArray alloc] init];
    
    preEventsFromLocalIdentify = [[NSMutableArray alloc] init];
    
    doneButton = [[UIBarButtonItem alloc]
                                   initWithTitle:@"Done"
                                   style:UIBarButtonItemStyleDone
                                   target:self
                                   action:@selector(onDone:)];
    self.navigationItem.rightBarButtonItem = doneButton;
    
    UIBarButtonItem *cancelBtn = [[UIBarButtonItem alloc]
                                   initWithTitle:@"Cancel"
                                   style:UIBarButtonItemStylePlain
                                   target:self
                                   action:@selector(onCancel:)];
    self.navigationItem.leftBarButtonItem = cancelBtn;
    AddReservationTableView.HVTableViewDelegate = self;
    AddReservationTableView.HVTableViewDataSource = self;
    
    if (editEvent && isEditableOfEvent) {
        btnDeleteConstraint.constant = 44.0f;
        btnDelete.hidden = NO;
        if (editEvent.alarms.count > 0) {
            EKAlarm *ekAlarm = [editEvent.alarms objectAtIndex:0];
            alertVal = ekAlarm.relativeOffset;
        }else{
            alertVal = -1;
        }
    }else{
        alertVal = -1;
        btnDeleteConstraint.constant = 0;
        btnDelete.hidden = YES;
    }
}
- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    if (editEvent) {
        [self getPreEventsFromLocal];
    }
    [self getInitialDataFromLocal];
    
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
- (void)getPreEventsFromLocal{
    [preEventsFromLocalIdentify removeAllObjects];
    
    EKEventStore *eventStore = [[EKEventStore alloc]init];
    NSError *error;
    NSManagedObjectContext *context = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"ResourcesCalendar" inManagedObjectContext:context];
    [request setEntity:entityDescription];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"event_identify == %@", editEvent.eventIdentifier];
    [request setPredicate:predicate];
    NSArray *fetchedResourcesCalendars = [context executeFetchRequest:request error:&error];
    ResourcesCalendar *resourcesCalendar = nil;
    if (fetchedResourcesCalendars == nil) {
        
    } else if (fetchedResourcesCalendars.count == 0) {
        
    } else{
        resourcesCalendar = [fetchedResourcesCalendars objectAtIndex:0];
        groupIDToUpdate = resourcesCalendar.group_id;
        
        if ([resourcesCalendar.isEditable boolValue] == NO) {
            doneButton.enabled = NO;
            isEditableOfEvent = NO;
            btnDelete.hidden = YES;
            btnDeleteConstraint.constant = 0;
        }
        
        Reachability *reachability = [Reachability reachabilityForInternetConnection];
        [reachability startNotifier];
        NetworkStatus status = [reachability currentReachabilityStatus];
        if (status == NotReachable) {
            // you must be connected to the internet to download documents            
            doneButton.enabled = NO;
            isEditableOfEvent = NO;
            btnDelete.hidden = YES;
            btnDeleteConstraint.constant = 0;
            
        }
        request = [[NSFetchRequest alloc] init];
        entityDescription = [NSEntityDescription entityForName:@"ResourcesCalendar" inManagedObjectContext:context];
        [request setEntity:entityDescription];
        predicate = [NSPredicate predicateWithFormat:@"group_id == %@", resourcesCalendar.group_id];
        [request setPredicate:predicate];
        NSArray *fetchedResourcesCalendarsWithGroup = [context executeFetchRequest:request error:&error];
        if (fetchedResourcesCalendarsWithGroup.count >0){
            for (ResourcesCalendar *resourcesCalendarToCheck in fetchedResourcesCalendarsWithGroup) {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                [dict setObject:resourcesCalendarToCheck.calendar_name forKey:@"calendarName"];
                [dict setObject:resourcesCalendarToCheck.group_id forKey:@"group_id"];
                [dict setObject:resourcesCalendarToCheck.event_local_id forKey:@"event_local_id"];
                if (resourcesCalendarToCheck.event_identify != nil) {
                    [dict setObject:resourcesCalendarToCheck.event_identify forKey:@"identify"];
                    [preEventsFromLocalIdentify addObject:dict];
                }
            }
        }
    }
}
- (void)getInitialDataFromLocal{
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
                if (editEvent) {
                    for (NSMutableDictionary *dict in preEventsFromLocalIdentify) {
                        NSString *calendarName = [dict objectForKey:@"calendarName"];
                        if ([calendarName isEqualToString:[NSString stringWithFormat:@"FD-U-(%@ %@ %@)", users.firstName, users.middleName, users.lastName]]) {
                            if (![arrayUsersCalendarsSelected containsObject:users]) {
                                [arrayUsersCalendarsSelected addObject:users];
                                break;
                            }
                        }
                    }
                }
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
            if (editEvent) {
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
                for (NSMutableDictionary *dict in preEventsFromLocalIdentify) {
                    NSString *calendarName = [dict objectForKey:@"calendarName"];
                    if ([calendarName isEqualToString:[NSString stringWithFormat:@"FD-A-(%@ %@)", aircraftReg, aircraftMod]]) {
                        if (![arrayAircraftsCalendarsSelected containsObject:aircraft]) {
                            [arrayAircraftsCalendarsSelected addObject:aircraft];
                            break;
                        }
                    }
                }
            }
        }
    }
    
    [classroomsArray addObject:@"Cirrus Room"];
    [classroomsArray addObject:@"Cessna Room"];
    
    for (NSString *classRoomsName in classroomsArray) {
        if (editEvent) {
            for (NSMutableDictionary *dict in preEventsFromLocalIdentify) {
                NSString *calendarName = [dict objectForKey:@"calendarName"];
                if ([calendarName isEqualToString:[NSString stringWithFormat:@"FD-C-(%@)", classRoomsName]]) {
                    if (![arrayClassroomsCalendarsSelected containsObject:classRoomsName]) {
                        [arrayClassroomsCalendarsSelected addObject:classRoomsName];
                        break;
                    }
                }
            }
        }
    }
    
    if (editEvent) {
        txtTitle.text = editEvent.title;
    }
    
    [AddReservationTableView reloadData];
}


- (BOOL)checkReservationsWithDate:(NSString*)calendarName{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
    [dateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
    
    NSDate *startDateToCheck = [dateFormatter dateFromString:[dateFormatter stringFromDate:startDate]];
    NSDate *endDateToCheck = [dateFormatter dateFromString:[dateFormatter stringFromDate:endDate]];
    
    NSError *error;
    NSManagedObjectContext *context = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"ResourcesCalendar" inManagedObjectContext:context];
    [request setEntity:entityDescription];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"timeIntervalStartDate <= %@ AND timeIntervalEndDate >%@ AND calendar_name=%@", [NSNumber numberWithDouble:[startDateToCheck timeIntervalSince1970] * 1000000], [NSNumber numberWithDouble:[startDateToCheck timeIntervalSince1970] * 1000000], calendarName];
    NSLog(@"%.f, %.f", [startDateToCheck timeIntervalSince1970] * 1000000, [endDateToCheck timeIntervalSince1970] * 1000000);
    [request setPredicate:predicate];
    NSArray *fetchedResourcesCalendars = [context executeFetchRequest:request error:&error];
    if (fetchedResourcesCalendars.count > 0) {
        return NO;
    }
    return YES;
}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)onDone:(id)sender{
    [self reservationSave];
}
- (void)reservationSave{
    if (!txtTitle.text.length)
    {
        [self showAlert:@"Please input First Name" :@"Input Error"];
        return;
    }
    if (arrayUsersCalendarsSelected.count == 0 && arrayAircraftsCalendarsSelected.count == 0 && arrayClassroomsCalendarsSelected.count == 0) {
        [self showAlert:@"Please select resources" :@"Input Error"];
        return;
    }
    
    NSError *error;
    EKEventStore *eventStore = [[EKEventStore alloc]init];
    if ([self.delegate respondsToSelector:@selector(didDoneResevation:)]) {
        [self.delegate didDoneResevation:self];
    }
    if (editEvent) {
        //Update users
        for (Users *userInfo in arrayUsersCalendarsSelected) {
            BOOL isExit = NO;
            for (NSMutableDictionary *dict in preEventsFromLocalIdentify) {
                NSString *calendarName = [dict objectForKey:@"calendarName"];
                NSNumber *eventLocalID = [dict objectForKey:@"event_local_id"];
                EKEvent *eventToUpdate = [eventStore eventWithIdentifier:[dict objectForKey:@"identify"]];
                if ([calendarName isEqualToString:[NSString stringWithFormat:@"FD-U-(%@ %@ %@)", userInfo.firstName, userInfo.middleName, userInfo.lastName]]) {
                    eventToUpdate.title = txtTitle.text;
                    eventToUpdate.startDate = startDate;
                    eventToUpdate.endDate = endDate;
                    if (alertVal >= 0) {
                        EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:alertVal*(-1)];
                        eventToUpdate.alarms = [NSArray arrayWithObject:alarm];
                    }else{
                        eventToUpdate.alarms = nil;
                    }
                    [eventStore saveEvent:eventToUpdate span:EKSpanThisEvent error:&error];
                    if (error != nil) {
                        NSLog(@"Event Saving Error : %@", error.localizedDescription);
                    }
                    isExit = YES;
                    [preEventsFromLocalIdentify removeObject:dict];
                    [self updateCurrentEventInLocal:eventToUpdate withLocalID:eventLocalID];
                    break;
                }
            }
            if (!isExit) {
                EKEvent *ev = [EKEvent eventWithEventStore:eventStore];
                ev.title = txtTitle.text;
                ev.location = @"";
                ev.allDay = NO;
                ev.startDate = startDate;
                ev.endDate = endDate;
                if (alertVal >= 0) {
                    EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:alertVal*(-1)];
                    ev.alarms = [NSArray arrayWithObject:alarm];
                }
                NSArray *calendars = [eventStore calendarsForEntityType:EKEntityTypeEvent];
                for (EKCalendar *currentCalendar in calendars) {
                    if ([currentCalendar.title isEqualToString:[NSString stringWithFormat:@"FD-U-(%@ %@ %@)", userInfo.firstName, userInfo.middleName, userInfo.lastName]]) {
                        ev.calendar = currentCalendar;
                    }
                }
                [eventStore saveEvent:ev span:EKSpanThisEvent error:&error];
                if (error != nil) {
                    NSLog(@"Event Saving Error : %@", error.localizedDescription);
                }
                [self saveCurrentEventToLocal:ev wihtGroupId:groupIDToUpdate withInvitedUserID:userInfo.userID];
            }
        }
        
        //Update aircrafts
        for (Aircraft *aircraft in arrayAircraftsCalendarsSelected) {
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
            BOOL isExit = NO;
            for (NSMutableDictionary *dict in preEventsFromLocalIdentify) {
                NSString *calendarName = [dict objectForKey:@"calendarName"];
                NSNumber *eventLocalID = [dict objectForKey:@"event_local_id"];
                EKEvent *eventToUpdate = [eventStore eventWithIdentifier:[dict objectForKey:@"identify"]];
                if ([calendarName isEqualToString:[NSString stringWithFormat:@"FD-A-(%@ %@)", aircraftReg, aircraftMod]]) {
                    eventToUpdate.title = txtTitle.text;
                    eventToUpdate.startDate = startDate;
                    eventToUpdate.endDate = endDate;
                    if (alertVal >= 0) {
                        EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:alertVal*(-1)];
                        eventToUpdate.alarms = [NSArray arrayWithObject:alarm];
                    }else{
                        eventToUpdate.alarms = nil;
                    }
                    [eventStore saveEvent:eventToUpdate span:EKSpanThisEvent error:&error];
                    if (error != nil) {
                        NSLog(@"Event Saving Error : %@", error.localizedDescription);
                    }
                    isExit = YES;
                    [preEventsFromLocalIdentify removeObject:dict];
                    [self updateCurrentEventInLocal:eventToUpdate withLocalID:eventLocalID];
                    break;
                }
            }
            if (!isExit) {
                EKEvent *ev = [EKEvent eventWithEventStore:eventStore];
                ev.title = txtTitle.text;
                ev.location = @"";
                ev.allDay = NO;
                ev.startDate = startDate;
                ev.endDate = endDate;
                if (alertVal >= 0) {
                    EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:alertVal*(-1)];
                    ev.alarms = [NSArray arrayWithObject:alarm];
                }
                NSArray *calendars = [eventStore calendarsForEntityType:EKEntityTypeEvent];
                for (EKCalendar *currentCalendar in calendars) {
                    if ([currentCalendar.title isEqualToString:[NSString stringWithFormat:@"FD-A-(%@ %@)", aircraftReg, aircraftMod]]) {
                        ev.calendar = currentCalendar;
                    }
                }
                [eventStore saveEvent:ev span:EKSpanThisEvent error:&error];
                if (error != nil) {
                    NSLog(@"Event Saving Error : %@", error.localizedDescription);
                }
                [self saveCurrentEventToLocal:ev wihtGroupId:groupIDToUpdate withInvitedUserID:@0];
            }
        }
        //Update classrooms
        for (NSString *classroomName in arrayClassroomsCalendarsSelected) {
            BOOL isExit = NO;
            for (NSMutableDictionary *dict in preEventsFromLocalIdentify) {
                NSString *calendarName = [dict objectForKey:@"calendarName"];
                NSNumber *eventLocalID = [dict objectForKey:@"event_local_id"];
                EKEvent *eventToUpdate = [eventStore eventWithIdentifier:[dict objectForKey:@"identify"]];
                if ([calendarName isEqualToString:[NSString stringWithFormat:@"FD-C-(%@)", classroomName]]) {
                    eventToUpdate.title = txtTitle.text;
                    eventToUpdate.startDate = startDate;
                    eventToUpdate.endDate = endDate;
                    if (alertVal >= 0) {
                        EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:alertVal*(-1)];
                        eventToUpdate.alarms = [NSArray arrayWithObject:alarm];
                    }else{
                        eventToUpdate.alarms = nil;
                    }
                    [eventStore saveEvent:eventToUpdate span:EKSpanThisEvent error:&error];
                    if (error != nil) {
                        NSLog(@"Event Saving Error : %@", error.localizedDescription);
                    }
                    isExit = YES;
                    [preEventsFromLocalIdentify removeObject:dict];
                    [self updateCurrentEventInLocal:eventToUpdate withLocalID:eventLocalID];
                    break;
                }
            }
            if (!isExit) {
                EKEvent *ev = [EKEvent eventWithEventStore:eventStore];
                ev.title = txtTitle.text;
                ev.location = @"";
                ev.allDay = NO;
                ev.startDate = startDate;
                ev.endDate = endDate;
                if (alertVal >= 0) {
                    EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:alertVal*(-1)];
                    ev.alarms = [NSArray arrayWithObject:alarm];
                }
                NSArray *calendars = [eventStore calendarsForEntityType:EKEntityTypeEvent];
                for (EKCalendar *currentCalendar in calendars) {
                    if ([currentCalendar.title isEqualToString:[NSString stringWithFormat:@"FD-C-(%@)", classroomName]]) {
                        ev.calendar = currentCalendar;
                    }
                }
                [eventStore saveEvent:ev span:EKSpanThisEvent error:&error];
                if (error != nil) {
                    NSLog(@"Event Saving Error : %@", error.localizedDescription);
                }
                [self saveCurrentEventToLocal:ev wihtGroupId:groupIDToUpdate withInvitedUserID:@0];
            }
        }
        
        //Delete remaining events
        for (NSMutableDictionary *dict in preEventsFromLocalIdentify) {
            EKEvent *eventToUpdate = [eventStore eventWithIdentifier:[dict objectForKey:@"identify"]];
            NSNumber *localIdToDelete = [dict objectForKey:@"event_local_id"];
            if (eventToUpdate) {
                NSManagedObjectContext *context = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
                NSFetchRequest *request = [[NSFetchRequest alloc] init];
                NSError *error;
                NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"ResourcesCalendar" inManagedObjectContext:context];
                [request setEntity:entityDescription];
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"event_local_id == %@", localIdToDelete];
                [request setPredicate:predicate];
                NSArray *fetchedResourcesCalendars = [context executeFetchRequest:request error:&error];
                if (fetchedResourcesCalendars == nil) {
                } else if (fetchedResourcesCalendars.count == 0) {
                } else{
                    for (ResourcesCalendar *resourcesCalendarToDel in fetchedResourcesCalendars) {
                        if ([resourcesCalendarToDel.event_id integerValue] != 0) {
                            DeleteQuery *deleteQueryForAssignment = [NSEntityDescription insertNewObjectForEntityForName:@"DeleteQuery" inManagedObjectContext:context];
                            deleteQueryForAssignment.type = @"resourcesCalendars";
                            deleteQueryForAssignment.idToDelete = resourcesCalendarToDel.event_id;
                            [context save:&error];
                            if (error) {
                                NSLog(@"Error when saving managed object context : %@", error);
                            }
                        }
                        [context deleteObject:resourcesCalendarToDel];
                        [context save:&error];
                    }
                }
                [context save:&error];
                if (error) {
                    NSLog(@"Error when saving managed object context : %@", error);
                }
                
                [eventStore removeEvent:eventToUpdate span:EKSpanThisEvent error:&error];
                if (error != nil) {
                    NSLog(@"Event Saving Error : %@", error.localizedDescription);
                }
            }
        }
        [preEventsFromLocalIdentify removeAllObjects];
    }else{
        NSNumber *groupID = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] * 1000000];
        for (Users *userInfo in arrayUsersCalendarsSelected) {
            EKEvent *ev = [EKEvent eventWithEventStore:eventStore];
            ev.title = txtTitle.text;
            ev.location = @"";
            ev.allDay = NO;
            ev.startDate = startDate;
            ev.endDate = endDate;
            if (alertVal >= 0) {
                EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:alertVal*(-1)];
                ev.alarms = [NSArray arrayWithObject:alarm];
            }
            
            NSArray *calendars = [eventStore calendarsForEntityType:EKEntityTypeEvent];
            for (EKCalendar *currentCalendar in calendars) {
                if ([currentCalendar.title isEqualToString:[NSString stringWithFormat:@"FD-U-(%@ %@ %@)", userInfo.firstName, userInfo.middleName, userInfo.lastName]]) {
                    ev.calendar = currentCalendar;
                }
            }
            [eventStore saveEvent:ev span:EKSpanThisEvent error:&error];
            if (error != nil) {
                NSLog(@"Event Saving Error : %@", error.localizedDescription);
            }
            [self saveCurrentEventToLocal:ev wihtGroupId:groupID withInvitedUserID:userInfo.userID];
        }
        for (Aircraft *aircraft in arrayAircraftsCalendarsSelected) {
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
            
            EKEvent *ev = [EKEvent eventWithEventStore:eventStore];
            ev.title = txtTitle.text;
            ev.location = @"";
            ev.allDay = NO;
            ev.startDate = startDate;
            ev.endDate = endDate;
            if (alertVal >= 0) {
                EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:alertVal*(-1)];
                ev.alarms = [NSArray arrayWithObject:alarm];
            }
            NSArray *calendars = [eventStore calendarsForEntityType:EKEntityTypeEvent];
            for (EKCalendar *currentCalendar in calendars) {
                if ([currentCalendar.title isEqualToString:[NSString stringWithFormat:@"FD-A-(%@ %@)", aircraftReg, aircraftMod]]) {
                    ev.calendar = currentCalendar;
                }
            }
            [eventStore saveEvent:ev span:EKSpanThisEvent error:&error];
            if (error != nil) {
                NSLog(@"Event Saving Error : %@", error.localizedDescription);
            }
            [self saveCurrentEventToLocal:ev wihtGroupId:groupID withInvitedUserID:@0];
        }
        for (NSString *classroomName in arrayClassroomsCalendarsSelected) {
            EKEvent *ev = [EKEvent eventWithEventStore:eventStore];
            ev.title = txtTitle.text;
            ev.location = @"";
            ev.allDay = NO;
            ev.startDate = startDate;
            ev.endDate = endDate;
            if (alertVal >= 0) {
                EKAlarm *alarm = [EKAlarm alarmWithRelativeOffset:alertVal*(-1)];
                ev.alarms = [NSArray arrayWithObject:alarm];
            }
            
            NSArray *calendars = [eventStore calendarsForEntityType:EKEntityTypeEvent];
            for (EKCalendar *currentCalendar in calendars) {
                if ([currentCalendar.title isEqualToString:[NSString stringWithFormat:@"FD-C-(%@)", classroomName]]) {
                    ev.calendar = currentCalendar;
                }
            }
            [eventStore saveEvent:ev span:EKSpanThisEvent error:&error];
            if (error != nil) {
                NSLog(@"Event Saving Error : %@", error.localizedDescription);
            }
            [self saveCurrentEventToLocal:ev wihtGroupId:groupID withInvitedUserID:@0];
        }
    }
    UIAlertController * alert=[UIAlertController alertControllerWithTitle:@"Flight Desk" message:@"Saved!" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* yesButton = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action){
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
    [alert addAction:yesButton];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)updateCurrentEventInLocal:(EKEvent *)event withLocalID:(NSNumber *)eventLocalId{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
    [dateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
    
    NSManagedObjectContext *context = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    NSError *error;
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"ResourcesCalendar" inManagedObjectContext:context];
    [request setEntity:entityDescription];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"event_local_id == %@", eventLocalId];
    [request setPredicate:predicate];
    NSArray *fetchedResourcesCalendars = [context executeFetchRequest:request error:&error];
    ResourcesCalendar *resourcesCalendar = nil;
    if (fetchedResourcesCalendars == nil) {
        
    } else if (fetchedResourcesCalendars.count == 0) {
        
    } else{
        resourcesCalendar = [fetchedResourcesCalendars objectAtIndex:0];
        resourcesCalendar.title = event.title;
        resourcesCalendar.endDate = [dateFormatter stringFromDate:event.endDate];
        resourcesCalendar.event_identify = event.eventIdentifier;
        resourcesCalendar.lastUpdate = @0;
        resourcesCalendar.lastSync = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] * 1000000];
        resourcesCalendar.startDate = [dateFormatter stringFromDate:event.startDate];
        resourcesCalendar.timeIntervalStartDate = [NSNumber numberWithDouble:[event.startDate timeIntervalSince1970] * 1000000];
        resourcesCalendar.timeIntervalEndDate = [NSNumber numberWithDouble:[event.endDate timeIntervalSince1970] * 1000000];
        
        resourcesCalendar.alertTimeInterVal = [NSNumber numberWithInt:(int)alertVal];
        
    }
    [context save:&error];
    if (error) {
        NSLog(@"Error when saving managed object context : %@", error);
    }
}
- (void)saveCurrentEventToLocal:(EKEvent *)event wihtGroupId:(NSNumber *)groupID withInvitedUserID:(NSNumber*)invitedUserID{
    NSString *prefixOfCalendar = @"";
    if(event.calendar.title.length > 3){
       prefixOfCalendar = [event.calendar.title substringToIndex:3];
    }
    if (![prefixOfCalendar isEqualToString:@"FD-"]) {
        return;
    }
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
    [dateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
    
    NSManagedObjectContext *context = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    NSError *error;
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"ResourcesCalendar" inManagedObjectContext:context];
    [request setEntity:entityDescription];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"event_identify == %@", event.eventIdentifier];
    [request setPredicate:predicate];
    NSArray *fetchedResourcesCalendars = [context executeFetchRequest:request error:&error];
    ResourcesCalendar *resourcesCalendar = nil;
    if (fetchedResourcesCalendars == nil) {
        FDLogError(@"Skipped resourcesCalendar update since there was an error checking for existing resourcesCalendar!");
    } else if (fetchedResourcesCalendars.count == 0) {
        resourcesCalendar = [NSEntityDescription insertNewObjectForEntityForName:@"ResourcesCalendar" inManagedObjectContext:context];
        resourcesCalendar.event_id = @0;
        resourcesCalendar.title = @"";
        if (event.title) {
            resourcesCalendar.title = event.title;
        }
        resourcesCalendar.calendar_identify = event.calendar.calendarIdentifier;
        resourcesCalendar.calendar_name = event.calendar.title;
        resourcesCalendar.endDate = [dateFormatter stringFromDate:event.endDate];
        resourcesCalendar.event_identify = event.eventIdentifier;
        resourcesCalendar.event_local_id = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] * 1000000];
        resourcesCalendar.group_id = groupID;
        resourcesCalendar.lastUpdate = @0;
        resourcesCalendar.lastSync = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] * 1000000];
        resourcesCalendar.startDate = [dateFormatter stringFromDate:event.startDate];
        resourcesCalendar.user_id = [NSNumber numberWithInteger:[[AppDelegate sharedDelegate].userId integerValue]];
        resourcesCalendar.invitedUser_id = invitedUserID;
        resourcesCalendar.isEditable = @YES;
        
        resourcesCalendar.alertTimeInterVal = [NSNumber numberWithInt:(int)alertVal];
        resourcesCalendar.timeIntervalStartDate = [NSNumber numberWithDouble:[event.startDate timeIntervalSince1970] * 1000000];
        resourcesCalendar.timeIntervalEndDate = [NSNumber numberWithDouble:[event.endDate timeIntervalSince1970] * 1000000];
    } else{
        resourcesCalendar = [fetchedResourcesCalendars objectAtIndex:0];
        if (event.title) {
            resourcesCalendar.title = event.title;
        }
        resourcesCalendar.calendar_identify = event.calendar.calendarIdentifier;
        resourcesCalendar.calendar_name = event.calendar.title;
        resourcesCalendar.endDate = [dateFormatter stringFromDate:event.endDate];
        resourcesCalendar.event_identify = event.eventIdentifier;
        resourcesCalendar.event_local_id = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] * 1000000];
        resourcesCalendar.group_id = groupID;
        resourcesCalendar.lastUpdate = @0;
        resourcesCalendar.alertTimeInterVal = [NSNumber numberWithInt:(int)alertVal];
        resourcesCalendar.lastSync = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] * 1000000];
        resourcesCalendar.startDate = [dateFormatter stringFromDate:event.startDate];
        resourcesCalendar.user_id = [NSNumber numberWithInteger:[[AppDelegate sharedDelegate].userId integerValue]];
        resourcesCalendar.invitedUser_id = invitedUserID;
        resourcesCalendar.isEditable = @YES;
        resourcesCalendar.timeIntervalStartDate = [NSNumber numberWithDouble:[event.startDate timeIntervalSince1970] * 1000000];
        resourcesCalendar.timeIntervalEndDate = [NSNumber numberWithDouble:[event.endDate timeIntervalSince1970] * 1000000];
    }
    [context save:&error];
    if (error) {
        NSLog(@"Error when saving managed object context : %@", error);
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
- (void)onCancel:(id)send{
    BOOL isConnectedToInternet = YES;
    Reachability *reachability = [Reachability reachabilityForInternetConnection];
    [reachability startNotifier];
    NetworkStatus status = [reachability currentReachabilityStatus];
    if (status == NotReachable) {
        isConnectedToInternet = NO;
        
    }
    if (isConnectedToInternet == YES && isUpdatedSome == YES) {
        UIAlertController * alert=[UIAlertController alertControllerWithTitle:@"Flight Desk" message:@"Do you want to save your changes before exiting?" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* yesButton = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action){
            NSLog(@"you pressed Yes, please button");
        }];
        UIAlertAction* noButton = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action){
            if ([self.delegate respondsToSelector:@selector(didCancelResevation:)]) {
                [self.delegate didCancelResevation:self];
            }
            [self dismissViewControllerAnimated:YES completion:nil];
        }];
        [alert addAction:yesButton];
        [alert addAction:noButton];
        [self presentViewController:alert animated:YES completion:nil];
    }else{
        if ([self.delegate respondsToSelector:@selector(didCancelResevation:)]) {
            [self.delegate didCancelResevation:self];
        }
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    
}

#pragma mark DateFlightCellDelegate
- (void)didChangeDate:(DateFlightCell *)_cell withDate:(NSDate *)_date{
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
    
    _cell.dateValue.text = [dateFormatter stringFromDate:_date];
    NSIndexPath *indexPath = [AddReservationTableView indexPathForCell:_cell];
    if (indexPath.row == 0) {
        startDate = _date;
    }else if(indexPath.row == 1){
        endDate = _date;
    }
}
#pragma mark - Table view data source

#pragma mark HVTableViewDatasource
-(void)tableView:(UITableView *)tableView expandCell:(DateFlightCell *)cell withIndexPath:(NSIndexPath *)indexPath{
    isUpdatedSome = YES;
    if (!isEditableOfEvent) {
        return;
    }
    if (indexPath.section == 4) {
        [UIView animateWithDuration:0.5 animations:^(void)
         {
             cell.datePicker.hidden = NO;
         }
         completion:^(BOOL finished)
         {
             [AddReservationTableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:indexPath.section]
                                   atScrollPosition:UITableViewScrollPositionBottom
                                           animated:YES];
         }
         ];
    }else if (indexPath.section == 3){
        AlertSelectTableViewController *alertSectionVC = [[AlertSelectTableViewController alloc] initWithAlertVal:alertVal];
        alertSectionVC.alertSelectDelegate = self;
        [self.navigationController pushViewController:alertSectionVC animated:YES];
    }else{
        if (indexPath.section == 0) {
            Users *userInfo = [usersArray objectAtIndex:indexPath.row];
            if (![arrayUsersCalendarsSelected containsObject:userInfo]) {
                if (![[AppDelegate sharedDelegate].userLevel.lowercaseString isEqualToString:@"admin"]) {
                    [arrayUsersCalendarsSelected removeAllObjects];
                }
                [arrayUsersCalendarsSelected addObject:userInfo];
            }else{
                [arrayUsersCalendarsSelected removeObject:userInfo];
            }
            
        }else if(indexPath.section == 1){
            Aircraft *aircraft = [aircraftArray objectAtIndex:indexPath.row];
            if (![arrayAircraftsCalendarsSelected containsObject:aircraft]) {
                if (![[AppDelegate sharedDelegate].userLevel.lowercaseString isEqualToString:@"admin"]) {
                    [arrayAircraftsCalendarsSelected removeAllObjects];
                }
                [arrayAircraftsCalendarsSelected addObject:aircraft];
            }else{
                [arrayAircraftsCalendarsSelected removeObject:aircraft];
            }
        }else if(indexPath.section == 2){
            NSString *classroomName = [classroomsArray objectAtIndex:indexPath.row];
            if (![arrayClassroomsCalendarsSelected containsObject:classroomName]) {
                if (![[AppDelegate sharedDelegate].userLevel.lowercaseString isEqualToString:@"admin"]) {
                    [arrayClassroomsCalendarsSelected removeAllObjects];
                }
                [arrayClassroomsCalendarsSelected addObject:classroomName];
            }else{
                [arrayClassroomsCalendarsSelected removeObject:classroomName];
            }
        }
        [AddReservationTableView reloadData];
    }
    
}

-(void)tableView:(UITableView *)tableView collapseCell:(DateFlightCell *)cell withIndexPath:(NSIndexPath *)indexPath{
    isUpdatedSome = YES;
    if (!isEditableOfEvent) {
        return;
    }
    if (indexPath.section == 4) {
        [UIView animateWithDuration:0.5 animations:^(void)
         {
             cell.datePicker.hidden = YES;
         }
                         completion:^(BOOL finished)
         {
             [AddReservationTableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:indexPath.section]
                                            atScrollPosition:UITableViewScrollPositionBottom
                                                    animated:YES];
         }
         ];
    }else if (indexPath.section == 3){
        AlertSelectTableViewController *alertSectionVC = [[AlertSelectTableViewController alloc] initWithAlertVal:alertVal];
        alertSectionVC.alertSelectDelegate = self;
        [self.navigationController pushViewController:alertSectionVC animated:YES];
    }else{
        if (indexPath.section == 0) {
            Users *userInfo = [usersArray objectAtIndex:indexPath.row];
            if (![arrayUsersCalendarsSelected containsObject:userInfo]) {
                if (![[AppDelegate sharedDelegate].userLevel.lowercaseString isEqualToString:@"admin"]) {
                    [arrayUsersCalendarsSelected removeAllObjects];
                }
                [arrayUsersCalendarsSelected addObject:userInfo];
            }else{
                [arrayUsersCalendarsSelected removeObject:userInfo];
            }
            
        }else if(indexPath.section == 1){
            Aircraft *aircraft = [aircraftArray objectAtIndex:indexPath.row];
            if (![arrayAircraftsCalendarsSelected containsObject:aircraft]) {
                if (![[AppDelegate sharedDelegate].userLevel.lowercaseString isEqualToString:@"admin"]) {
                    [arrayAircraftsCalendarsSelected removeAllObjects];
                }
                [arrayAircraftsCalendarsSelected addObject:aircraft];
            }else{
                [arrayAircraftsCalendarsSelected removeObject:aircraft];
            }
        }else if(indexPath.section == 2){
            NSString *classroomName = [classroomsArray objectAtIndex:indexPath.row];
            if (![arrayClassroomsCalendarsSelected containsObject:classroomName]) {
                if (![[AppDelegate sharedDelegate].userLevel.lowercaseString isEqualToString:@"admin"]) {
                    [arrayClassroomsCalendarsSelected removeAllObjects];
                }
                [arrayClassroomsCalendarsSelected addObject:classroomName];
            }else{
                [arrayClassroomsCalendarsSelected removeObject:classroomName];
            }
        }
        [AddReservationTableView reloadData];
    }
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
    switch (section) {
        case 0:
            if ([[AppDelegate sharedDelegate].userLevel.lowercaseString isEqualToString:@"student"]) {
                return @"Instructors";
            }else{
                return @"Students";
            }
            break;
        case 1:
            return @"Aircrafts";
            break;
        case 2:
            return @"Classrooms";
            break;
        case 3:
            return @"Alert";
            break;
        case 4:
            return @"Date Range";
            break;
            
        default:
            return @"";
            break;
    }
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    switch (section) {
        case 0:
            return usersArray.count;
            break;
        case 1:
            return aircraftArray.count;
            break;
        case 2:
            return classroomsArray.count;
            break;
        case 3:
            return 1;
            break;
        case 4:
            return 2;
            break;
            
        default:
            return 0;
            break;
    }
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath isExpanded:(BOOL)isExpanded
{
    if (indexPath.section == 0 || indexPath.section == 1 || indexPath.section == 2) {
        static NSString *sortTableViewIdentifier = @"Resevationitem";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sortTableViewIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:sortTableViewIdentifier];
        }
        NSString *strLabel = @"";
        switch (indexPath.section) {
            case 0:
            {
                Users *userInfo = [usersArray objectAtIndex:indexPath.row];
                strLabel = [NSString stringWithFormat:@"%@ %@ %@",userInfo.firstName,userInfo.middleName,userInfo.lastName];
                if ([arrayUsersCalendarsSelected containsObject:userInfo]) {
                    [cell.contentView setBackgroundColor:[UIColor colorWithRed:212.0f/255.0f green:229.0f/255.0f blue:248.0f/255.0f alpha:1.0f]];
                }else{
                    [cell.contentView setBackgroundColor:[UIColor clearColor]];
                }
                break;
            }
            case 1:
            {
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
                break;
            }
            case 2:
            {
                NSString *classroomName = [classroomsArray objectAtIndex:indexPath.row];
                strLabel = classroomName;
                if ([arrayClassroomsCalendarsSelected containsObject:classroomName]) {
                    [cell.contentView setBackgroundColor:[UIColor colorWithRed:212.0f/255.0f green:229.0f/255.0f blue:248.0f/255.0f alpha:1.0f]];
                }else{
                    [cell.contentView setBackgroundColor:[UIColor clearColor]];
                }
                break;
            }
            default:
                break;
        }
        for (UIView *subViews in cell.contentView.subviews) {
            [subViews removeFromSuperview];
        }
        UILabel *contentName = [[UILabel alloc] initWithFrame:CGRectMake(30, 0, self.view.bounds.size.width-40, 44.0f)];
        contentName.font = [UIFont fontWithName:@"Helvetica" size:15];
        contentName.backgroundColor = [UIColor clearColor];
        contentName.textColor = [UIColor darkGrayColor];
        [cell.contentView addSubview:contentName];
        contentName.text = strLabel;
        
        NSString *calendarName = @"";
        switch (indexPath.section) {
            case 0:
                calendarName = [NSString stringWithFormat:@"FD-U-(%@)", strLabel];
                break;
            case 1:
                calendarName = [NSString stringWithFormat:@"FD-A-(%@)", strLabel];
                break;
            case 2:
                calendarName = [NSString stringWithFormat:@"FD-C-(%@)", strLabel];
                break;
            default:
                break;
        }
        BOOL isAovidToEditEvent = NO;
        for (NSMutableDictionary *dict in preEventsFromLocalIdentify) {
            NSString *calendarNameToCheck = [dict objectForKey:@"calendarName"];
            if ([calendarNameToCheck isEqualToString:calendarName]) {
                isAovidToEditEvent = YES;
            }
        }
        if (isEditableOfEvent && !isAovidToEditEvent) {
            
            if (![self checkReservationsWithDate:calendarName]) {
                UILabel *lblBooked = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width-70, 0, 70, 44.0f)];
                lblBooked.font = [UIFont fontWithName:@"Helvetica" size:15];
                lblBooked.backgroundColor = [UIColor clearColor];
                lblBooked.textColor = [UIColor redColor];
                lblBooked.text = @"Booked";
                [cell.contentView addSubview:lblBooked];
                [cell.contentView setBackgroundColor:[UIColor colorWithRed:0.93f green:0.93f blue:0.93f alpha:1.0f]];
                contentName.textColor = [UIColor lightGrayColor];
                
                switch (indexPath.section) {
                    case 0:
                    {
                        Users *userInfo = [usersArray objectAtIndex:indexPath.row];
                        if ([arrayUsersCalendarsSelected containsObject:userInfo]) {
                            [arrayUsersCalendarsSelected removeObject:userInfo];
                        }
                        break;
                    }
                    case 1:
                    {
                        Aircraft *aircraft = [aircraftArray objectAtIndex:indexPath.row];
                        if ([arrayAircraftsCalendarsSelected containsObject:aircraft]) {
                            [arrayAircraftsCalendarsSelected removeObject:aircraft];
                        }
                        break;
                    }
                    case 2:
                    {
                        NSString *classroomName = [classroomsArray objectAtIndex:indexPath.row];
                        strLabel = classroomName;
                        if ([arrayClassroomsCalendarsSelected containsObject:classroomName]) {
                            [arrayClassroomsCalendarsSelected removeObject:classroomName];
                        }
                        break;
                    }
                    default:
                        break;
                }
                
            }
        }
        
        return cell;
    }else if (indexPath.section == 3){
        static NSString *sortTableViewIdentifier = @"Resevationitem";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sortTableViewIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:sortTableViewIdentifier];
        }
        
        for (UIView *subViews in cell.contentView.subviews) {
            [subViews removeFromSuperview];
        }
//        UILabel *alertLbl = [[UILabel alloc] initWithFrame:CGRectMake(30, 0, self.view.bounds.size.width-40, 44.0f)];
//        alertLbl.font = [UIFont fontWithName:@"Helvetica" size:17];
//        alertLbl.backgroundColor = [UIColor clearColor];
//        alertLbl.textColor = [UIColor blackColor];
//        alertLbl.text = @"Alert";
//        [cell.contentView addSubview:alertLbl];
        
        UILabel *alertValLbl = [[UILabel alloc] initWithFrame:CGRectMake(30, 0, self.view.bounds.size.width-40, 44.0f)];
        alertValLbl.font = [UIFont fontWithName:@"Helvetica" size:15];
        alertValLbl.backgroundColor = [UIColor clearColor];
        alertValLbl.textColor = [UIColor darkGrayColor];
        
        if (alertVal >= 0 ) {
            switch ((int)alertVal) {
                case 0:
                    alertValLbl.text = @"At time of event";
                    break;
                case 300:
                    alertValLbl.text = @"5 minutes before";
                    break;
                case 900:
                    alertValLbl.text = @"15 minutes before";
                    break;
                case 1800:
                    alertValLbl.text = @"30 minutes before";
                    break;
                case 3600:
                    alertValLbl.text = @"1 hour before";
                    break;
                case 7200:
                    alertValLbl.text = @"2 hours before";
                    break;
                case 86400:
                    alertValLbl.text = @"1 day before";
                    break;
                case 172800:
                    alertValLbl.text = @"2 days before";
                    break;
                case 604800:
                    alertValLbl.text = @"1 week before";
                    break;
                    
                default:
                    alertValLbl.text = @"None";
                    break;
            }
        }else{
            alertValLbl.text = @"None";
        }
        [cell.contentView addSubview:alertValLbl];
        
        
        UILabel *arrowLbl = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width-30, 0, 30, 44.0f)];
        arrowLbl.font = [UIFont fontWithName:@"Helvetica" size:15];
        arrowLbl.backgroundColor = [UIColor clearColor];
        arrowLbl.textColor = [UIColor lightGrayColor];
        arrowLbl.text = @">";
        [cell.contentView addSubview:arrowLbl];
        return cell;
    }else{
        static NSString *simpleTableIdentifier = @"DateFlightItem";
        DateFlightCell *cell = (DateFlightCell *)[tableView dequeueReusableCellWithIdentifier:simpleTableIdentifier];
        if (cell == nil) {
            cell = [DateFlightCell sharedCell];
        }
        cell.delegate = self;
        
        NSDateFormatter *dateFormattercell = [[NSDateFormatter alloc] init];
        [dateFormattercell setDateFormat:@"yyyy-MM-dd HH:mm"];
        [dateFormattercell setTimeZone:[NSTimeZone localTimeZone]];
        
        if (indexPath.row == 0) {
            cell.lblDateType.text = @"Start Date";
            cell.dateValue.text = [dateFormattercell stringFromDate:startDate];
            [cell.datePicker setDate:[dateFormattercell dateFromString:[dateFormattercell stringFromDate:startDate]]];
        }else {
            cell.dateValue.text = [dateFormattercell stringFromDate:endDate];
            cell.lblDateType.text = @"End Date";
            [cell.datePicker setDate:[dateFormattercell dateFromString:[dateFormattercell stringFromDate:endDate]]];
        }
        
        if (!isExpanded) {
            cell.datePicker.hidden = YES;
        }
        else
        {
            cell.datePicker.hidden = NO;
        }
        
        return cell;
    }
    
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath isExpanded:(BOOL)isexpanded
{
    if (indexPath.section == 4 && isexpanded && isEditableOfEvent){
        return 227.0f;
    }
    return 44.0f;
}

- (IBAction)onAllDelete:(UIButton *)sender {
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Delete Reservation" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        
        EKEventStore *eventStore = [[EKEventStore alloc]init];
        for (NSMutableDictionary *dict in preEventsFromLocalIdentify) {
            EKEvent *eventToUpdate = [eventStore eventWithIdentifier:[dict objectForKey:@"identify"]];
            NSNumber *localIdToDelete = [dict objectForKey:@"event_local_id"];
            if (eventToUpdate) {
                NSManagedObjectContext *context = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
                NSFetchRequest *request = [[NSFetchRequest alloc] init];
                NSError *error;
                NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"ResourcesCalendar" inManagedObjectContext:context];
                [request setEntity:entityDescription];
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"event_local_id == %@", localIdToDelete];
                [request setPredicate:predicate];
                NSArray *fetchedResourcesCalendars = [context executeFetchRequest:request error:&error];
                if (fetchedResourcesCalendars == nil) {
                } else if (fetchedResourcesCalendars.count == 0) {
                } else{
                    for (ResourcesCalendar *resourcesCalendarToDel in fetchedResourcesCalendars) {
                        if ([resourcesCalendarToDel.event_id integerValue] != 0) {
                            DeleteQuery *deleteQueryForAssignment = [NSEntityDescription insertNewObjectForEntityForName:@"DeleteQuery" inManagedObjectContext:context];
                            deleteQueryForAssignment.type = @"resourcesCalendars";
                            deleteQueryForAssignment.idToDelete = resourcesCalendarToDel.event_id;
                            [context save:&error];
                            if (error) {
                                NSLog(@"Error when saving managed object context : %@", error);
                            }
                        }
                        [context deleteObject:resourcesCalendarToDel];
                        [context save:&error];
                    }
                }
                [context save:&error];
                if (error) {
                    NSLog(@"Error when saving managed object context : %@", error);
                }
                
                [eventStore removeEvent:eventToUpdate span:EKSpanThisEvent error:&error];
                if (error != nil) {
                    NSLog(@"Event Saving Error : %@", error.localizedDescription);
                }
            }
        }
        
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        
    }]];
    
    // Present action sheet.
    [self presentViewController:actionSheet animated:YES completion:nil];
    
}

#pragma mark AlertSelectTableViewControllerDelegate
- (void)didSetAlertVal:(NSTimeInterval)_timeInterval{
    alertVal = _timeInterval;
    [AddReservationTableView reloadData];
}

#pragma mark UITextFieldDelegate
- (void)textFieldDidBeginEditing:(UITextField *)textField{
}
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string{
    isUpdatedSome = YES;
    return YES;
}

@end
