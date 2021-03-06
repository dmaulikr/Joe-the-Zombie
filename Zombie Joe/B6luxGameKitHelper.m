/*
 * cocos2d-project http://www.learn-cocos2d.com
 *
 * Copyright (c) 2010 Steffen Itterheim
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "B6luxGameKitHelper.h"
#import "cfg.h"

static NSString* kCachedAchievementsFile = @"CachedAchievements.archive";

@interface B6luxGameKitHelper (Private)
-(void) registerForLocalPlayerAuthChange;
-(void) setLastError:(NSError*)error;
-(void) initCachedAchievements;
-(void) cacheAchievement:(GKAchievement*)achievement;
-(void) uncacheAchievement:(GKAchievement*)achievement;
-(void) loadAchievements;
-(void) initMatchInvitationHandler;
-(UIViewController*) getRootViewController;
@end

@implementation B6luxGameKitHelper
@synthesize isLeaderboardShow;

static B6luxGameKitHelper *instanceOfB6luxGameKitHelper;

#pragma mark Singleton stuff
+(id) alloc
{
	@synchronized(self)	
	{
		NSAssert(instanceOfB6luxGameKitHelper == nil, @"Attempted to allocate a second instance of the singleton: B6luxGameKitHelper");
		instanceOfB6luxGameKitHelper = [[super alloc] retain];
		return instanceOfB6luxGameKitHelper;
	}
	
	// to avoid compiler warning
	return nil;
}

+(B6luxGameKitHelper*) sharedB6luxGameKitHelper
{
	@synchronized(self)
	{
		if (instanceOfB6luxGameKitHelper == nil)
		{
			[[B6luxGameKitHelper alloc] init];
		}
		
		return instanceOfB6luxGameKitHelper;
	}
	
	// to avoid compiler warning
	return nil;
}

#pragma mark Init & Dealloc

@synthesize delegate;
@synthesize isGameCenterAvailable;
@synthesize lastError;
@synthesize topPlayer;
@synthesize achievements;
@synthesize currentMatch;
@synthesize matchStarted;

-(id) init
{
	if ((self = [super init]))
	{
		// Test for Game Center availability
		Class gameKitLocalPlayerClass = NSClassFromString(@"GKLocalPlayer");
		bool isLocalPlayerAvailable = (gameKitLocalPlayerClass != nil);
		
		// Test if device is running iOS 4.1 or higher
		NSString* reqSysVer = @"4.1";
		NSString* currSysVer = [[UIDevice currentDevice] systemVersion];
		bool isOSVer41 = ([currSysVer compare:reqSysVer options:NSNumericSearch] != NSOrderedAscending);
		
		isGameCenterAvailable = (isLocalPlayerAvailable && isOSVer41);
		NSLog(@"GameCenter available = %@", isGameCenterAvailable ? @"YES" : @"NO");
        
        
        topPlayer = [[NSMutableDictionary alloc] init];
		[self registerForLocalPlayerAuthChange];
        
		[self initCachedAchievements];
	}
	
	return self;
}

-(void) dealloc
{
	CCLOG(@"dealloc %@", self);
	
	[instanceOfB6luxGameKitHelper release];
	instanceOfB6luxGameKitHelper = nil;
	
	[lastError release];
	
	[self saveCachedAchievements];
	[cachedAchievements release];
	[achievements release];
    [topPlayer release];
    [leaderboardRequest release];
	[currentMatch release];
    
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    
	[super dealloc];
}

#pragma mark setLastError

-(void) setLastError:(NSError*)error
{
	[lastError release];
	lastError = [error copy];
	
	if (lastError)
	{
		NSLog(@"B6luxGameKitHelper ERROR: %@", [[lastError userInfo] description]);
	}
}

#pragma mark Player Authentication

-(void) authenticateLocalPlayer
{
	if (isGameCenterAvailable == NO)
		return;
    
	GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
	if (localPlayer.authenticated == NO)
	{
		// Authenticate player, using a block object. See Apple's Block Programming guide for more info about Block Objects:
		// http://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/Blocks/Articles/00_Introduction.html
		[localPlayer authenticateWithCompletionHandler:^(NSError* error)
         {
             [self setLastError:error];
             
             if (error == nil)
             {
                 [self initMatchInvitationHandler];
                 [self reportCachedAchievements];
                 [self loadAchievements];
             }
         }];
		
		
		 // NOTE: bad example ahead!
		 
		 // If you want to modify a local variable inside a block object, you have to prefix it with the __block keyword.
		 __block bool success = NO;
		 
		 [localPlayer authenticateWithCompletionHandler:^(NSError* error)
		 {
         success = (error == nil);
		 }];
		 
		 // CAUTION: success will always be NO here! The block isn't run until later, when the authentication call was
		 // confirmed by the Game Center server. Set a breakpoint inside the block to see what is happening in what order.
		 if (success)
         NSLog(@"Local player logged in!");
		 else
         NSLog(@"Local player NOT logged in!");
		 
	}
}

-(void) onLocalPlayerAuthenticationChanged
{
	[delegate onLocalPlayerAuthenticationChanged];
}

-(void) registerForLocalPlayerAuthChange
{
	if (isGameCenterAvailable == NO)
		return;
    
	// Register to receive notifications when local player authentication status changes
	NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self
		   selector:@selector(onLocalPlayerAuthenticationChanged)
			   name:GKPlayerAuthenticationDidChangeNotificationName
			 object:nil];
}

#pragma mark Friends & Player Info

-(void) getLocalPlayerFriends
{
	if (isGameCenterAvailable == NO)
		return;
	
	GKLocalPlayer* localPlayer = [GKLocalPlayer localPlayer];
	if (localPlayer.authenticated)
	{
		// First, get the list of friends (player IDs)
		[localPlayer loadFriendsWithCompletionHandler:^(NSArray* friends, NSError* error)
         {
             [self setLastError:error];
             [delegate onFriendListReceived:friends];
         }];
	}
}

-(void) getPlayerInfo:(NSArray*)playerList
{
	if (isGameCenterAvailable == NO)
		return;
    
	// Get detailed information about a list of players
	if ([playerList count] > 0)
	{
		[GKPlayer loadPlayersForIdentifiers:playerList withCompletionHandler:^(NSArray* players, NSError* error)
         {
             [self setLastError:error];
             [delegate onPlayerInfoReceived:players];
             
             if (players != nil) {
                 NSLog(@"leader Score: %@", players);
             }

         }];
	}
}

#pragma mark Scores & Leaderboard

-(void) submitBrainScore:(int)score
{
    int64_t score_ = score;
    
	if (isGameCenterAvailable == NO)
		return;
    
	GKScore* gkScore = [[[GKScore alloc] initWithCategory:@"Brain_"] autorelease];
	gkScore.value = score_;
    
	[gkScore reportScoreWithCompletionHandler:^(NSError* error)
     {
         [self setLastError:error];
         
         bool success = (error == nil);
         [delegate onScoresSubmitted:success];
     }];
}

-(void) submitMainScore:(int)score
{
    int64_t score_ = score;
    
	if (isGameCenterAvailable == NO)
		return;
    
	GKScore* gkScore = [[[GKScore alloc] initWithCategory:@"Main_"] autorelease];
	gkScore.value = score_;
    
	[gkScore reportScoreWithCompletionHandler:^(NSError* error)
     {
         [self setLastError:error];
         
         bool success = (error == nil);
         [delegate onScoresSubmitted:success];
     }];
}

-(void) submitScore:(int)score level:(int)level
{
    NSString *levelStr = [NSString stringWithFormat:@"Level%i_",level];
    int64_t score_ = score;
    
	if (isGameCenterAvailable == NO)
		return;
    
	GKScore* gkScore = [[[GKScore alloc] initWithCategory:levelStr] autorelease];
	gkScore.value = score_;
    
	[gkScore reportScoreWithCompletionHandler:^(NSError* error)
     {
         [self setLastError:error];
         
         bool success = (error == nil);
         [delegate onScoresSubmitted:success];
     }];
}

-(void) retrieveScoresForPlayers:(NSArray*)players
						category:(NSString*)levelStr 
						   range:(NSRange)range
					 playerScope:(GKLeaderboardPlayerScope)playerScope 
					   timeScope:(GKLeaderboardTimeScope)timeScope 
{
	if (isGameCenterAvailable == NO)
		return;
	
	GKLeaderboard* leaderboard = nil;
	if ([players count] > 0)
	{
		leaderboard = [[[GKLeaderboard alloc] initWithPlayerIDs:players] autorelease];
	}
	else
	{
		leaderboard = [[[GKLeaderboard alloc] init] autorelease];
		leaderboard.playerScope = playerScope;
	}
	
	if (leaderboard != nil)
	{
		leaderboard.timeScope = timeScope;
		leaderboard.category = levelStr;
		leaderboard.range = range;
		[leaderboard loadScoresWithCompletionHandler:^(NSArray* scores, NSError* error)
         {
             [self setLastError:error];
             [delegate onScoresReceived:scores];
             
             if (scores != nil) {
                 NSLog(@"leader Score: %@", scores);
             }
         }];
    
	}
}
- (void)checkTopPlayers
{
    /*
    [self retrieveTopPlayerFromCategory:gc_MAIN];
    [self retrieveTopPlayerFromCategory:gc_BRAIN];
    
    for (int i = 1; i<=15; i++)
    {
        [self retrieveTopPlayerFromCategory:gc_LEVEL(i)];
    }
     */
     
}

