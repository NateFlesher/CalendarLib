//
//  DateFlightCell.h
//  FlightDesk
//
//  Created by jellaliu on 11/10/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DateFlightCell;
@protocol DateFlightCellDelegate
@optional;
- (void)didChangeDate:(DateFlightCell *)_cell withDate:(NSDate *)_date;
@end

@interface DateFlightCell : UITableViewCell
+ (DateFlightCell *)sharedCell;

@property (weak, nonatomic) IBOutlet UILabel *lblDateType;
@property (weak, nonatomic) IBOutlet UILabel *dateValue;
@property (weak, nonatomic) IBOutlet UIDatePicker *datePicker;

@property (nonatomic, weak, readwrite) id <DateFlightCellDelegate> delegate;

- (IBAction)onChangeDate:(UIDatePicker *)sender;

@end
