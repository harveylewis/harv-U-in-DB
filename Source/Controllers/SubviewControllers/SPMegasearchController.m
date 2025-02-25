//
//  GotoDatbaseController.m
//  sequel-pro
//
//  Created by Max Lohrmann on 12.10.14.
//  Copyright (c) 2014 Max Lohrmann. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPMegasearchController.h"
#include <Foundation/NSObjCRuntime.h>

@interface SPMegasearchController ()

/** Update the list of matched names
 * @param filter     The string to be matched.
 * @param exactMatch Will be set to YES if there is at least one entry in
 *                   unfilteredList that is equivalent to filter. Can be NULL to
 * disable.
 *
 * This method will take every item in the unfilteredList and add matching items
 * to the filteredList, including highlighting.
 * It will neither clear the filteredList first, nor change the isFiltered ivar!
 * Search is case insensitive.
 */
- (void)_buildFilterList:(NSString *)filter
       didFindExactMatch:(BOOL *)exactMatch;

- (IBAction)okClicked:(id)sender;
- (IBAction)cancelClicked:(id)sender;
- (IBAction)searchChanged:(id)sender;
- (IBAction)toggleWordSearch:(id)sender;

- (BOOL)qualifiesForWordSearch; // takes s from searchField
@end

static BOOL StringQualifiesForWordSearch(NSString *s);

#pragma mark -

@interface SPGotoFilteredMegasearchItem : NSObject {
  NSString *string;
  NSArray *matches;
  BOOL isCustomItem;
  BOOL exact;
}
@property(nonatomic, copy) NSString *string;
@property(nonatomic, strong) NSArray *matches;
@property(nonatomic, assign) BOOL isCustomItem;
@property(nonatomic, assign) BOOL exact;

+ (SPGotoFilteredMegasearchItem *)item;
@end

@implementation SPGotoFilteredMegasearchItem

@synthesize string;
@synthesize matches;
@synthesize isCustomItem;
@synthesize exact;

+ (SPGotoFilteredMegasearchItem *)item {
  return [[SPGotoFilteredMegasearchItem alloc] init];
}
@end

#pragma mark -

@implementation SPMegasearchController

@synthesize allowCustomNames;

- (instancetype)init {
  if ((self = [super initWithWindowNibName:@"MegasearchWindow"])) {
    unfilteredList = [[NSMutableArray alloc] init];
    filteredList = [[NSMutableArray alloc] init];
    isFiltered = NO;
    highlightAttrs = @{
      NSBackgroundColorAttributeName :
          [NSColor colorWithCalibratedRed:249 / 255.0
                                    green:247 / 255.0
                                     blue:62 / 255.0
                                    alpha:0.5],
      NSUnderlineColorAttributeName :
          [NSColor colorWithCalibratedRed:246 / 255.0
                                    green:189 / 255.0
                                     blue:85 / 255.0
                                    alpha:1.0],
      NSUnderlineStyleAttributeName :
          [NSNumber numberWithInt:NSUnderlineStyleThick]
    };

    [self setAllowCustomNames:YES];
  }

  return self;
}

- (void)windowDidLoad {
  // Handle a double click in the DB list the same as if OK was clicked.
  [databaseListView setTarget:self];
  [databaseListView setDoubleAction:@selector(okClicked:)];
  [super windowDidLoad];
}

#pragma mark -
#pragma mark IBAction

- (IBAction)okClicked:(id)sender {
  [NSApp stopModalWithCode:YES];

  [[self window] orderOut:nil];
}

- (IBAction)cancelClicked:(id)sender {
  [NSApp stopModalWithCode:NO];

  [[self window] orderOut:nil];
}

- (IBAction)searchChanged:(id)sender {
  [filteredList removeAllObjects];

  NSString *newFilter = [searchField stringValue];

  if (!newFilter || [newFilter isEqualToString:@""]) {
    isFiltered = NO;
  } else {
    isFiltered = YES;

    BOOL exactMatch = NO;

    [self _buildFilterList:newFilter didFindExactMatch:&exactMatch];

    // always add the search string to the end of the list (in case the user
    // wants to switch to a DB not in the list) unless there was an exact match
    if ([self allowCustomNames] && !exactMatch) {
      // remove quotes if any
      if (StringQualifiesForWordSearch(newFilter))
        newFilter = [newFilter
            substringWithRange:NSMakeRange(1, [newFilter length] - 2)];

      if ([newFilter length]) {
        SPGotoFilteredMegasearchItem *customItem =
            [SPGotoFilteredMegasearchItem item];
        [customItem setString:newFilter];
        [customItem setIsCustomItem:YES];

        [filteredList addObject:customItem];
      }
    }
  }

  [databaseListView reloadData];

  // Ensure we have a selection
  if ([databaseListView selectedRow] < 0 &&
      [self numberOfRowsInTableView:databaseListView]) {
    [databaseListView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                  byExtendingSelection:NO];
  }

  [okButton setEnabled:([databaseListView selectedRow] >= 0)];
}

