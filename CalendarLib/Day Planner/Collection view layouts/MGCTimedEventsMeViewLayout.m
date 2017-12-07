//
//  MGCTimedEventsMeViewLayout.m
//  FlightDesk
//
//  Created by jellaliu on 11/15/17.
//  Copyright © 2017 spider. All rights reserved.
//

#import "MGCTimedEventsMeViewLayout.h"
#import "MGCEventCellLayoutAttributes.h"
#import "MGCAlignedGeometry.h"


// In iOS 8.1.2 and older, there is a bug with UICollectionView that will make
// cells disappear when their frame overlap vertically the visible rect (i.e the one passed in
// layoutAttributesForElementsInRect:)
// To avoid this, we constraint the height of the cells frame so that they entirely fit in the rect.
// Then we have to remember to invalidate the whole layout whenever this visible rect changes

// see http://stackoverflow.com/questions/13770484/large-uicollectionviewcells-disappearing-with-custom-layout
// or https://github.com/mattjgalloway/CocoaBugs/blob/master/UICollectionView-MissingCells/README.md

//#define BUG_FIX   // cannot reproduce this bug anymore


static NSString* const DimmingViewsKey = @"DimmingViewsKey";
static NSString* const EventCellsKey = @"EventCellsKey";


@implementation MGCTimedEventsMeViewLayoutInvalidationContext

- (instancetype)init {
    if (self = [super init]) {
        self.invalidateDimmingViews = NO;
        self.invalidateEventCells = YES;
    }
    return self;
}

@end

@interface MGCTimedEventsMeViewLayout()

@property (nonatomic) NSMutableDictionary *layoutInfo;

#ifdef BUG_FIX
@property (nonatomic) CGRect visibleBounds;
@property (nonatomic) BOOL shouldInvalidate;
#endif

@end


@implementation MGCTimedEventsMeViewLayout

- (instancetype)init {
    if (self = [super init]) {
        _minimumVisibleHeight = 15.;
        _ignoreNextInvalidation = NO;
    }
    return self;
}

- (NSMutableDictionary*)layoutInfo
{
    if (!_layoutInfo) {
        NSInteger numSections = self.collectionView.numberOfSections;
        _layoutInfo = [NSMutableDictionary dictionaryWithCapacity:numSections];
    }
    return _layoutInfo;
}

- (NSArray*)layoutAttributesForDimmingViewsInSection:(NSUInteger)section
{
    NSArray *dimmingRects = [self.delegate collectionView:self.collectionView layout:self dimmingRectsForSectionMe:section];
    
    NSMutableArray *layoutAttribs = [NSMutableArray arrayWithCapacity:dimmingRects.count];
    
    for (NSInteger item = 0; item < dimmingRects.count; item++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
        
        CGRect rect = [dimmingRects[item] CGRectValue];
        if (!CGRectIsNull(rect)) {
            UICollectionViewLayoutAttributes *viewAttribs = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:DimmingMeViewKind withIndexPath:indexPath];
            rect.origin.x = self.dayColumnSize.width * indexPath.section;
            rect.size.width = self.dayColumnSize.width;
            
            viewAttribs.frame = MGCAlignedRect(rect);
            
            [layoutAttribs addObject:viewAttribs];
        }
    }
    
    return layoutAttribs;
}

