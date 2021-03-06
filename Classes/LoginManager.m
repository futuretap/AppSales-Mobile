//
//  LoginManager.m
//  AppSales
//
//  Created by Nicolas Gomollon on 12/1/15.
//
//

#import "LoginManager.h"

// Apple Auth API
NSString *const kAppleAuthBaseURL      = @"https://idmsa.apple.com/appleauth/auth";
NSString *const kAppleAuthSignInAction = @"/signin";
NSString *const kAppleAuthDeviceAction = @"/verify/device/%@/securitycode";
NSString *const kAppleAuthCodeAction   = @"/verify/trusteddevice/securitycode";
NSString *const kAppleAuthTrustAction  = @"/2sv/trust";

// Apple Auth API Headers
NSString *const kAppleAuthWidgetKey        = @"X-Apple-Widget-Key";
NSString *const kAppleAuthWidgetValue      = @"e0b80c3bf78523bfe80974d320935bfa30add02e1bff88ec2166c6bd5a706c42";
NSString *const kAppleAuthSessionIdKey     = @"X-Apple-ID-Session-Id";
NSString *const kAppleAuthScntKey          = @"scnt";
NSString *const kAppleAuthAcceptKey        = @"Accept";
NSString *const kAppleAuthAcceptValue      = @"application/json, text/javascript, */*; q=0.01";
NSString *const kAppleAuthContentTypeKey   = @"Content-Type";
NSString *const kAppleAuthContentTypeValue = @"application/json;charset=UTF-8";
NSString *const kAppleAuthLocationKey      = @"Location";
NSString *const kAppleAuthSetCookieKey     = @"Set-Cookie";

// iTunes Connect Payments API
NSString *const kITCBaseURL                     = @"https://itunesconnect.apple.com/WebObjects/iTunesConnect.woa";
NSString *const kITCSetCookiesAction            = @"/wa/route?noext";
NSString *const kITCUserDetailAction            = @"/ra/user/detail";
NSString *const kITCPaymentVendorsAction        = @"/ra/paymentConsolidation/providers/%@/sapVendorNumbers";
NSString *const kITCPaymentVendorsPaymentAction = @"/ra/paymentConsolidation/providers/%@/sapVendorNumbers/%@?year=%ld&month=%ld";

@implementation LoginManager

- (instancetype)init {
	return [self initWithAccount:nil];
}

- (instancetype)initWithAccount:(ASAccount *)_account {
	self = [super init];
	if (self) {
		// Initialization code
		account = _account;
		authType = SCInputTypeUnknown;
	}
	return self;
}

- (instancetype)initWithLoginInfo:(NSDictionary *)_loginInfo {
	self = [super init];
	if (self) {
		// Initialization code
		loginInfo = _loginInfo;
		authType = SCInputTypeUnknown;
	}
	return self;
}

- (BOOL)isLoggedIn {
	for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
		if ([cookie.domain rangeOfString:@"apple.com"].location != NSNotFound) {
			if ([cookie.name isEqualToString:@"myacinfo"]) {
				return YES;
			}
		}
	}
	return NO;
}

- (void)logOut {
	NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
	
	NSArray *cookies = [cookieStorage cookiesForURL:[NSURL URLWithString:@"https://itunesconnect.apple.com"]];
	for (NSHTTPCookie *cookie in cookies) {
		[cookieStorage deleteCookie:cookie];
	}
	
	cookies = [cookieStorage cookiesForURL:[NSURL URLWithString:@"https://reportingitc.apple.com"]];
	for (NSHTTPCookie *cookie in cookies) {
		[cookieStorage deleteCookie:cookie];
	}
	
	cookies = [cookieStorage cookiesForURL:[NSURL URLWithString:@"https://reportingitc2.apple.com"]];
	for (NSHTTPCookie *cookie in cookies) {
		[cookieStorage deleteCookie:cookie];
	}
	
	cookies = [cookieStorage cookiesForURL:[NSURL URLWithString:@"https://reportingitc-reporter.apple.com"]];
	for (NSHTTPCookie *cookie in cookies) {
		[cookieStorage deleteCookie:cookie];
	}
	
	if (self.shouldDeleteCookies) {
		cookies = [cookieStorage cookiesForURL:[NSURL URLWithString:@"https://idmsa.apple.com"]];
		for (NSHTTPCookie *cookie in cookies) {
			[cookieStorage deleteCookie:cookie];
		}
	}
}