- (IBAction)toggleWordSearch:(id)sender {
  // if the search field is empty just add two " and put the caret in-between
  if (![[searchField stringValue] length]) {
    [searchField setStringValue:@"\"\""];
    [[searchField currentEditor] setSelectedRange:NSMakeRange(1, 0)];

  } else if (![self qualifiesForWordSearch]) {
    [searchField
        setStringValue:[NSString stringWithFormat:@"\"%@\"",
                                                  [searchField stringValue]]];
    // change the selection to be inside the quotes
    [[searchField currentEditor]
        setSelectedRange:NSMakeRange(1,
                                     [[searchField stringValue] length] - 2)];
  } else {
    NSString *str = [searchField stringValue];
    [searchField
        setStringValue:[str substringWithRange:NSMakeRange(1,
                                                           [str length] - 2)]];
  }
  [self searchChanged:nil];
}

#pragma mark -
#pragma mark Public

- (NSString *)selectedDatabase {
  NSInteger row = [databaseListView selectedRow];

  id attrValue;

  if (isFiltered) {
    attrValue = [(SPGotoFilteredMegasearchItem *)[filteredList
        safeObjectAtIndex:row] string];
  } else {
    attrValue = [unfilteredList safeObjectAtIndex:row];
  }
  NSLog(@"in the selected database atrribute here", attrValue);

  return attrValue;
}

- (void)setDatabaseList:(NSArray *)list {
  // Update list of databases
  [unfilteredList removeAllObjects];
  [unfilteredList addObjectsFromArray:list];
}

- (BOOL)runModal {
  // NSWindowController is lazy with loading nibs
  [self window];

  // Reset the search field
  [searchField setStringValue:@""];
  [self searchChanged:nil];

  // Give focus to search field
  [[self window] makeFirstResponder:searchField];

  // Start modal dialog
  return [NSApp runModalForWindow:[self window]];
}

#pragma mark -
#pragma mark Private

- (void)_buildFilterList:(NSString *)filter
       didFindExactMatch:(BOOL *)exactMatch {
  NSStringCompareOptions opts = NSCaseInsensitiveSearch |
                                NSDiacriticInsensitiveSearch |
                                NSWidthInsensitiveSearch;

  BOOL useWordSearch = StringQualifiesForWordSearch(filter);

  // interpret a quoted string as 'looking for exact submachtes only'
  if (useWordSearch) {
    // remove quotes for matching
    filter = [filter substringWithRange:NSMakeRange(1, [filter length] - 2)];

    // look for matches
    for (NSString *db in unfilteredList) {
      NSRange matchRange = [db rangeOfString:filter options:opts];

      if (matchRange.location == NSNotFound)
        continue;

      // Should we check for exact match AND have not yet found one?
      if (exactMatch && !*exactMatch) {
        if (matchRange.location == 0 && matchRange.length == [db length]) {
          *exactMatch = YES;
        }
      }

      SPGotoFilteredMegasearchItem *item = [SPGotoFilteredMegasearchItem item];
      [item setString:db];
      [item setMatches:@[ [NSValue valueWithRange:matchRange] ]];

      [filteredList addObject:item];
    }
  }
  // default to a per-character search
  else {
    for (NSString *db in unfilteredList) {

      NSArray *matches = nil;
      BOOL hasMatch = [db nonConsecutivelySearchString:filter
                                        matchingRanges:&matches];

      if (!hasMatch)
        continue;

      SPGotoFilteredMegasearchItem *item = [SPGotoFilteredMegasearchItem item];

      // Should we check for exact match AND have not yet found one?
      if (exactMatch && !*exactMatch) {
        if ([matches count] == 1) {
          NSRange match = [(NSValue *)[matches objectAtIndex:0] rangeValue];
          NSLog(@"database name %@, match range: %lu, dblength: %lu", db,
                match.length, [db length]);
          // NSLog(@"match range %lu", match.length);
          // NSLog(@"db length %lu", [db length]);

          if (match.location == 0 && match.length == [db length]) {
            *exactMatch = YES;
            [item setExact:YES];

            NSLog(@"FOUND EXACT MATCH HERE");
          }
        }
      }

      [item setString:db];
      [item setMatches:matches];

      [filteredList addObject:item];
    }
  }

  // sort the filtered list
  [filteredList sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
    // word search produces only 1 match, skip.
    if (!useWordSearch) {
      // First we want to sort by number of match groups.
      //   Less match groups -> better result:
      //     Search string: abc
      //     Matches: schema_abc, tablecloth
      //     => First only has 1 match group, is more likely to be the desired
      //     result
      //
      if ([obj1 exact]) {
        return NSOrderedAscending;
      }

      if ([obj2 exact]) {
        return NSOrderedDescending;
      }

      NSUInteger mgc1 = [[(SPGotoFilteredMegasearchItem *)obj1 matches] count];
      NSUInteger mgc2 = [[(SPGotoFilteredMegasearchItem *)obj2 matches] count];
      if (mgc1 < mgc2)
        return NSOrderedAscending;
      if (mgc2 < mgc1)
        return NSOrderedDescending;
    }
    // For strings with the same number of match groups we just sort
    // alphabetically
    return [[(SPGotoFilteredMegasearchItem *)obj1 string]
        compare:[(SPGotoFilteredMegasearchItem *)obj2 string]];
  }];
}