- (NSArray*)layoutAttributesForEventCellsInSection:(NSUInteger)section
{
    NSInteger numItems = [self.collectionView numberOfItemsInSection:section];
    NSMutableArray *layoutAttribs = [NSMutableArray arrayWithCapacity:numItems];
    
    for (NSInteger item = 0; item < numItems; item++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
        
        CGRect rect = [self.delegate collectionView:self.collectionView layout:self rectForEventAtIndexPathMe:indexPath];
        EKEvent *event = [self.delegate collectionView:self.collectionView layout:self getEventMe:indexPath];
        //        NSLog(@"identify : %@", event.eventIdentifier);
        //        NSLog(@"calendar identify : %@", event.calendar.calendarIdentifier);
        NSInteger position = 0;
        if (event) {
            position = [self getPositionFromCalendar:event.calendar.title];
        }
        
        if (!CGRectIsNull(rect)) {
            MGCEventCellLayoutAttributes *cellAttribs = [MGCEventCellLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
            
            rect.origin.x = self.dayColumnSize.width * indexPath.section;
            rect.size.width = self.dayColumnSize.width;
            if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
                rect.size.height = fmax(8, rect.size.height);
            }else{
                rect.size.height = fmax(self.minimumVisibleHeight, rect.size.height);
            }
            
            cellAttribs.frame = MGCAlignedRect(CGRectInset(rect , 0, 1));
            cellAttribs.visibleHeight = cellAttribs.frame.size.height;
            cellAttribs.eventsPositionType = position;
            cellAttribs.zIndex = 1;  // should appear above dimming views
            
            [layoutAttribs addObject:cellAttribs];
        }
    }
    
    return [self adjustLayoutForOverlappingCells:layoutAttribs inSection:section];
}
- (NSInteger)getPositionFromCalendar:(NSString *)calendarName{
    NSInteger positionEvent = 0;
    NSString *prefixOfCalendar = @"";
    if(calendarName.length > 3){
        prefixOfCalendar = [calendarName substringToIndex:3];
    }
    if ([prefixOfCalendar isEqualToString:@"FD-"]) {
        if(calendarName.length > 3){
            prefixOfCalendar = [calendarName substringToIndex:4];
        }
        prefixOfCalendar = [prefixOfCalendar substringFromIndex:3];
        
        NSMutableArray *usersArray = [[NSMutableArray alloc] init];
        NSMutableArray *aircraftArray = [[NSMutableArray alloc] init];
        NSMutableArray *classroomsArray  = [[NSMutableArray alloc] init];
        
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
        
        if ([prefixOfCalendar isEqualToString:@"U"]) {
            for (int i = 0; i < usersArray.count; i++) {
                Users *userInfo = [usersArray objectAtIndex:i];
                if ([calendarName isEqualToString:[NSString stringWithFormat:@"FD-U-(%@ %@ %@)", userInfo.firstName, userInfo.middleName, userInfo.lastName]]) {
                    positionEvent = i + 1 + 1;
                }
            }
        }else if ([prefixOfCalendar isEqualToString:@"A"]) {
            for (int i = 0; i < aircraftArray.count; i++) {
                Aircraft *aircraft = [aircraftArray objectAtIndex:i];
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
                if ([calendarName isEqualToString:[NSString stringWithFormat:@"FD-A-(%@ %@)", aircraftReg, aircraftMod]]) {
                    positionEvent = usersArray.count + 1 + i + 1 + 1;
                }
            }
        }else if ([prefixOfCalendar isEqualToString:@"C"]) {
            for (int i = 0; i < classroomsArray.count; i++) {
                NSString *classroom = [classroomsArray objectAtIndex:i];
                if ([calendarName isEqualToString:[NSString stringWithFormat:@"FD-C-(%@)", classroom]]) {
                    positionEvent = usersArray.count + 1 + aircraftArray.count + 1 + i + 1 + 1;
                }
            }
        }
    }
    return positionEvent;
}
- (NSDictionary*)layoutAttributesForSection:(NSUInteger)section
{
    NSMutableDictionary *sectionAttribs = [self.layoutInfo objectForKey:@(section)];
    
    if (!sectionAttribs) {
        sectionAttribs = [NSMutableDictionary dictionary];
    }
    
    if (![sectionAttribs objectForKey:DimmingViewsKey]) {
        NSArray *dimmingViewsAttribs = [self layoutAttributesForDimmingViewsInSection:section];
        [sectionAttribs setObject:dimmingViewsAttribs forKey:DimmingViewsKey];
    }
    if (![sectionAttribs objectForKey:EventCellsKey]) {
        NSArray *cellsAttribs = [self layoutAttributesForEventCellsInSection:section];
        [sectionAttribs setObject:cellsAttribs forKey:EventCellsKey];
    }
    
    [self.layoutInfo setObject:sectionAttribs forKey:@(section)];
    
    return sectionAttribs;
}