- (void)logIn {
	[self logOut];
	
	authType = SCInputTypeUnknown;
	appleAuthTrustedDeviceId = nil;
	if (trustedDevices == nil) {
		trustedDevices = [[NSMutableArray alloc] init];
	} else {
		[trustedDevices removeAllObjects];
	}
	
	NSDictionary *bodyDict = @{@"accountName": account.username ?: loginInfo[@"username"],
							   @"password": account.password ?: loginInfo[@"password"],
							   @"rememberMe": @(YES)};
	NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
	
	NSURL *signInURL = [NSURL URLWithString:[kAppleAuthBaseURL stringByAppendingString:kAppleAuthSignInAction]];
	NSMutableURLRequest *signInRequest = [NSMutableURLRequest requestWithURL:signInURL];
	[signInRequest setHTTPMethod:@"POST"];
	[signInRequest setValue:kAppleAuthWidgetValue forHTTPHeaderField:kAppleAuthWidgetKey];
	[signInRequest setValue:kAppleAuthAcceptValue forHTTPHeaderField:kAppleAuthAcceptKey];
	[signInRequest setValue:kAppleAuthContentTypeValue forHTTPHeaderField:kAppleAuthContentTypeKey];
	[signInRequest setHTTPBody:bodyData];
	
	NSHTTPURLResponse *signInResponse = nil;
	[NSURLConnection sendSynchronousRequest:signInRequest returningResponse:&signInResponse error:nil];
	NSString *location = signInResponse.allHeaderFields[kAppleAuthLocationKey];
	appleAuthSessionId = signInResponse.allHeaderFields[kAppleAuthSessionIdKey];
	appleAuthScnt = signInResponse.allHeaderFields[kAppleAuthScntKey];
	
	if ((appleAuthSessionId.length == 0) || (appleAuthScnt.length == 0)) {
		// Wrong credentials?
		if ([self.delegate respondsToSelector:@selector(loginFailed)]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.delegate loginFailed];
			});
		}
	} else if (location.length == 0) {
		// We're in!
		[self fetchRemainingCookies];
		if ([self.delegate respondsToSelector:@selector(loginSucceeded)]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.delegate loginSucceeded];
			});
		}
	} else {
		// This account has either Two-Step Verification or Two-Factor Authentication enabled.
		NSURL *authURL = [NSURL URLWithString:kAppleAuthBaseURL];
		NSMutableURLRequest *authRequest = [NSMutableURLRequest requestWithURL:authURL];
		[authRequest setHTTPMethod:@"GET"];
		[authRequest setValue:kAppleAuthWidgetValue forHTTPHeaderField:kAppleAuthWidgetKey];
		[authRequest setValue:appleAuthSessionId forHTTPHeaderField:kAppleAuthSessionIdKey];
		[authRequest setValue:appleAuthScnt forHTTPHeaderField:kAppleAuthScntKey];
		[authRequest setValue:kAppleAuthAcceptValue forHTTPHeaderField:kAppleAuthAcceptKey];
		[authRequest setValue:kAppleAuthContentTypeValue forHTTPHeaderField:kAppleAuthContentTypeKey];
		NSHTTPURLResponse *authResponse = nil;
		NSData *authData = [NSURLConnection sendSynchronousRequest:authRequest returningResponse:&authResponse error:nil];
		NSDictionary *authDict = [NSJSONSerialization JSONObjectWithData:authData options:0 error:nil];
		
		NSString *authenticationType = authDict[@"authType"] ?: authDict[@"authenticationType"];
		if ([authenticationType isEqualToString:@"hsa"]) {
			// This account has Two-Step Verification enabled.
			authType = SCInputTypeTwoStepVerificationCode;
			NSNumber *accountLocked = authDict[@"accountLocked"];
			NSNumber *recoveryKeyLocked = authDict[@"recoveryKeyLocked"];
			NSNumber *securityCodeLocked = authDict[@"securityCodeLocked"];
			[trustedDevices addObjectsFromArray:authDict[@"trustedDevices"] ?: @[]];
			if (accountLocked.boolValue || recoveryKeyLocked.boolValue || securityCodeLocked.boolValue) {
				// User is temporarily locked out of account, and is unable to sign in at the moment. Try again later?
				if ([self.delegate respondsToSelector:@selector(loginFailed)]) {
					dispatch_async(dispatch_get_main_queue(), ^{
						[self.delegate loginFailed];
					});
				}
			} else if (trustedDevices.count == 0) {
				// Account has no trusted devices.
				if ([self.delegate respondsToSelector:@selector(loginFailed)]) {
					dispatch_async(dispatch_get_main_queue(), ^{
						[self.delegate loginFailed];
					});
				}
			} else {
				// Allow user to choose a trusted device.
				[self performSelectorOnMainThread:@selector(chooseTrustedDevice) withObject:nil waitUntilDone:NO];
			}
		} else if ([authenticationType isEqualToString:@"hsa2"]) {
			// This account has Two-Factor Authentication enabled.
			authType = SCInputTypeTwoFactorAuthenticationCode;
			NSDictionary *securityCodeDict = authDict[@"securityCode"];
			NSNumber *tooManyCodesSent = securityCodeDict[@"tooManyCodesSent"];
			NSNumber *tooManyCodesValidated = securityCodeDict[@"tooManyCodesValidated"];
			NSNumber *securityCodeLocked = securityCodeDict[@"securityCodeLocked"];
			if (tooManyCodesSent.boolValue || tooManyCodesValidated.boolValue || securityCodeLocked.boolValue) {
				// User is temporarily locked out of account, and is unable to sign in at the moment. Try again later?
				if ([self.delegate respondsToSelector:@selector(loginFailed)]) {
					dispatch_async(dispatch_get_main_queue(), ^{
						[self.delegate loginFailed];
					});
				}
			} else {
				// Display security code input controller.
				dispatch_async(dispatch_get_main_queue(), ^{
					SecurityCodeInputController *securityCodeInput = [[SecurityCodeInputController alloc] initWithType:SCInputTypeTwoFactorAuthenticationCode];
					securityCodeInput.delegate = self;
					[securityCodeInput show];
				});
			}
		} else {
			// Something else went wrong.
			if ([self.delegate respondsToSelector:@selector(loginFailed)]) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[self.delegate loginFailed];
				});
			}
		}
	}
}