- (BOOL)qualifiesForWordSearch {
  return StringQualifiesForWordSearch([searchField stringValue]);
}

#pragma mark -
#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
  if (!isFiltered) {
    return [unfilteredList count];
  } else {
    return [filteredList count];
  }
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
                          row:(NSInteger)rowIndex {
  if (!isFiltered) {
    return [unfilteredList objectAtIndex:rowIndex];
  } else {
    return [(SPGotoFilteredMegasearchItem *)[filteredList
        objectAtIndex:rowIndex] string];
  }
}

#pragma mark -
#pragma mark NSTableViewDelegate

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
                row:(NSInteger)row {
  // nothing to do here, unless the list is filtered
  if (!isFiltered)
    return;

  // The styling of source list table views is basically done by Apple by
  // replacing the cell's string with an attributedstring. But if the data
  // source were to already return an attributedstring, most of the other
  // attributes Apple sets would not get applied. So we have to add our
  // attributes after Apple has already modified the string returned by the data
  // source.

  id cellValue = [cell objectValue];
  // turn the cell value into something we can work with
  NSMutableAttributedString *attrString;
  if ([cellValue isKindOfClass:[NSMutableAttributedString class]]) {
    attrString = cellValue;
  } else if ([cellValue isKindOfClass:[NSAttributedString class]]) {
    attrString =
        [[NSMutableAttributedString alloc] initWithAttributedString:cellValue];
  } else if ([cellValue isKindOfClass:[NSString class]]) {
    attrString = [[NSMutableAttributedString alloc] initWithString:cellValue];
  } else {
    SPLog(@"Unknown object for cellValue (type=%@)", [cellValue className]);
    return;
  }

  SPGotoFilteredMegasearchItem *item = [filteredList objectAtIndex:row];

  if ([item isCustomItem]) {
    [[attrString mutableString] appendString:@"⁈"];
    [attrString addAttribute:NSUnderlineStyleAttributeName
                       value:@(NSUnderlineStyleSingle)
                       range:NSMakeRange([attrString length] - 1, 1)];
  } else {
    for (NSValue *matchValue in [item matches]) {
      [attrString addAttributes:highlightAttrs range:[matchValue rangeValue]];
    }
  }

  [cell setObjectValue:attrString];
}

#pragma mark -
#pragma mark NSControlTextEditingDelegate

- (BOOL)control:(NSControl *)control
               textView:(NSTextView *)fieldEditor
    doCommandBySelector:(SEL)commandSelector {
  // The ESC key will usually clear the search field. we want to close the
  // dialog
  if (commandSelector == @selector(cancelOperation:)) {
    [cancelButton performClick:control];
    return YES;
  }

  // the keyboard event is the preferable choice as it will also scroll the
  // window
  // TODO: check if the other path is ever used
  NSEvent *currentEvent = [NSApp currentEvent];
  BOOL isKeyDownEvent = ([currentEvent type] == NSEventTypeKeyDown);

  // Arrow down/up will usually go to start/end of the text field. we want to
  // change the selected table row.
  if (commandSelector == @selector(moveDown:)) {
    if (isKeyDownEvent) {
      [databaseListView keyDown:currentEvent];
    } else {
      [databaseListView
              selectRowIndexes:[NSIndexSet indexSetWithIndex:([databaseListView
                                                                  selectedRow] +
                                                              1)]
          byExtendingSelection:NO];
    }
    return YES;
  }

  if (commandSelector == @selector(moveUp:)) {
    if (isKeyDownEvent) {
      [databaseListView keyDown:currentEvent];
    } else {
      [databaseListView
              selectRowIndexes:[NSIndexSet indexSetWithIndex:([databaseListView
                                                                  selectedRow] -
                                                              1)]
          byExtendingSelection:NO];
    }
    return YES;
  }

  // Forward return to OK button (enter will not be caught by search field)
  if (commandSelector == @selector(insertNewline:)) {
    [okButton performClick:control];
    return YES;
  }

  return NO;
}

#pragma mark -
#pragma mark NSUserInterfaceValidations

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem {
  if ([anItem action] == @selector(toggleWordSearch:)) {
    [(NSMenuItem *)anItem
        setState:([self qualifiesForWordSearch] ? NSControlStateValueOn
                                                : NSControlStateValueOff)];
  }
  return YES;
}

@end

#pragma mark -

BOOL StringQualifiesForWordSearch(NSString *s) {
  return (s && ([s length] > 1) &&
          (([s hasPrefix:@"\""] && [s hasSuffix:@"\""]) ||
           ([s hasPrefix:@"'"] && [s hasSuffix:@"'"])));
}
