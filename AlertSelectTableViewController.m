//
//  AlertSelectTableViewController.m
//  FlightDesk
//
//  Created by jellaliu on 06/12/2017.
//  Copyright © 2017 spider. All rights reserved.
//

#import "AlertSelectTableViewController.h"

@interface AlertSelectTableViewController ()<UITableViewDelegate, UITableViewDataSource>
{
    NSMutableArray *alertArray;
    NSTimeInterval selectedAlertVal;
    NSInteger currentSelectedIndexRow;
    NSArray *timeIntervalArray;
}

@end


@implementation AlertSelectTableViewController
- (id)initWithAlertVal:(NSTimeInterval)alertVal
{
    self = [super init];
    if (self) {
        selectedAlertVal = alertVal;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Alert";
    
    alertArray = [[NSMutableArray alloc] initWithObjects:@"At time of Event", @"5 minutes before", @"15 minutes before", @"30 minutes before", @"1 hour before", @"2 hours before", @"1 day before", @"2 days before",@"1 week before", nil];
    
    timeIntervalArray = [[NSArray alloc] initWithObjects:@0, @300, @900, @1800, @3600, @7200, @86400, @172800, @604800, nil];
    currentSelectedIndexRow = -1;
    for (int i = 0; i < timeIntervalArray.count; i ++) {
        NSInteger timeIntervalToCheck = [[timeIntervalArray objectAtIndex:i] integerValue];
        if (timeIntervalToCheck == selectedAlertVal) {
            currentSelectedIndexRow = i;
            break;
        }
    }
    
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 1;
    }else if (section == 1){
        return alertArray.count;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *sortTableViewIdentifier = @"AlertItem";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sortTableViewIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:sortTableViewIdentifier];
    }
    if (indexPath.section == 0) {
        cell.textLabel.text = @"None";
    }else if (indexPath.section == 1){
        cell.textLabel.text = [alertArray objectAtIndex:indexPath.row];
    }
    
    if (indexPath.section == 1 && currentSelectedIndexRow == indexPath.row) {
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(self.view.frame.size.width - 30, 12, 20, 20)];
        [imageView setImage:[UIImage imageNamed:@"right.png"]];
        [cell.contentView addSubview:imageView];
    }
    
    
    return cell;
}
- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
    return @" ";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section{
    return 40.0f;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        [self.alertSelectDelegate didSetAlertVal:-1];
    }else if (indexPath.section == 1){
        [self.alertSelectDelegate didSetAlertVal:[[timeIntervalArray objectAtIndex:indexPath.row] integerValue]];
    }
    [self.navigationController popViewControllerAnimated:YES];
}
/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