-(NSString *)getLocalPlayerAlias
{
    if ([GKLocalPlayer localPlayer].alias == nil) {
        return @"unknown";
    }
    return [GKLocalPlayer localPlayer].alias;
}

- (NSString *)returnTopPlayerByCategory:(NSString *)category type:(int)type_
{
    if (topPlayer == nil) {
        [self checkTopPlayers];
    }
    
    NSString *a = [topPlayer valueForKey:category];
    NSArray *dataArray = [a componentsSeparatedByString:@"[]"];
    return dataArray[type_];
}

- (void) retrieveTopPlayerFromCategory:(NSString *)category
{
    NSMutableArray *playerIDs=[NSMutableArray arrayWithCapacity:1];
    NSMutableArray *nameArray=[NSMutableArray arrayWithCapacity:1];
    
    
    leaderboardRequest = [[GKLeaderboard alloc] init];

    if (leaderboardRequest != nil)
    {
     
        if (category != nil) {
            
            leaderboardRequest.category = category;
        }
        leaderboardRequest.playerScope = GKLeaderboardPlayerScopeGlobal;
        leaderboardRequest.timeScope = GKLeaderboardTimeScopeAllTime;
        leaderboardRequest.range = NSMakeRange(1,1);
        
        [leaderboardRequest loadScoresWithCompletionHandler: ^(NSArray *scores, NSError *error) {
            if (error != nil)
            {
                // handle the error.
            }
            if (scores != nil)
            {
                // process the score information.
                //NSString *myArrayString = [scores description];
                for (int i=0; i<[scores count]; i++)
                    [playerIDs addObject:[[scores objectAtIndex:i] playerID]];
                
                //NSLog(@"MYARRAYSTRING:    %@",myArrayString);
        
             
                
                [GKPlayer loadPlayersForIdentifiers:playerIDs withCompletionHandler:^(NSArray *players, NSError *error) {
                    if (error != nil)
                    {
                       // NSLog(@"error GKPlayer");
                        // Handle the error.
                    }
                    if (players != nil)
                    {
    
                        for(int i = 0; i<[players count]; i++) {
                            [nameArray addObject:[[players objectAtIndex:i]alias]];
                        }
                        
                        NSString *values_ = [NSString stringWithFormat:@"%@[]%@",nameArray[0],[NSNumber numberWithInt:(int64_t)[[scores objectAtIndex:0] value]]];
                        
                        [topPlayer setObject:values_ forKey:category];
                        
                       // NSLog(@"TOP PLAYEAR: %@",topPlayer);
                                               
                    }
                }];
            }
        }];
    }
}



