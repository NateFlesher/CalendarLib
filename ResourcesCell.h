//
//  ResourcesCell.h
//  FlightDesk
//
//  Created by stepanekdavid on 11/6/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ResourcesCell : UITableViewCell
+ (ResourcesCell *)sharedCell;
@property (weak, nonatomic) IBOutlet UILabel *lblResourceTitle;

@end
