#import "ViWordCompletion.h"
#include "logging.h"

@implementation ViWordCompletion

- (ViWordCompletion *)initWithTextStorage:(ViTextStorage *)aTextStorage
			       atLocation:(NSUInteger)aLocation
{
	if ((self = [super init]) != nil) {
		textStorage = aTextStorage;
		currentLocation = aLocation;
	}
	return self;
}

- (id<ViDeferred>)completionsForString:(NSString *)word
			       options:(NSString *)options
			    onResponse:(void (^)(NSArray *, NSError *))responseCallback
{
	BOOL fuzzySearch = ([options rangeOfString:@"f"].location != NSNotFound);
	BOOL fuzzyTrigger = ([options rangeOfString:@"F"].location != NSNotFound);
	NSString *pattern;
	if (word == nil) {
		pattern = @"\\b\\w{3,}";
	} else if (fuzzyTrigger) { /* Fuzzy completion trigger. */
		pattern = [NSMutableString string];
		[(NSMutableString *)pattern appendString:@"\\b\\w*"];
		[ViCompletionController appendFilter:word
					   toPattern:(NSMutableString *)pattern
					  fuzzyClass:@"\\w"];
		[(NSMutableString *)pattern appendString:@"\\w*"];
	} else {
		pattern = [NSString stringWithFormat:@"\\b(%@)\\w*", word];
	}

	DEBUG(@"searching for %@", pattern);

	unsigned rx_options = ONIG_OPTION_NOTBOL | ONIG_OPTION_NOTEOL | ONIG_OPTION_IGNORECASE;
	ViRegexp *rx;
	rx = [[ViRegexp alloc] initWithString:pattern
				      options:rx_options];
	NSArray *foundMatches = [rx allMatchesInString:[textStorage string]
					       options:rx_options];

	NSMutableSet *uniq = [NSMutableSet set];
	for (ViRegexpMatch *m in foundMatches) {
		NSRange r = [m rangeOfMatchedString];
		if (r.location == NSNotFound || r.location == currentLocation)
			/* Don't include the word we're about to complete. */
			continue;
		NSString *content = [[textStorage string] substringWithRange:r];
		ViCompletion *c;
		if (fuzzySearch) {
			c = [ViCompletion completionWithContent:content fuzzyMatch:m];
			if (!fuzzyTrigger)
				c.prefixLength = [word length];
		} else
			c = [ViCompletion completionWithContent:content prefixLength:[word length]];
		c.location = r.location;
		[uniq addObject:c];
	}

	BOOL sortDescending = ([options rangeOfString:@"d"].location != NSNotFound);
	NSComparator sortByLocation = ^(id a, id b) {
		ViCompletion *ca = a, *cb = b;
		NSUInteger al = ca.location;
		NSUInteger bl = cb.location;
		if (al > bl) {
			if (bl < currentLocation && al > currentLocation)
				return (NSComparisonResult)(sortDescending ? NSOrderedDescending : NSOrderedAscending); // a < b
			return (NSComparisonResult)(sortDescending ? NSOrderedAscending : NSOrderedDescending); // a > b
		} else if (al < bl) {
			if (al < currentLocation && bl > currentLocation)
				return (NSComparisonResult)(sortDescending ? NSOrderedAscending : NSOrderedDescending); // a > b
			return (NSComparisonResult)(sortDescending ? NSOrderedDescending : NSOrderedAscending); // a < b
		}
		return (NSComparisonResult)NSOrderedSame;
	};
	NSArray *completions = [[uniq allObjects] sortedArrayUsingComparator:sortByLocation];

	responseCallback(completions, nil);
	return nil;
}

@end