#pragma mark Achievements

-(void) loadAchievements
{
	if (isGameCenterAvailable == NO)
		return;
    
	[GKAchievement loadAchievementsWithCompletionHandler:^(NSArray* loadedAchievements, NSError* error)
     {
         [self setLastError:error];
		 
         if (achievements == nil)
         {
             achievements = [[NSMutableDictionary alloc] init];
         }
         else
         {
             [achievements removeAllObjects];
         }
         
         for (GKAchievement* achievement in loadedAchievements)
         {
             [achievements setObject:achievement forKey:achievement.identifier];
         }
		 
         [delegate onAchievementsLoaded:achievements];
     }];
}

-(GKAchievement*) getAchievementByID:(NSString*)identifier
{
	if (isGameCenterAvailable == NO)
		return nil;
    
	// Try to get an existing achievement with this identifier
	GKAchievement* achievement = [achievements objectForKey:identifier];
	
	if (achievement == nil)
	{
		// Create a new achievement object
		achievement = [[[GKAchievement alloc] initWithIdentifier:identifier] autorelease];
		[achievements setObject:achievement forKey:achievement.identifier];
	}
	
	return [[achievement retain] autorelease];
}

-(void) reportAchievementWithID:(NSString*)identifier percentComplete:(float)percent
{
	if (isGameCenterAvailable == NO)
		return;
    
	GKAchievement* achievement = [self getAchievementByID:identifier];
	if (achievement != nil && achievement.percentComplete < percent)
	{
		achievement.percentComplete = percent;
		[achievement reportAchievementWithCompletionHandler:^(NSError* error)
         {
             [self setLastError:error];
             
             bool success = (error == nil);
             if (success == NO)
             {
                 // Keep achievement to try to submit it later
                 [self cacheAchievement:achievement];
             }
             
             [delegate onAchievementReported:achievement];
         }];
	}
}

