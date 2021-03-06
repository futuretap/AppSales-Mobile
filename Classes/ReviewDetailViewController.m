//
//  ReviewDetailViewController.m
//  AppSales
//
//  Created by Ole Zorn on 28.07.11.
//  Copyright 2011 omz:software. All rights reserved.
//

#import "ReviewDetailViewController.h"
#import "LoginManager.h"
#import "CountryDictionary.h"
#import "Product.h"
#import "Version.h"
#import "Review.h"
#import "DeveloperResponse.h"

@implementation ReviewDetailViewController

- (instancetype)initWithReviews:(NSArray<Review *> *)_reviews selectedIndex:(NSInteger)_index {
	reviews = _reviews;
	index = _index;
	self = [super init];
	if (self) {
		// Initialization code
		formatter = [[NSNumberFormatter alloc] init];
		formatter.locale = [NSLocale currentLocale];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
		formatter.usesGroupingSeparator = YES;
		
		dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setDateStyle:NSDateFormatterMediumStyle];
		
		self.title = [NSString stringWithFormat:NSLocalizedString(@"%@ of %@", nil), [formatter stringFromNumber:@(index + 1)], [formatter stringFromNumber:@(reviews.count)]];
	}
	return self;
}

- (void)loadView {
	[super loadView];
	
	UIEdgeInsets contentInset = UIEdgeInsetsMake(0.0f, 0.0f, 44.0f, 0.0f);
	
	webView = [[UIWebView alloc] initWithFrame:CGRectZero];
	webView.backgroundColor = [UIColor whiteColor];
	webView.opaque = NO;
	webView.scalesPageToFit = YES;
	webView.dataDetectorTypes = UIDataDetectorTypeNone;
	webView.scrollView.contentInset = contentInset;
	webView.scrollView.scrollIndicatorInsets = contentInset;
	self.view = webView;
	
	toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.0f, self.view.bounds.size.height - contentInset.bottom, self.view.bounds.size.width, contentInset.bottom)];
	toolbar.autoresizingMask = (UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth);
	[self.view addSubview:toolbar];
	
	previousItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ChevronUp"] style:UIBarButtonItemStylePlain target:self action:@selector(previousReview)];
	nextItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ChevronDown"] style:UIBarButtonItemStylePlain target:self action:@selector(nextReview)];
	
	UIBarButtonItem *flexSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	markItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Circle"] style:UIBarButtonItemStylePlain target:self action:@selector(markReview)];
	UIBarButtonItem *sendReviewButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(sendReviewViaEmail)];
	UIBarButtonItem *replyButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemReply target:self action:@selector(replyToReview)];
	
	toolbar.items = @[markItem, flexSpaceItem, sendReviewButtonItem, flexSpaceItem, replyButtonItem];
	toolbar.translucent = YES;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	
	self.navigationItem.rightBarButtonItems = @[nextItem, previousItem];
	
	[self updateCurrentReview];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)updateToolbarButtons {
	previousItem.enabled = (0 < index);
	nextItem.enabled = (index < (reviews.count - 1));
	markItem.image = reviews[index].unread.boolValue ? [UIImage imageNamed:@"CircleFilled"] : [UIImage imageNamed:@"Circle"];
}

- (void)markUnread:(BOOL)unread {
	Review *review = reviews[index];
	review.unread = @(unread);
	
	markItem.image = review.unread.boolValue ? [UIImage imageNamed:@"CircleFilled"] : [UIImage imageNamed:@"Circle"];
	
	NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] init];
	moc.persistentStoreCoordinator = review.managedObjectContext.persistentStoreCoordinator;
	moc.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
	
	[moc.persistentStoreCoordinator performBlockAndWait:^{
		NSError *saveError = nil;
		[moc save:&saveError];
		if (saveError) {
			NSLog(@"Could not save context: %@", saveError);
		}
	}];
}

- (void)markReview {
	[self markUnread:!reviews[index].unread.boolValue];
}

- (void)replyToReview {
	NSLog(@"Reply to customer review here.");
}

- (void)previousReview {
	if (0 < index) {
		index--;
		[self updateCurrentReview];
	}
}

- (void)nextReview {
	if (index < (reviews.count - 1)) {
		index++;
		[self updateCurrentReview];
	}
}

- (void)updateCurrentReview {
	[self updateToolbarButtons];
	[self markUnread:NO];
	[self updateReviewWithTitle:nil text:nil];
}

- (void)updateReviewWithTitle:(NSString *)title text:(NSString *)text {
	self.title = [NSString stringWithFormat:NSLocalizedString(@"%@ of %@", nil), [formatter stringFromNumber:@(index + 1)], [formatter stringFromNumber:@(reviews.count)]];
	
	Review *review = reviews[index];
	
	NSString *reviewTitle = title ?: review.title;
	
	NSString *reviewText = text ?: review.text;
	reviewText = [reviewText stringByReplacingOccurrencesOfString:@"\n" withString:@"<br/>"];
	
	NSString *ratingString = [@"" stringByPaddingToLength:review.rating.integerValue withString:@"\u2605" startingAtIndex:0];
	ratingString = [ratingString stringByPaddingToLength:5 withString:@"\u2606" startingAtIndex:0];
	
	UIImage *flagImage = [UIImage imageNamed:review.countryCode.uppercaseString];
	if (flagImage == nil) {
		flagImage = [UIImage imageNamed:@"WW"];
	}
	NSData *flagData = UIImagePNGRepresentation(flagImage);
	NSString *flagBase64 = [flagData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
	NSString *countryName = [[CountryDictionary sharedDictionary] nameForCountryCode:review.countryCode.uppercaseString];
	
	NSString *template = [[NSString alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"ReviewTemplate" ofType:@"html"] encoding:NSUTF8StringEncoding error:nil];
	template = [template stringByReplacingOccurrencesOfString:@"[[[TITLE]]]" withString:reviewTitle];
	template = [template stringByReplacingOccurrencesOfString:@"[[[RATING]]]" withString:ratingString];
	template = [template stringByReplacingOccurrencesOfString:@"[[[NICKNAME]]]" withString:review.nickname];
	template = [template stringByReplacingOccurrencesOfString:@"[[[DATE]]]" withString:[dateFormatter stringFromDate:review.lastModified]];
	template = [template stringByReplacingOccurrencesOfString:@"[[[COUNTRY_FLAG]]]" withString:flagBase64];
	template = [template stringByReplacingOccurrencesOfString:@"[[[COUNTRY_NAME]]]" withString:countryName];
	template = [template stringByReplacingOccurrencesOfString:@"[[[CONTENT]]]" withString:reviewText];
	
	[webView loadHTMLString:template baseURL:nil];
}

- (void)sendReviewViaEmail {
	Review *review = reviews[index];
	if (![MFMailComposeViewController canSendMail]) {
		[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Email Account", nil) message:NSLocalizedString(@"You have not configured this device for sending email.", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] show];
		return;
	}
	MFMailComposeViewController *mailComposeViewController = [[MFMailComposeViewController alloc] init];
	mailComposeViewController.mailComposeDelegate = self;
	[mailComposeViewController setSubject:[NSString stringWithFormat:@"%@ %@ Review From %@", review.product.displayName, review.version.number, review.nickname]];
	[mailComposeViewController setMessageBody:review.text isHTML:NO];
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		mailComposeViewController.modalPresentationStyle = UIModalPresentationFormSheet;
	}
	[self presentViewController:mailComposeViewController animated:YES completion:nil];
}

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