- (void)fetchRemainingCookies {
	NSURL *trustURL = [NSURL URLWithString:[kAppleAuthBaseURL stringByAppendingString:kAppleAuthTrustAction]];
	NSMutableURLRequest *trustRequest = [NSMutableURLRequest requestWithURL:trustURL];
	[trustRequest setHTTPMethod:@"GET"];
	[trustRequest setValue:kAppleAuthWidgetValue forHTTPHeaderField:kAppleAuthWidgetKey];
	[trustRequest setValue:appleAuthSessionId forHTTPHeaderField:kAppleAuthSessionIdKey];
	[trustRequest setValue:appleAuthScnt forHTTPHeaderField:kAppleAuthScntKey];
	[trustRequest setValue:kAppleAuthContentTypeValue forHTTPHeaderField:kAppleAuthContentTypeKey];
	[NSURLConnection sendSynchronousRequest:trustRequest returningResponse:nil error:nil];
	
	NSURL *setCookiesURL = [NSURL URLWithString:[kITCBaseURL stringByAppendingString:kITCSetCookiesAction]];
	[NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:setCookiesURL] returningResponse:nil error:nil];
}

- (void)generateCode:(NSString *)_appleAuthTrustedDeviceId {
	appleAuthTrustedDeviceId = _appleAuthTrustedDeviceId;
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0ul), ^{
		NSURL *deviceURL = [NSURL URLWithString:[kAppleAuthBaseURL stringByAppendingFormat:kAppleAuthDeviceAction, _appleAuthTrustedDeviceId]];
		NSMutableURLRequest *deviceRequest = [NSMutableURLRequest requestWithURL:deviceURL];
		[deviceRequest setHTTPMethod:@"PUT"];
		[deviceRequest setValue:kAppleAuthWidgetValue forHTTPHeaderField:kAppleAuthWidgetKey];
		[deviceRequest setValue:appleAuthSessionId forHTTPHeaderField:kAppleAuthSessionIdKey];
		[deviceRequest setValue:appleAuthScnt forHTTPHeaderField:kAppleAuthScntKey];
		[deviceRequest setValue:kAppleAuthContentTypeValue forHTTPHeaderField:kAppleAuthContentTypeKey];
		NSHTTPURLResponse *deviceResponse = nil;
		NSData *deviceData = [NSURLConnection sendSynchronousRequest:deviceRequest returningResponse:&deviceResponse error:nil];
		NSDictionary *deviceDict = [NSJSONSerialization JSONObjectWithData:deviceData options:0 error:nil];
		
		NSDictionary *securityCode = deviceDict[@"securityCode"];
		NSNumber *securityCodeLength = securityCode[@"length"];
		if (securityCodeLength.integerValue == 4) {
			// Display security code input controller.
			dispatch_async(dispatch_get_main_queue(), ^{
				SecurityCodeInputController *securityCodeInput = [[SecurityCodeInputController alloc] initWithType:SCInputTypeTwoStepVerificationCode];
				securityCodeInput.delegate = self;
				[securityCodeInput show];
			});
		} else {
			// Authentication is requesting a security code with an unsupported number of digits.
			if ([self.delegate respondsToSelector:@selector(loginFailed)]) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[self.delegate loginFailed];
				});
			}
		}
	});
}