-(void) resetAchievements
{
	if (isGameCenterAvailable == NO)
		return;
	
	[achievements removeAllObjects];
	[cachedAchievements removeAllObjects];
	
	[GKAchievement resetAchievementsWithCompletionHandler:^(NSError* error)
     {
         [self setLastError:error];
         bool success = (error == nil);
         [delegate onResetAchievements:success];
     }];
}

-(void) reportCachedAchievements
{
	if (isGameCenterAvailable == NO)
		return;
	
	if ([cachedAchievements count] == 0)
		return;
    
	for (GKAchievement* achievement in [cachedAchievements allValues])
	{
		[achievement reportAchievementWithCompletionHandler:^(NSError* error)
         {
             bool success = (error == nil);
             if (success == YES)
             {
                 [self uncacheAchievement:achievement];
             }
         }];
	}
}

-(void) initCachedAchievements
{
	NSString* file = [NSHomeDirectory() stringByAppendingPathComponent:kCachedAchievementsFile];
	id object = [NSKeyedUnarchiver unarchiveObjectWithFile:file];
	
	if ([object isKindOfClass:[NSMutableDictionary class]])
	{
		NSMutableDictionary* loadedAchievements = (NSMutableDictionary*)object;
		cachedAchievements = [[NSMutableDictionary alloc] initWithDictionary:loadedAchievements];
	}
	else
	{
		cachedAchievements = [[NSMutableDictionary alloc] init];
	}
}

-(void) saveCachedAchievements
{
	NSString* file = [NSHomeDirectory() stringByAppendingPathComponent:kCachedAchievementsFile];
	[NSKeyedArchiver archiveRootObject:cachedAchievements toFile:file];
}

-(void) cacheAchievement:(GKAchievement*)achievement
{
	[cachedAchievements setObject:achievement forKey:achievement.identifier];
	
	// Save to disk immediately, to keep achievements around even if the game crashes.
	[self saveCachedAchievements];
}

-(void) uncacheAchievement:(GKAchievement*)achievement
{
	[cachedAchievements removeObjectForKey:achievement.identifier];
	
	// Save to disk immediately, to keep the removed cached achievement from being loaded again
	[self saveCachedAchievements];
}

#pragma mark Matchmaking

-(void) disconnectCurrentMatch
{
	[currentMatch disconnect];
	currentMatch.delegate = nil;
	[currentMatch release];
	currentMatch = nil;
}

-(void) setCurrentMatch:(GKMatch*)match
{
	if ([currentMatch isEqual:match] == NO)
	{
		[self disconnectCurrentMatch];
		currentMatch = [match retain];
		currentMatch.delegate = self;
	}
}