- (NSArray*)adjustLayoutForOverlappingCells:(NSArray*)attributes inSection:(NSUInteger)section
{
    const CGFloat kOverlapOffset = 4.;
    
    // sort layout attributes by frame y-position
    NSArray *adjustedAttributes = [attributes sortedArrayUsingComparator:^NSComparisonResult(MGCEventCellLayoutAttributes *att1, MGCEventCellLayoutAttributes *att2) {
        if (att1.frame.origin.y > att2.frame.origin.y) {
            return NSOrderedDescending;
        }
        else if (att1.frame.origin.y < att2.frame.origin.y) {
            return NSOrderedAscending;
        }
        return NSOrderedSame;
    }];
    
    if (self.coveringType == TimedEventMeCoveringTypeClassic) {
        
//        for (NSUInteger i = 0; i < adjustedAttributes.count; i++) {
//            MGCEventCellLayoutAttributes *attribs1 = [adjustedAttributes objectAtIndex:i];
//            
//            NSMutableArray *layoutGroup = [NSMutableArray array];
//            [layoutGroup addObject:attribs1];
//            
//            NSMutableArray *coveredLayoutAttributes = [NSMutableArray array];
//            
//            // iterate previous frames (i.e with highest or equal y-pos)
//            for (NSInteger j = i - 1; j >= 0; j--) {
//                
//                MGCEventCellLayoutAttributes *attribs2 = [adjustedAttributes objectAtIndex:j];
//                if (CGRectIntersectsRect(attribs1.frame, attribs2.frame)) {
//                    CGFloat visibleHeight = fabs(attribs1.frame.origin.y - attribs2.frame.origin.y);
//                    
//                    if (visibleHeight > self.minimumVisibleHeight) {
//                        [coveredLayoutAttributes addObject:attribs2];
//                        attribs2.visibleHeight = visibleHeight;
//                        attribs1.zIndex = attribs2.zIndex + 1;
//                    }
//                    else {
//                        if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking) {
//                            
//                        }else{
//                            [layoutGroup addObject:attribs2];
//                        }
//                    }
//                }
//            }
//            
//            
//            // now, distribute elements in layout group
//            CGFloat groupOffset = 0;
//            if (coveredLayoutAttributes.count > 0) {
//                BOOL lookForEmptySlot = YES;
//                NSUInteger slotNumber = 0;
//                CGFloat offset = 0;
//                
//                while (lookForEmptySlot) {
//                    offset = slotNumber * kOverlapOffset;
//                    
//                    lookForEmptySlot = NO;
//                    
//                    for (MGCEventCellLayoutAttributes *attribs in coveredLayoutAttributes) {
//                        if (attribs.frame.origin.x - section * self.dayColumnSize.width == offset) {
//                            lookForEmptySlot = YES;
//                            break;
//                        }
//                    }
//                    
//                    slotNumber += 1;
//                }
//                
//                groupOffset += offset;
//            }
//            
//            CGFloat totalWidth = (self.dayColumnSize.width - 1.) - groupOffset;
//            CGFloat colWidth = totalWidth / layoutGroup.count;
//            CGFloat colWidthMe;
//            if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
//                totalWidth = 40.0f;
//                if (coveredLayoutAttributes.count > 0) {
//                    colWidthMe = totalWidth / coveredLayoutAttributes.count;
//                }else{
//                    colWidthMe = totalWidth;
//                }
//            }
//            
//            CGFloat x = section * self.dayColumnSize.width + groupOffset;
//            
//            NSInteger j = 0;
//            for (MGCEventCellLayoutAttributes* attribs in [layoutGroup reverseObjectEnumerator]) {
//                if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
//                    attribs.frame = MGCAlignedRectMake(x+attribs.frame.origin.y,
//                                                       j * colWidthMe,
//                                                       attribs.frame.size.height ,
//                                                       colWidthMe);
//                }else{
//                    attribs.frame = MGCAlignedRectMake(x, attribs.frame.origin.y, colWidth, attribs.frame.size.height);
//                }
//                x += colWidth;
//                j++;
//            }
//        }
//        
//        return adjustedAttributes;
        // Create clusters - groups of rectangles which don't have common parts with other groups
        NSMutableArray *uninspectedAttributes = [adjustedAttributes mutableCopy];
        NSMutableArray<NSMutableArray<MGCEventCellLayoutAttributes *> *> *clusters = [NSMutableArray new];
        
        while (uninspectedAttributes.count > 0) {
            MGCEventCellLayoutAttributes *attrib = [uninspectedAttributes firstObject];
            NSMutableArray<MGCEventCellLayoutAttributes *> *destinationCluster;
            
            for (NSMutableArray<MGCEventCellLayoutAttributes *> *cluster in clusters) {
                for (MGCEventCellLayoutAttributes *clusteredAttrib in cluster) {
                    if (CGRectIntersectsRect(clusteredAttrib.frame, attrib.frame)) {
                        destinationCluster = cluster;
                        break;
                    }
                }
            }
            
            if (destinationCluster) {
                [destinationCluster addObject:attrib];
            } else {
                NSMutableArray<MGCEventCellLayoutAttributes *> *cluster = [NSMutableArray new];
                [cluster addObject:attrib];
                [clusters addObject:cluster];
            }
            
            [uninspectedAttributes removeObject:attrib];
        }
        
        // Distribute rectangles evenly in clusters
        for (NSMutableArray<MGCEventCellLayoutAttributes *> *cluster in clusters) {
            [self expandCellsToMaxWidthInCluster:cluster];
        }
        
        // Gather all the attributes and return them
        NSMutableArray *attributes = [NSMutableArray new];
        for (NSMutableArray<MGCEventCellLayoutAttributes *> *cluster in clusters) {
            [attributes addObjectsFromArray:cluster];
        }
        
        return attributes;
    } else if (self.coveringType == TimedEventMeCoveringTypeComplex) {
        
        // Create clusters - groups of rectangles which don't have common parts with other groups
        NSMutableArray *uninspectedAttributes = [adjustedAttributes mutableCopy];
        NSMutableArray<NSMutableArray<MGCEventCellLayoutAttributes *> *> *clusters = [NSMutableArray new];
        
        while (uninspectedAttributes.count > 0) {
            MGCEventCellLayoutAttributes *attrib = [uninspectedAttributes firstObject];
            NSMutableArray<MGCEventCellLayoutAttributes *> *destinationCluster;
            
            for (NSMutableArray<MGCEventCellLayoutAttributes *> *cluster in clusters) {
                for (MGCEventCellLayoutAttributes *clusteredAttrib in cluster) {
                    if (CGRectIntersectsRect(clusteredAttrib.frame, attrib.frame)) {
                        destinationCluster = cluster;
                        break;
                    }
                }
            }
            
            if (destinationCluster) {
                [destinationCluster addObject:attrib];
            } else {
                NSMutableArray<MGCEventCellLayoutAttributes *> *cluster = [NSMutableArray new];
                [cluster addObject:attrib];
                [clusters addObject:cluster];
            }
            
            [uninspectedAttributes removeObject:attrib];
        }
        
        // Distribute rectangles evenly in clusters
        for (NSMutableArray<MGCEventCellLayoutAttributes *> *cluster in clusters) {
            [self expandCellsToMaxWidthInCluster:cluster];
        }
        
        // Gather all the attributes and return them
        NSMutableArray *attributes = [NSMutableArray new];
        for (NSMutableArray<MGCEventCellLayoutAttributes *> *cluster in clusters) {
            [attributes addObjectsFromArray:cluster];
        }
        
        return attributes;
    }
    
    return @[];
}