- (void)validateCode:(NSString *)securityCode {
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0ul), ^{
		NSDictionary *bodyDict = nil;
		switch (authType) {
			case SCInputTypeTwoStepVerificationCode:
				bodyDict = @{@"code": securityCode};
				break;
			case SCInputTypeTwoFactorAuthenticationCode:
				bodyDict = @{@"securityCode": @{@"code": securityCode}};
				break;
			default:
				bodyDict = @{};
				break;
		}
		NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
		
		NSURL *verifyURL = [NSURL URLWithString:[kAppleAuthBaseURL stringByAppendingFormat:kAppleAuthCodeAction]];
		if (authType == SCInputTypeTwoStepVerificationCode) {
			verifyURL = [NSURL URLWithString:[kAppleAuthBaseURL stringByAppendingFormat:kAppleAuthDeviceAction, appleAuthTrustedDeviceId]];
		}
		NSMutableURLRequest *verifyRequest = [NSMutableURLRequest requestWithURL:verifyURL];
		[verifyRequest setHTTPMethod:@"POST"];
		[verifyRequest setValue:kAppleAuthWidgetValue forHTTPHeaderField:kAppleAuthWidgetKey];
		[verifyRequest setValue:appleAuthSessionId forHTTPHeaderField:kAppleAuthSessionIdKey];
		[verifyRequest setValue:appleAuthScnt forHTTPHeaderField:kAppleAuthScntKey];
		[verifyRequest setValue:kAppleAuthContentTypeValue forHTTPHeaderField:kAppleAuthContentTypeKey];
		[verifyRequest setHTTPBody:bodyData];
		NSHTTPURLResponse *verifyResponse = nil;
		[NSURLConnection sendSynchronousRequest:verifyRequest returningResponse:&verifyResponse error:nil];
		
		NSString *setCookie = verifyResponse.allHeaderFields[kAppleAuthSetCookieKey];
		if (([setCookie rangeOfString:@"myacinfo"].location != NSNotFound) || self.isLoggedIn) {
			// We're in!
			[self fetchRemainingCookies];
			if ([self.delegate respondsToSelector:@selector(loginSucceeded)]) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[self.delegate loginSucceeded];
				});
			}
		} else {
			// Incorrect verification code. Retry?
			switch (authType) {
				case SCInputTypeTwoStepVerificationCode: {
					[self performSelectorOnMainThread:@selector(chooseTrustedDevice) withObject:nil waitUntilDone:NO];
					break;
				}
				case SCInputTypeTwoFactorAuthenticationCode: {
					dispatch_async(dispatch_get_main_queue(), ^{
						SecurityCodeInputController *securityCodeInput = [[SecurityCodeInputController alloc] initWithType:SCInputTypeTwoFactorAuthenticationCode];
						securityCodeInput.delegate = self;
						[securityCodeInput show];
					});
					break;
				}
				default: {
					break;
				}
			}
		}
	});
}

- (void)chooseTrustedDevice {
	UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Verify Your Identity", nil)
																			 message:NSLocalizedString(@"Your Apple ID is protected with two-step verification.\nChoose a trusted device to receive a verification code.", nil)
																	  preferredStyle:UIAlertControllerStyleActionSheet];
	
	for (NSDictionary *trustedDevice in trustedDevices) {
		NSNumber *isDevice = trustedDevice[@"device"];
		NSString *deviceName = trustedDevice[@"name"];
		if (isDevice.boolValue) {
			NSString *modelName = trustedDevice[@"modelName"];
			deviceName = [deviceName stringByAppendingFormat:@" (%@)", modelName];
		} else if ([trustedDevice[@"type"] isEqualToString:@"sms"]) {
			deviceName = [NSString stringWithFormat:@"Phone number ending in %@", trustedDevice[@"lastTwoDigits"]];
		}
		NSString *deviceId = trustedDevice[@"id"];
		[alertController addAction:[UIAlertAction actionWithTitle:deviceName style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[self generateCode:deviceId];
		}]];
	}
	
	[alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
		if ([self.delegate respondsToSelector:@selector(loginFailed)]) {
			// User canceled the verification, so we're unable to log in.
			[self.delegate loginFailed];
		}
	}]];
	
	UIViewController *viewController = [UIApplication sharedApplication].keyWindow.rootViewController;
	while (viewController.presentedViewController != nil) {
		viewController = viewController.presentedViewController;
	}
	[viewController presentViewController:alertController animated:YES completion:nil];
}

- (void)securityCodeInputSubmitted:(NSString *)securityCode {
	[self validateCode:securityCode];
}

- (void)securityCodeInputCanceled {
	// User canceled the verification, so we're unable to log in.
	if ([self.delegate respondsToSelector:@selector(loginFailed)]) {
		[self.delegate loginFailed];
	}
}

@end