-(void) initMatchInvitationHandler
{
	if (isGameCenterAvailable == NO)
		return;
    
	[GKMatchmaker sharedMatchmaker].inviteHandler = ^(GKInvite* acceptedInvite, NSArray* playersToInvite)
	{
		[self disconnectCurrentMatch];
		
		if (acceptedInvite)
		{
			[self showMatchmakerWithInvite:acceptedInvite];
		}
		else if (playersToInvite)
		{
			GKMatchRequest* request = [[[GKMatchRequest alloc] init] autorelease];
			request.minPlayers = 2;
			request.maxPlayers = 4;
			request.playersToInvite = playersToInvite;
            
			[self showMatchmakerWithRequest:request];
		}
	};
}

-(void) findMatchForRequest:(GKMatchRequest*)request
{
	if (isGameCenterAvailable == NO)
		return;
	
	[[GKMatchmaker sharedMatchmaker] findMatchForRequest:request withCompletionHandler:^(GKMatch* match, NSError* error)
     {
         [self setLastError:error];
         
         if (match != nil)
         {
             [self setCurrentMatch:match];
             [delegate onMatchFound:match];
         }
     }];
}

-(void) addPlayersToMatch:(GKMatchRequest*)request
{
	if (isGameCenterAvailable == NO)
		return;
    
	if (currentMatch == nil)
		return;
	
	[[GKMatchmaker sharedMatchmaker] addPlayersToMatch:currentMatch matchRequest:request completionHandler:^(NSError* error)
     {
         [self setLastError:error];
         
         bool success = (error == nil);
         [delegate onPlayersAddedToMatch:success];
     }];
}

-(void) cancelMatchmakingRequest
{
	if (isGameCenterAvailable == NO)
		return;
    
	[[GKMatchmaker sharedMatchmaker] cancel];
}

-(void) queryMatchmakingActivity
{
	if (isGameCenterAvailable == NO)
		return;
    
	[[GKMatchmaker sharedMatchmaker] queryActivityWithCompletionHandler:^(NSInteger activity, NSError* error)
     {
         [self setLastError:error];
         
         if (error == nil)
         {
             [delegate onReceivedMatchmakingActivity:activity];
         }
     }];
}

#pragma mark Match Connection

-(void) match:(GKMatch*)match player:(NSString*)playerID didChangeState:(GKPlayerConnectionState)state
{
	switch (state)
	{
		case GKPlayerStateConnected:
			[delegate onPlayerConnected:playerID];
			break;
		case GKPlayerStateDisconnected:
			[delegate onPlayerDisconnected:playerID];
			break;
	}
	
	if (matchStarted == NO && match.expectedPlayerCount == 0)
	{
		matchStarted = YES;
		[delegate onStartMatch];
	}
}

-(void) sendDataToAllPlayers:(void*)data length:(NSUInteger)length
{
	if (isGameCenterAvailable == NO)
		return;
	
	NSError* error = nil;
	NSData* packet = [NSData dataWithBytes:data length:length];
	[currentMatch sendDataToAllPlayers:packet withDataMode:GKMatchSendDataUnreliable error:&error];
	[self setLastError:error];
}

-(void) match:(GKMatch*)match didReceiveData:(NSData*)data fromPlayer:(NSString*)playerID
{
	[delegate onReceivedData:data fromPlayer:playerID];
}

#pragma mark Views (Leaderboard, Achievements)

// Helper methods

-(id)getRootViewController_iOS5
{

    return [[[[[UIApplication sharedApplication] keyWindow] subviews] objectAtIndex:0] nextResponder];

}

-(UIViewController*) getRootViewController
{
	return [UIApplication sharedApplication].keyWindow.rootViewController;//Dont Work on iOS 5!!!
}

-(void) presentViewController:(UIViewController*)vc
{
//    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 6.0){
//        [[self getRootViewController] presentViewController:vc animated:YES completion:nil];
//    }
//    else
//    {
         [[self getRootViewController_iOS5] presentViewController:vc animated:YES completion:nil];
   // }
  
}