- (void)expandCellsToMaxWidthInCluster:(NSMutableArray<MGCEventCellLayoutAttributes *> *)cluster
{
    const NSUInteger padding = 2.f;
    
    // Expand the attributes to maximum possible width
    NSMutableArray<NSMutableArray<MGCEventCellLayoutAttributes *> *> *columns = [NSMutableArray new];
    [columns addObject:[NSMutableArray new]];
    for (MGCEventCellLayoutAttributes *attribs in cluster) {
        BOOL isPlaced = NO;
        for (NSMutableArray<MGCEventCellLayoutAttributes *> *column in columns) {
            if (column.count == 0) {
                [column addObject:attribs];
                isPlaced = YES;
            } else if (!CGRectIntersectsRect(attribs.frame, [column lastObject].frame)) {
                [column addObject:attribs];
                isPlaced = YES;
                break;
            }
        }
        if (!isPlaced) {
            NSMutableArray<MGCEventCellLayoutAttributes *> *column = [NSMutableArray new];
            [column addObject:attribs];
            [columns addObject:column];
        }
    }
    
    // Calculate left and right position for all the attributes, get the maxRowCount by looking in all columns
    NSInteger maxRowCount = 0;
    for (NSMutableArray<MGCEventCellLayoutAttributes *> *column in columns) {
        maxRowCount = fmax(maxRowCount, column.count);
    }
    
    CGFloat totalWidth = self.dayColumnSize.width - 2.f;
    if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
        totalWidth = 40.0f - 2.0f;
    }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
        totalWidth = 40.0f - 2.0f;
    }
    
    for (NSInteger i = 0; i < maxRowCount; i++) {
        // Set the x position of the rect
        NSInteger j = 0;
        for (NSMutableArray<MGCEventCellLayoutAttributes *> *column in columns) {
            CGFloat colWidth = totalWidth / columns.count;
            if (column.count >= i + 1) {
                MGCEventCellLayoutAttributes *attribs = [column objectAtIndex:i];
                if ([AppDelegate sharedDelegate].isSelectedDayViewForBooking) {
                    attribs.frame = MGCAlignedRectMake(attribs.frame.origin.y + attribs.frame.origin.x,
                                                       j * colWidth,
                                                       attribs.frame.size.height ,
                                                       colWidth);
                }else if ([AppDelegate sharedDelegate].isSelectedWeekViewForBooking){
                    attribs.frame = MGCAlignedRectMake(attribs.frame.origin.y + attribs.frame.origin.x,
                                                       j * colWidth,
                                                       attribs.frame.size.height ,
                                                       colWidth);
                }else{
                    attribs.frame = MGCAlignedRectMake(attribs.frame.origin.x + j * colWidth,
                                                       attribs.frame.origin.y,
                                                       colWidth,
                                                       attribs.frame.size.height);
                }
            }
            j++;
        }
    }
}

