//
//  CKModifyRecordZonesOperation.m
//  AgileCloudSDK
//
//  Copyright (c) 2015 AgileBits Inc. All rights reserved.
//

#import "CKModifyRecordZonesOperation.h"
#import "CKDatabaseOperation_Private.h"
#import "NSArray+AgileMap.h"
#import "CKRecord+AgileDictionary.h"
#import "CKRecordID+AgileDictionary.h"
#import "CKRecordZoneID+AgileDictionary.h"
#import "CKRecord_Private.h"
#import "CKDatabase_Private.h"
#import "Defines.h"
#import "NSError+AgileCloudSDKExtensions.h"
#import "CKError.h"
#import "CKRecordZone.h"
#import "CKContainer.h"

@implementation CKModifyRecordZonesOperation

- (instancetype)init {
	if (self = [super init]) {
	}
	return self;
}


- (instancetype)initWithRecordZonesToSave:(NSArray *)recordZonesToSave recordZoneIDsToDelete:(NSArray *)recordZoneIDsToDelete {
	if (self = [self init]) {
		_recordZonesToSave = recordZonesToSave;
		_recordZoneIDsToDelete = recordZoneIDsToDelete;
	}
	return self;
}

- (void)start {
	[self setExecuting:YES];
	
	if ([_recordZoneIDsToDelete count] || [_recordZonesToSave count]) {
		NSMutableDictionary *savedZoneIDToZone = [NSMutableDictionary dictionary];
		// the response doesn't contain the owner name so we have to preserve it - kevin 2015-12-09
		NSMutableDictionary *savedZoneIDOwnerNames = [NSMutableDictionary dictionary];
		
		NSArray *ops = @[];
		ops = [ops arrayByAddingObjectsFromArray:[_recordZoneIDsToDelete agile_mapUsingBlock:^id(id obj, NSUInteger idx) {
			return @{ @"operationType" : @"delete",
					  @"zone" : @{ @"zoneID": [obj asAgileDictionary] } };
		}]];
		
		
		ops = [ops arrayByAddingObjectsFromArray:[_recordZonesToSave agile_mapUsingBlock:^id(id obj, NSUInteger idx) {
			[savedZoneIDToZone setObject:obj forKey:[obj zoneID]];
			[savedZoneIDOwnerNames setObject:[[obj zoneID] ownerName] forKey:[[obj zoneID] zoneName]];
			return @{ @"operationType" : @"create",
					  @"zone" : [obj asAgileDictionary] };
		}]];
		
		NSDictionary *requestDictionary = @{ @"operations": ops };
		
		[self.database sendPOSTRequestTo:@"zones/modify" withJSON:requestDictionary completionHandler:^(id jsonResponse, NSError *error) {
			NSMutableArray* savedZones = [NSMutableArray array];
			NSMutableArray* deletedZones = [NSMutableArray array];
			NSMutableDictionary* partialFailures = [NSMutableDictionary dictionary];
			
			if ([jsonResponse isKindOfClass:[NSDictionary class]] && jsonResponse[@"zones"]) {
				[jsonResponse[@"zones"] enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
					
					NSString *zoneName = obj[@"zoneID"][@"zoneName"];
					CKRecordZoneID* savedZoneID = [[CKRecordZoneID alloc] initWithZoneName:zoneName ownerName:savedZoneIDOwnerNames[zoneName]];
					CKRecordZone* originalZone = savedZoneIDToZone[savedZoneID];
					
					if (originalZone) {
						NSError* recordError = nil;
						if (obj[@"serverErrorCode"]) {
							recordError = [[NSError alloc] initWithCKErrorDictionary:obj];
							[partialFailures setObject:recordError forKey:originalZone.zoneID];
						}
						else {
							[savedZones addObject:originalZone];
						}
					}
					else if (obj[@"deleted"]) {
						// was it deleted?
						[deletedZones addObject:savedZoneID];
					}
				}];
			}
			else if (!error) {
				error = [[NSError alloc] initWithCKErrorDictionary:jsonResponse];
			}
			
			if (!error && [[partialFailures allKeys] count]) {
				NSDictionary* userInfo = @{ CKErrorUserInfoPartialErrorsKey : self.database.container.containerIdentifier,
											CKErrorUserInfoPartialErrorsKey : partialFailures };
				error = [[NSError alloc] initWithDomain:CKErrorDomain code:CKErrorPartialFailure userInfo:userInfo];
			}
			
			if (self.modifyRecordZonesCompletionBlock) {
				self.modifyRecordZonesCompletionBlock(savedZones, deletedZones, error);
			}
			
			[self setExecuting:NO];
			[self setFinished:YES];
		}];
	}
}

@end