-(void) dismissModalViewController
{
    
//    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 6.0){
//        [[self getRootViewController] dismissViewControllerAnimated:YES completion:^{
//            if ([[[CCDirector sharedDirector] openGLView]viewWithTag:kLOADINGTAG]) {
//                [[[[CCDirector sharedDirector] openGLView]viewWithTag:kLOADINGTAG]removeFromSuperview];
//            }
//            isLeaderboardShow = NO;
//        }];
//
//    }
//    else
//    {
        [[self getRootViewController_iOS5] dismissViewControllerAnimated:YES completion:^{
            if ([[[CCDirector sharedDirector] openGLView]viewWithTag:kLOADINGTAG]) {
                [[[[CCDirector sharedDirector] openGLView]viewWithTag:kLOADINGTAG]removeFromSuperview];
            }
            isLeaderboardShow = NO;
        }];
 //   }
  
}

// Leaderboards

-(void) showLeaderboard:(NSString *)category
{
    
    isLeaderboardShow = YES;
	if (isGameCenterAvailable == NO){
        if ([[[CCDirector sharedDirector] openGLView]viewWithTag:kLOADINGTAG]) {
            [[[[CCDirector sharedDirector] openGLView]viewWithTag:kLOADINGTAG]removeFromSuperview];
        }
		return;
    }
	
	GKLeaderboardViewController* leaderboardVC = [[[GKLeaderboardViewController alloc] init] autorelease];
	if (leaderboardVC != nil)
	{
		leaderboardVC.leaderboardDelegate = self;
        leaderboardVC.category = category;
        
		[self presentViewController:leaderboardVC];
	}
     
    
}

-(void) leaderboardViewControllerDidFinish:(GKLeaderboardViewController*)viewController
{
    if ([[[CCDirector sharedDirector] openGLView]viewWithTag:kLOADINGTAG]) {
        [[[[CCDirector sharedDirector] openGLView]viewWithTag:kLOADINGTAG]setUserInteractionEnabled:YES];
        [[[[CCDirector sharedDirector] openGLView]viewWithTag:kLOADINGTAG] setHidden:YES];
    }
    [self dismissModalViewController];
    
	//[delegate onLeaderboardViewDismissed]; //Loads Acheivements after ???
}

// Achievements

-(void) showAchievements
{
	if (isGameCenterAvailable == NO)
		return;
	
	GKAchievementViewController* achievementsVC = [[[GKAchievementViewController alloc] init] autorelease];
	if (achievementsVC != nil)
	{
		achievementsVC.achievementDelegate = self;
		[self presentViewController:achievementsVC];
	}
}

-(void) achievementViewControllerDidFinish:(GKAchievementViewController*)viewController
{
   
	[self dismissModalViewController];
    
	//[delegate onAchievementsViewDismissed];
}

// Matchmaking

-(void) showMatchmakerWithInvite:(GKInvite*)invite
{
	GKMatchmakerViewController* inviteVC = [[[GKMatchmakerViewController alloc] initWithInvite:invite] autorelease];
	if (inviteVC != nil)
	{
		inviteVC.matchmakerDelegate = self;
		[self presentViewController:inviteVC];
	}
}

-(void) showMatchmakerWithRequest:(GKMatchRequest*)request
{
	GKMatchmakerViewController* hostVC = [[[GKMatchmakerViewController alloc] initWithMatchRequest:request] autorelease];
	if (hostVC != nil)
	{
		hostVC.matchmakerDelegate = self;
		[self presentViewController:hostVC];
	}
}

-(void) matchmakerViewControllerWasCancelled:(GKMatchmakerViewController*)viewController
{
	[self dismissModalViewController];
	[delegate onMatchmakingViewDismissed];
}

-(void) matchmakerViewController:(GKMatchmakerViewController*)viewController didFailWithError:(NSError*)error
{
	[self dismissModalViewController];
	[self setLastError:error];
	[delegate onMatchmakingViewError];
}

-(void) matchmakerViewController:(GKMatchmakerViewController*)viewController didFindMatch:(GKMatch*)match
{
	[self dismissModalViewController];
	[self setCurrentMatch:match];
	[delegate onMatchFound:match];
}

@end