#pragma mark - UICollectionViewLayout

+ (Class)layoutAttributesClass
{
    return [MGCEventCellLayoutAttributes class];
}

+ (Class)invalidationContextClass
{
    return [MGCTimedEventsMeViewLayoutInvalidationContext class];
}

- (MGCEventCellLayoutAttributes*)layoutAttributesForItemAtIndexPath:(NSIndexPath*)indexPath
{
    //NSLog(@"layoutAttributesForItemAtIndexPath %@", indexPath);
    
    NSArray *attribs = [[self layoutAttributesForSection:indexPath.section] objectForKey:EventCellsKey];
    return [attribs objectAtIndex:indexPath.item];
}

- (UICollectionViewLayoutAttributes*)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath
{
    NSArray *attribs = [[self layoutAttributesForSection:indexPath.section] objectForKey:DimmingViewsKey];
    return [attribs objectAtIndex:indexPath.item];
}

- (void)prepareForCollectionViewUpdates:(NSArray*)updateItems
{
    //NSLog(@"prepare Collection updates");
    
    [super prepareForCollectionViewUpdates:updateItems];
}

- (void)invalidateLayoutWithContext:(MGCTimedEventsMeViewLayoutInvalidationContext *)context
{
    //NSLog(@"invalidateLayoutWithContext");
    
    [super invalidateLayoutWithContext:context];
    
    if (self.ignoreNextInvalidation) {
        self.ignoreNextInvalidation = NO;
        return;
        
    }
    
    if (context.invalidateEverything || context.invalidatedSections == nil) {
        self.layoutInfo = nil;
    }
    else {
        [context.invalidatedSections enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            if (context.invalidateDimmingViews) {
                [[self.layoutInfo objectForKey:@(idx)]removeObjectForKey:DimmingViewsKey];
            }
            if (context.invalidateEventCells) {
                [[self.layoutInfo objectForKey:@(idx)]removeObjectForKey:EventCellsKey];
            }
        }];
    }
}

