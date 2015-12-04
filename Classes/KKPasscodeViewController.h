//
// Copyright 2011-2012 Kosher Penguin LLC 
// Created by Adar Porat (https://github.com/aporat) on 1/16/2012.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//		http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <UIKit/UIKit.h>


enum {
	KKPasscodeModeEnter = 0,
	KKPasscodeModeSet = 1,
	KKPasscodeModeDisabled = 2,
	KKPasscodeModeChange = 3
};
typedef NSUInteger KKPasscodeMode;


@class KKPasscodeViewController;

@protocol KKPasscodeViewControllerDelegate <NSObject>

@optional

- (void)didPasscodeEnteredCorrectly:(KKPasscodeViewController *)viewController;
- (void)didPasscodeEnteredIncorrectly:(KKPasscodeViewController *)viewController;
- (void)shouldEraseApplicationData:(KKPasscodeViewController *)viewController;
- (void)didSettingsChanged:(KKPasscodeViewController *)viewController;

@end



@interface KKPasscodeViewController : UIViewController <UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource> {
	
	id<KKPasscodeViewControllerDelegate> __weak _delegate;
	
	UILabel *_passcodeConfirmationWarningLabel;
	UIView *_failedAttemptsView;
	UILabel *_failedAttemptsLabel;
	NSInteger _failedAttemptsCount;
	
	NSUInteger _tableIndex;
	NSMutableArray *_tableViews;
	NSMutableArray *_textFields;
	NSMutableArray *_squares;
	
	UITableView *_enterPasscodeTableView;
	UITextField *_enterPasscodeTextField;
	NSArray *_enterPasscodeSquareImageViews;
	
	UITableView *_setPasscodeTableView;
	UITextField *_setPasscodeTextField;
	NSArray *_setPasscodeSquareImageViews;
	
	UITableView *_confirmPasscodeTableView;
	UITextField *_confirmPasscodeTextField;
	NSArray *_confirmPasscodeSquareImageViews;
	
	BOOL _passcodeLockOn;
	BOOL _eraseData;
}

@property (nonatomic, weak) id <KKPasscodeViewControllerDelegate> delegate; 
@property (nonatomic, assign) KKPasscodeMode mode;
@property (nonatomic, assign) BOOL startTouchID;

@property (nonatomic, strong) UITableView *enterPasscodeTableView;
@property (nonatomic, strong) UITableView *setPasscodeTableView;
@property (nonatomic, strong) UITableView *confirmPasscodeTableView;

+ (BOOL)hasTouchID;
- (void)authenticateWithTouchID;

@end
