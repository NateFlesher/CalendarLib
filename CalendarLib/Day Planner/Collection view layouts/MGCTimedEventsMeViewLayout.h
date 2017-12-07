//
//  MGCTimedEventsMeViewLayout.h
//  FlightDesk
//
//  Created by jellaliu on 11/15/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import <UIKit/UIKit.h>

static NSString* const DimmingMeViewKind = @"DimmingMeViewKind";
typedef enum : NSUInteger
{
    TimedEventMeCoveringTypeClassic = 0,
    TimedEventMeCoveringTypeComplex  = 1 << 0,
} TimedEventMeCoveringType;


@protocol MGCTimedEventsMeViewLayoutDelegate;
@class MGCEventCellLayoutAttributes;


// Custom invalidation context for MGCTimedEventsMeViewLayout
@interface MGCTimedEventsMeViewLayoutInvalidationContext: UICollectionViewLayoutInvalidationContext

@property (nonatomic) BOOL invalidateDimmingViews;  // set to true if layout attributes of dimming views must be recomputed
@property (nonatomic) BOOL invalidateEventCells;  // set to true if layout attributes of event cells must be recomputed
@property (nonatomic) NSMutableIndexSet *invalidatedSections;   // sections whose layout attributes (dimming views or event cells) must be recomputed - if nil, recompute everything

@end


// This collection view layout is responsible for the layout of event views in the timed-events part
// of the day planner view.
@interface MGCTimedEventsMeViewLayout : UICollectionViewLayout

@property (nonatomic, weak) id<MGCTimedEventsMeViewLayoutDelegate> delegate;
@property (nonatomic) CGSize dayColumnSize;
@property (nonatomic) CGFloat minimumVisibleHeight;  // if 2 cells overlap, and the height of the uncovered part of the upper cell is less than this value, the column is split
@property (nonatomic) BOOL ignoreNextInvalidation;  // for some reason, UICollectionView reloadSections: messes up with scrolling and animations so we have to stick with using reloadData even when only individual sections need to be invalidated. As a workaroud, we explicitly invalidate them with custom context, and set this flag to YES before calling reloadData
@property (nonatomic) TimedEventMeCoveringType coveringType;  // how to handle event covering

@end


@protocol MGCTimedEventsMeViewLayoutDelegate <UICollectionViewDelegate>

// x and width of returned rect are ignored
- (CGRect)collectionView:(UICollectionView*)collectionView layout:(MGCTimedEventsMeViewLayout*)layout rectForEventAtIndexPathMe:(NSIndexPath*)indexPath;
- (NSArray*)collectionView:(UICollectionView*)collectionView layout:(MGCTimedEventsMeViewLayout*)layout dimmingRectsForSectionMe:(NSUInteger)section;
- (EKEvent *)collectionView:(UICollectionView *)collectionView layout:(MGCTimedEventsMeViewLayout *)layout getEventMe:(NSIndexPath *)indexPath;

@end
