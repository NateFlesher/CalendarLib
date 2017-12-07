//
//  MGCTimeColumnsView.h
//  FlightDesk
//
//  Created by jellaliu on 11/12/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MGCTimeColumnsView : UIView
// font used for time marks
@property (nonatomic) UIColor *timeColor;
- (void)reDrawFromOtherView;
@end
