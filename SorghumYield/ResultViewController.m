//
//  ResultViewController.m
//  SorghumYield
//
//  Created by cis on 26/11/2016.
//  Copyright © 2016 Robert Sebek. All rights reserved.
//

#import "ResultViewController.h"
#import <CoreData/CoreData.h>
#import "AdditionalInfoTableViewController.h"

#import "FirebaseManager.h"

static NSString * baseText = @"Seeds per pound = ";

// Create reference to firestore
@interface ResultViewController ()
@property (nonatomic, readwrite) FIRFirestore *db;
@end

@implementation ResultViewController
{
    
}
- (void)viewDidLoad{
    [super viewDidLoad];
    
    _tableView.delegate = self;
    _tableView.dataSource = self;
    
    _keyData =  @[@"Average plant area (in²)",
                  @"Grain count per plant" ,
                  @"Plants per acre",
                  
                  @"Seeds per pound",
                  @"Weight per plant (lb)",
                  @"Yield per acre (lb)",
                  @"Yield per acre (bu)",
                  @"Total yield (bu)",
                  ];
    _valueData = [[NSMutableArray alloc] init];
    
    
    _formatter = [[NSNumberFormatter alloc] init];
    [_formatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [_formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    
    [self initStaticData];
    
    [self reCalculateValues];
    
    [self prepareView];
    
    self.db = [FIRFirestore firestore];
}
-(void) prepareView{
    [self setTitle:@"Yield Prediction"];
    
    [self disableBackButton];
    
    
    [_tableView setBackgroundColor:[UIColor clearColor]];
    [_tableView setBackgroundView:nil];
    
    _submitView.layer.cornerRadius = 5;
    _submitView.layer.masksToBounds = YES;
}

- (void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender{
    if([[segue identifier] isEqualToString:@"AdditionalInfoSegue"]){
        AdditionalInfoTableViewController * vc = [segue destinationViewController];
        [vc setFinalYield:_totalYield];
    }
    
}
-(void) initStaticData{
    [self setAppAreaAverage:[NSNumber numberWithFloat:[[self.managedObject valueForKey:@"appAreaAverage"] floatValue]]];
    [self setGrainsPerPlant:[NSNumber numberWithInt:(int)((113.6 * [_appAreaAverage floatValue]) + 236.38f) ]];
    
    int headsPerAcreRow = [[self.managedObject valueForKey:@"headsPerThousandth"] intValue];
    NSNumber *  rowsPerAcre = [self.managedObject valueForKey:@"rowSpacing"];
    
    NSNumber * headsPerAcre = [NSNumber numberWithInt:(1000 * headsPerAcreRow)];
    
    [self setNumberOfPlantsPerAcre:headsPerAcre];
    [self setNumberOfAcres:[self.managedObject valueForKey:@"numOfAcres"]];
    [_valueData insertObject:[_appAreaAverage stringValue] atIndex:0];
    [_valueData insertObject:[_grainsPerPlant stringValue] atIndex:1];
    [_valueData insertObject:[_numberOfPlantsPerAcre stringValue] atIndex:2];
}
-(void) updateTableViewSource{
    
    [_valueData insertObject:[_seedsPerPound stringValue] atIndex:3];
    [_valueData insertObject:[_formatter stringFromNumber:_weightPerPlant] atIndex:4];
    [_valueData insertObject:[_yieldPerAcre stringValue] atIndex:5];
    [_valueData insertObject:[_yieldPerAcreBU stringValue] atIndex:6];
    [_valueData insertObject:[_totalYield stringValue] atIndex:7];
    [self.tableView reloadData];
}



- (IBAction)sizeSlider:(id)sender {
    [_nextButton setEnabled:true];
    [self reCalculateValues];
}
-(void) reCalculateValues{
    [self setSeedsPerPound:[NSNumber numberWithInteger:_sliderValue.value]];
    
    [_sliderCaption setText:[baseText stringByAppendingString:[NSString stringWithFormat:@"%d", [_seedsPerPound intValue]]]];
    NSNumber * seedWeight = [NSNumber numberWithDouble:(1.0f/self.seedsPerPound.doubleValue)];
    double weightPerPlant = [seedWeight doubleValue] * [_grainsPerPlant floatValue];
    
    [self setWeightPerPlant:[NSNumber numberWithDouble: weightPerPlant]];
    
    [self setYieldPerAcre:[NSNumber numberWithLong:([_weightPerPlant floatValue] * [_numberOfPlantsPerAcre floatValue] )]];
    
    [self setYieldPerAcreBU:[NSNumber numberWithFloat:(round([_yieldPerAcre floatValue]*100/56)/100)]];
    [self setTotalYield:[NSNumber numberWithFloat:(round([_yieldPerAcre floatValue]/56 * [_numberOfAcres intValue]*100)/100)]];
    [self updateTableViewSource];
    
}

- (IBAction)submit:(id)sender {
    
    [_submitView setHidden:YES];
    [self.managedObject setValue:_seedsPerPound  forKey:@"seedsPerPound"];
    [self.managedObject setValue:_yieldPerAcre  forKey:@"yieldPerAcre"];
    [self.managedObject setValue:_totalYield  forKey:@"totalYield"];
    
    NSLog(@"%@\n\n-------Final--------------------------------------", self.managedObject);
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Submitting report"
                                                                   message:SubmitWarning
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* yesButton = [UIAlertAction
                                actionWithTitle:@"Agree"
                                style:UIAlertActionStyleDefault
                                handler:^(UIAlertAction * action)
                                {
                                    [self sendReport];
                                    
                                }];
    UIAlertAction* noButton = [UIAlertAction
                               actionWithTitle:@"Disagree"
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction * action)
                               {
                                   [self performSegueWithIdentifier:@"AdditionalInfoSegue" sender:self];
                               }];
    
    [alert addAction:yesButton];
    [alert addAction:noButton];
    [self presentViewController:alert animated:YES completion:nil];
}

/**
 Sends a report to firebase cloud firestore database
 */
-(void) sendReport{
    
    // Declares location variables
    NSManagedObject * autoGPSCoordinates =[self.managedObject valueForKey:@"autoGPSData"];
    NSManagedObject * manualGPSCoordinates =[self.managedObject valueForKey:@"manualGPSData"];
    NSNumber * lat=[NSNumber numberWithInt:0];
    NSNumber * lon=[NSNumber numberWithInt:0];
    NSString * countryName=@"";
    NSString * stateName=@"";
    NSString * countyName=@"";
    
    // Determines if autoGPS is available. If not, manually gets the location.
    if( autoGPSCoordinates!=nil){
        lat =[autoGPSCoordinates valueForKey:@"lat"];
        lon =[autoGPSCoordinates valueForKey:@"lon"];
    }
    else{
        countryName= [manualGPSCoordinates valueForKey:@"countryName"];
        stateName = [manualGPSCoordinates valueForKey:@"stateName"];
        countyName = [manualGPSCoordinates valueForKey:@"countyName"];
    }
    
    // Adds report data to database
    __block FIRDocumentReference *ref =
    [[self.db collectionWithPath:@"reports"] addDocumentWithData:@{
       @"appID": @"sorghumYield",
       @"owner": [FIRAuth auth].currentUser.uid,
       @"fieldName":      [self.managedObject valueForKey:@"fieldName"],
       @"numAcres":       [self.managedObject valueForKey:@"numOfAcres"],
       @"numberOfHeadsPerThousandth": [self.managedObject valueForKey:@"headsPerThousandth"],
       @"rowSpacing":       [self.managedObject valueForKey:@"rowSpacing"],
       @"AutoGPS":          @{
               @"lat":      lat,
               @"lon":      lon
               },
       @"ManualGPS":          @{
               @"country":      countryName,
               @"state":      stateName,
               @"county":      countyName
               },
       @"appAreaAverage":   [_appAreaAverage stringValue],
       @"seedsPerPound":    [_seedsPerPound stringValue],
       @"grainCount":       [_grainsPerPlant stringValue],
       @"yieldPerAcre_lb":  [_yieldPerAcre stringValue],
       @"yieldPerAcre_bu":  [_yieldPerAcreBU stringValue],
       @"totalYield_bu":    [_totalYield stringValue]
       } completion:^(NSError * _Nullable error) {
           if (error != nil) {
               NSLog(@"Error adding document: %@", error);
           } else {
               NSLog(@"Document added with ID: %@", ref.documentID);
           }
       }];
    
    //Creates a user document if one doesn't exist with this uid
    NSString *UID = [FIRAuth auth].currentUser.uid;
    
    FIRDocumentReference *ref2 =
    [[self.db collectionWithPath:@"users"] documentWithPath:UID];
    
    // Sets user data when creating for the first time
    [ref2 setData:@{
        @"email": [FIRAuth auth].currentUser.email}
        merge:YES
       completion:^(NSError * _Nullable error) {
           if (error != nil) {
               NSLog(@"Error adding document: %@", error);
           } else {
               NSLog(@"Document added with ID: %@", ref2.documentID);
           }
       }];
    
    // Adds the new reportID to the user's "reports" array field
    [ref2 updateData:@{
                       @"reports": [FIRFieldValue fieldValueForArrayUnion:@[ref.documentID]]
                       } completion:^(NSError * _Nullable error) {
                           if (error != nil) {
                               NSLog(@"Error adding document: %@", error);
                           }
                       }];
    
    // -------- Stores images -----------
    
    // Gets a reference to the storage service
    FIRStorage *storage = [FIRStorage storage];
    FIRStorageReference *storageRef = [storage reference];
    
    // Gets array of photos to be uploaded
    NSMutableSet *measurements = [self.managedObject valueForKey:@"measurements"];
    NSArray *objects = measurements.allObjects;
    
    // Creates file metadata (specifies file type)
    FIRStorageMetadata *mdata = [[FIRStorageMetadata alloc] init];
    mdata.contentType = @"image/jpeg";
    
    // Iterates through array and upload photos
    NSData *data;
    int i = 0;
    for (NSObject *item in objects) {
        // Create photo's new path (images/reportID/photoName)
        FIRStorageReference *path = [storageRef child:[[[@"images/" stringByAppendingString: ref.documentID] stringByAppendingString: @"/"] stringByAppendingString: [NSString stringWithFormat:@"%d",i]]];
        
        i++;
        data = [item valueForKey:@"processedImage"];
        
        // Uploads the file (data) to the storage location (path)
        FIRStorageUploadTask *uploadTask = [path putData:data metadata:mdata
          completion:^(FIRStorageMetadata *metadata, NSError *error) {
              if (error != nil) {
                  NSLog(@"Error uploading image: %@", error);
              } else {
                  // Fetches the photo's download URL and adds it to the report's "images" array field
                  [path downloadURLWithCompletion:^(NSURL *URL, NSError *error){
                      if (error != nil) {
                          NSLog(@"Error retrieving download url: %@", error);
                      } else {
                          FIRDocumentReference *ref3 = [[self.db collectionWithPath:@"reports"] documentWithPath:ref.documentID];
                          NSString *sURL = URL.absoluteString;
                          [ref3 updateData:@{@"images": [FIRFieldValue fieldValueForArrayUnion:@[sURL]]}];
                      }
                  }];
              }
          }];
        
    }
    
    [self.managedObject setValue:nil forKey:@"measurements"];
    [self performSegueWithIdentifier:@"AdditionalInfoSegue" sender:self];
}


-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return 2;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
    if(section ==0){
        return @"Your data";
    }
    if(section ==1){
        return @"Your results";
    }
    else return @"";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if(section == 0){
        return 3;
    }
    if(section ==1){
        return 5;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell =[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"TableDataItem"];
    if(indexPath.section==0){
        [cell.textLabel setText:_keyData[indexPath.row]];
        [cell.detailTextLabel setText:_valueData[indexPath.row]];
    }
    else if(indexPath.section==1){
        NSInteger sectionDataOffset =[self tableView:tableView numberOfRowsInSection:indexPath.section-1];
        [cell.textLabel setText:_keyData[indexPath.row+ sectionDataOffset ]];
        [cell.detailTextLabel setText:_valueData[indexPath.row+ sectionDataOffset ]];
        
    }
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.backgroundColor = [UIColor clearColor];
    
    return cell;
}


@end
