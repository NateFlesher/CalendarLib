//
//  ResourcesCell.m
//  FlightDesk
//
//  Created by stepanekdavid on 11/6/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import "ResourcesCell.h"

@implementation ResourcesCell
+ (ResourcesCell *)sharedCell
{
    NSArray *array = [[NSBundle mainBundle] loadNibNamed:@"ResourcesCell" owner:nil options:nil];
    ResourcesCell *cell = [array objectAtIndex:0];
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

@end
