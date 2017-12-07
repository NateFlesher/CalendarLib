//
//  DateFlightCell.m
//  FlightDesk
//
//  Created by jellaliu on 11/10/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import "DateFlightCell.h"

@implementation DateFlightCell
+ (DateFlightCell *)sharedCell
{
    NSArray *array = [[NSBundle mainBundle] loadNibNamed:@"DateFlightCell" owner:nil options:nil];
    DateFlightCell *cell = [array objectAtIndex:0];
    return cell;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}
- (IBAction)onChangeDate:(UIDatePicker *)sender {
    [self.delegate didChangeDate:self withDate:sender.date];
}
@end