- (void)invalidateLayout
{
    //NSLog(@"invalidateLayout");
    
    [super invalidateLayout];
}

- (CGSize)collectionViewContentSize
{
    return CGSizeMake(self.dayColumnSize.width * self.collectionView.numberOfSections, self.dayColumnSize.height);
}

- (NSArray*)layoutAttributesForElementsInRect:(CGRect)rect
{
    //NSLog(@"layoutAttributesForElementsInRect %@", NSStringFromCGRect(rect));
    
#ifdef BUG_FIX
    self.shouldInvalidate = self.visibleBounds.origin.y != rect.origin.y || self.visibleBounds.size.height != rect.size.height;
    //self.shouldInvalidate = !CGRectEqualToRect(self.visibleBounds, rect);
    self.visibleBounds = rect;
#endif
    
    NSMutableArray *allAttribs = [NSMutableArray array];
    
    // determine first and last day intersecting rect
    NSUInteger maxSection = self.collectionView.numberOfSections;
    NSUInteger first = MAX(0, floorf(rect.origin.x  / self.dayColumnSize.width));
    NSUInteger last =  MIN(MAX(first, ceilf(CGRectGetMaxX(rect) / self.dayColumnSize.width)), maxSection);
    
    for (NSInteger day = first; day < last; day++) {
        NSDictionary *layoutDic = [self layoutAttributesForSection:day];
        NSArray *attribs = [[layoutDic objectForKey:DimmingViewsKey]arrayByAddingObjectsFromArray:[layoutDic objectForKey:EventCellsKey]];
        
        for (UICollectionViewLayoutAttributes *a in attribs) {
            if (CGRectIntersectsRect(rect, a.frame)) {
#ifdef BUG_FIX
                CGRect frame = a.frame;
                frame.size.height = fminf(frame.size.height, CGRectGetMaxY(rect) - frame.origin.y);
                a.frame = frame;
#endif
                [allAttribs addObject:a];
            }
        }
    }
    
    return allAttribs;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds
{
    //NSLog(@"shouldInvalidateLayoutForBoundsChange %@", NSStringFromCGRect(newBounds));
    
    CGRect oldBounds = self.collectionView.bounds;
    
    return
#ifdef BUG_FIX
    self.shouldInvalidate ||
#endif
    oldBounds.size.width != newBounds.size.width;
}

// we keep this for iOS 8 compatibility. As of iOS 9, this is replaced by collectionView:targetContentOffsetForProposedContentOffset:
- (CGPoint)targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset
{
    id<UICollectionViewDelegate> delegate = (id<UICollectionViewDelegate>)self.collectionView.delegate;
    return [delegate collectionView:self.collectionView targetContentOffsetForProposedContentOffset:proposedContentOffset];
}

@end
