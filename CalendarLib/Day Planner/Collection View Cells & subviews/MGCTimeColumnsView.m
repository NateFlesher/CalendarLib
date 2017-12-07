//
//  MGCTimeColumnsView.m
//  FlightDesk
//
//  Created by jellaliu on 11/12/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import "MGCTimeColumnsView.h"

@implementation MGCTimeColumnsView
- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        _timeColor = [UIColor lightGrayColor];
    }
    return self;
}
- (void)reDrawFromOtherView{
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat lineWidth = 1. / [UIScreen mainScreen].scale;
    
    NSMutableArray *usersArray = [[NSMutableArray alloc] init];
    NSMutableArray *aircraftArray = [[NSMutableArray alloc] init];
    NSMutableArray *classroomsArray = [[NSMutableArray alloc] init];
    
    NSError *error;
    NSManagedObjectContext *contextCore = [AppDelegate sharedDelegate].persistentCoreDataStack.managedObjectContext;
    NSEntityDescription *entityDesc = [NSEntityDescription entityForName:@"Users" inManagedObjectContext:contextCore];
    // load the remaining lesson groups
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:entityDesc];
    NSArray *objects = [contextCore executeFetchRequest:request error:&error];
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
    
    entityDesc = [NSEntityDescription entityForName:@"Aircraft" inManagedObjectContext:contextCore];
    request = [[NSFetchRequest alloc] init];
    [request setEntity:entityDesc];
    objects = [contextCore executeFetchRequest:request error:&error];
    if (objects == nil) {
        FDLogError(@"Unable to retrieve Aircraft!");
    } else if (objects.count == 0) {
        FDLogDebug(@"No valid Aircrafts found!");
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
        CGRect rectangle = CGRectMake(0, 65, self.bounds.size.width, 40);
        CGContextSetRGBFillColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextSetRGBStrokeColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextFillRect(context, rectangle);
        
        for (NSInteger u = 0; u <= usersArray.count; u++) {
            CGContextSetStrokeColorWithColor(context, self.timeColor.CGColor);
            CGContextSetLineWidth(context, lineWidth);
            CGContextSetLineDash(context, 0, NULL, 0);
            CGContextMoveToPoint(context, 0, 105 + u*40.0f);
            CGContextAddLineToPoint(context, self.bounds.size.width , 105 + u*40.0f);
            CGContextStrokePath(context);
        }
        
        
        rectangle = CGRectMake(0, 65 + 40.0f * (usersArray.count + 1), self.bounds.size.width, 40);
        CGContextSetRGBFillColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextSetRGBStrokeColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextFillRect(context, rectangle);
        
        for (NSInteger a = 0; a <= aircraftArray.count; a++) {
            CGContextSetStrokeColorWithColor(context, self.timeColor.CGColor);
            CGContextSetLineWidth(context, lineWidth);
            CGContextSetLineDash(context, 0, NULL, 0);
            CGContextMoveToPoint(context, 0, 145 + usersArray.count*40.0f + a*40.0f);
            CGContextAddLineToPoint(context, self.bounds.size.width , 145 + usersArray.count*40.0f + a*40.0f);
            CGContextStrokePath(context);
        }
        
        rectangle = CGRectMake(0, 65 + 40.0f * (usersArray.count + aircraftArray.count + 2), self.bounds.size.width, 40);
        CGContextSetRGBFillColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextSetRGBStrokeColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextFillRect(context, rectangle);
        
        for (NSInteger c = 0; c <= classroomsArray.count; c++) {
            CGContextSetStrokeColorWithColor(context, self.timeColor.CGColor);
            CGContextSetLineWidth(context, lineWidth);
            CGContextSetLineDash(context, 0, NULL, 0);
            CGContextMoveToPoint(context, 0, 185 + usersArray.count*40.0f + aircraftArray.count*40.0f + c*40.0f);
            CGContextAddLineToPoint(context, self.bounds.size.width , 185 + usersArray.count*40.0f + aircraftArray.count*40.0f + c*40.0f);
            CGContextStrokePath(context);
        }
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        
        CGRect rectangle = CGRectMake(0, 65, self.bounds.size.width, 40);
        CGContextSetRGBFillColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextSetRGBStrokeColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextFillRect(context, rectangle);
        
        for (NSInteger u = 0; u <= usersArray.count; u++) {
            CGContextSetStrokeColorWithColor(context, self.timeColor.CGColor);
            CGContextSetLineWidth(context, lineWidth);
            CGContextSetLineDash(context, 0, NULL, 0);
            CGContextMoveToPoint(context, 0, 105 + u*40.0f);
            CGContextAddLineToPoint(context, self.bounds.size.width , 105 + u*40.0f);
            CGContextStrokePath(context);
        }
        
        
        rectangle = CGRectMake(0, 65 + 40.0f * (usersArray.count + 1), self.bounds.size.width, 40);
        CGContextSetRGBFillColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextSetRGBStrokeColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextFillRect(context, rectangle);
        
        for (NSInteger a = 0; a <= aircraftArray.count; a++) {
            CGContextSetStrokeColorWithColor(context, self.timeColor.CGColor);
            CGContextSetLineWidth(context, lineWidth);
            CGContextSetLineDash(context, 0, NULL, 0);
            CGContextMoveToPoint(context, 0, 145 + usersArray.count*40.0f + a*40.0f);
            CGContextAddLineToPoint(context, self.bounds.size.width , 145 + usersArray.count*40.0f + a*40.0f);
            CGContextStrokePath(context);
        }
        
        rectangle = CGRectMake(0, 65 + 40.0f * (usersArray.count + aircraftArray.count + 2), self.bounds.size.width, 40);
        CGContextSetRGBFillColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextSetRGBStrokeColor(context, 0.9, 0.9, 0.9, 1.0);
        CGContextFillRect(context, rectangle);
        
        for (NSInteger c = 0; c <= classroomsArray.count; c++) {
            CGContextSetStrokeColorWithColor(context, self.timeColor.CGColor);
            CGContextSetLineWidth(context, lineWidth);
            CGContextSetLineDash(context, 0, NULL, 0);
            CGContextMoveToPoint(context, 0, 185 + usersArray.count*40.0f + aircraftArray.count*40.0f + c*40.0f);
            CGContextAddLineToPoint(context, self.bounds.size.width , 185 + usersArray.count*40.0f + aircraftArray.count*40.0f + c*40.0f);
            CGContextStrokePath(context);
        }
    }
}
@end
