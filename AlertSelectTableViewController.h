//
//  AlertSelectTableViewController.h
//  FlightDesk
//
//  Created by jellaliu on 06/12/2017.
//  Copyright © 2017 spider. All rights reserved.
//

#import <UIKit/UIKit.h>
@protocol AlertSelectTableViewControllerDelegate
@optional;
-(void)didSetAlertVal:(NSTimeInterval)_timeInterval;
@end

@interface AlertSelectTableViewController : UITableViewController
- (id)initWithAlertVal:(NSTimeInterval)alertVal;
@property (nonatomic, weak, readwrite) id <AlertSelectTableViewControllerDelegate> alertSelectDelegate;
@end
