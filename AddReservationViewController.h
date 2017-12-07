//
//  AddReservationViewController.h
//  FlightDesk
//
//  Created by jellaliu on 11/10/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "HVTableView.h"

@protocol AddReservationViewControllerDelegate;

@interface AddReservationViewController : UIViewController
{
    __weak IBOutlet HVTableView *AddReservationTableView;
    __weak IBOutlet UITextField *txtTitle;
    __weak IBOutlet UIButton *btnDelete;
    __weak IBOutlet NSLayoutConstraint *btnDeleteConstraint;
    
}

@property (nonatomic, copy) NSCalendar *calendar;

@property (nonatomic, strong) NSDate *startDate;
@property (nonatomic, strong) NSDate *endDate;
@property (nonatomic, strong) EKEvent *editEvent;
@property  NSTimeInterval alertVal;

@property (nonatomic) UIBarButtonItem *doneButton;

- (IBAction)onAllDelete:(UIButton *)sender;

@property (nonatomic, weak) id<AddReservationViewControllerDelegate> delegate;
@end

@protocol AddReservationViewControllerDelegate<NSObject>

@optional
- (BOOL)didCancelResevation:(AddReservationViewController *)_reservationVC;
- (BOOL)didDoneResevation:(AddReservationViewController *)_reservationVC;
@end
