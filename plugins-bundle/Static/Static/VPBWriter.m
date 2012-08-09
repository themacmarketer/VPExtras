//
//  VPBWriter.m
//  VPBlog
//
//  Created by August Mueller on 4/5/12.
//  Copyright (c) 2012 Flying Meat. All rights reserved.
//

#import "VPBWriter.h"
#import "VPPrivateStuff.h"


@interface VPBWriter ()
@property (strong) NSMutableString *rssFeed;
@property (strong) NSMutableString *indexPage;
@property (strong) NSMutableDictionary *vpbSetup;
@property (strong) NSString *currentArchiveMonth;
@end

@implementation VPBWriter

@synthesize rssFeed=_rssFeed;
@synthesize indexPage=_indexPage;
@synthesize vpbSetup=_vpbSetup;
@synthesize currentArchiveMonth=_currentArchiveMonth;

- (id)init
{
    self = [super init];
    if (self) {
        [self setRssFeed:[NSMutableString string]];
        [self setIndexPage:[NSMutableString string]];
        [self setVpbSetup:[NSMutableDictionary dictionary]];
        
        [_vpbSetup setObject:@"" forKey:@"siteName"];
        [_vpbSetup setObject:@"" forKey:@"copyright"];
        [_vpbSetup setObject:@"10" forKey:@"frontPageCount"];
        [_vpbSetup setObject:@"siteURL" forKey:@"http://example.com/wherever/"];
        
    }
    return self;
}

- (void)dealloc {
    [_rssFeed release];
    [_indexPage release];
    [_vpbSetup release];
    [_currentArchiveMonth release];
    
    [super dealloc];
}



- (NSString*)escapeArchivePageName:(NSString*)name {
    
    NSArray *replaceChars = [NSArray arrayWithObjects:@" ", @"/", @"\\", @"\"", @",", @"'", @"?", @"[", @"]", @"&", @"%", nil];
    
    for (NSString *r in replaceChars) {
        name = [name stringByReplacingOccurrencesOfString:r withString:@"_"];
    }
    
    return name;
}


- (NSString*)askForArchivePathForItem:(id<VPData>)item fileName:(NSString*)fn document:(id<VPPluginDocument>)doc baseOutputURL:(NSURL*)baseOutputURL context:(NSMutableDictionary*)exportContext jstalk:(JSTalk*)jstalk {
    
    
    if ([jstalk hasFunctionNamed:@"blogExportArchivePathForItem"]) {
        
        NSString *newPath = [jstalk callFunctionNamed:@"blogExportArchivePathForItem" withArguments:[NSArray arrayWithObjects:doc, item, fn, exportContext, nil]];
        
        if (newPath) {
            
            NSURL *parentDir = [baseOutputURL URLByAppendingPathComponent:[newPath stringByDeletingLastPathComponent]];
            
            NSError *err = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtURL:parentDir withIntermediateDirectories:YES attributes:nil error:&err]) {
                NSBeep();
                NSLog(@"Could not make the directory %@", parentDir);
                NSLog(@"%@", err);
                return fn;
            }
            
            return newPath;
        }
    }
    
    return fn;
    
}

- (void)appendItem:(id<VPData>)item toArchiveString:(NSMutableString*)archive usingRelativePath:(NSString*)outRelativePath {
    
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat:@"MMMM yyyy"];
    
    NSString *thisGuysMonth = [formatter stringFromDate:[item createdDate]]; 
    
    if (![thisGuysMonth isEqualToString:_currentArchiveMonth]) {
    
        if (_currentArchiveMonth) {
            [archive appendString:@"</div>\n"];
        }
    
        [self setCurrentArchiveMonth:thisGuysMonth];
        [archive appendFormat:@"<div class=\"archiveMonthEntry\"><p class=\"archiveMonthHeader\">%@</p>\n", _currentArchiveMonth];
    }
    
    [archive appendFormat:@"<p class=\"archiveEntry\"><a href=\"%@\">%@</a></p>\n", outRelativePath, [self escapeForXML:[item displayName]]];
}

- (void)exportAndLimitToCount:(NSInteger)postCount {
    
    id <VPPluginDocument>doc = [[NSDocumentController sharedDocumentController] currentDocument];
    
    if (!doc) {
        return;
    }
    
    NSString *outputPath = [doc extraObjectForKey:@"vpblog.outputPath"];
    if (!outputPath) {
        NSLog(@"No output folder set, or it doesn't exist");
        
        NSAlert *alert = [NSAlert alertWithMessageText:@"No publish folder set" defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"Make sure to select a folder to publish to."];
        
        [alert runModal];
        
        return;
    }
    
    NSURL *baseOutputURL = [NSURL fileURLWithPath:outputPath];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
        NSError *err = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:baseOutputURL withIntermediateDirectories:YES attributes:nil error:&err]) {
            NSBeep();
            NSLog(@"Could not make the directory %@", outputPath);
            NSLog(@"%@", err);
            return;
        }
    }
    
    JSTalk *jstalk = [(id)doc jstalk];
    NSMutableDictionary *exportContext = [NSMutableDictionary dictionary];
    
    [jstalk pushObject:_vpbSetup withName:@"vpbSetup"];
    
    id <VPData>scriptPage = [doc pageForKey:@"vpblogexportscript"];
    
    if (scriptPage) {
        [jstalk executeString:[scriptPage stringData]];
    }
    
    if ([jstalk hasFunctionNamed:@"blogSetupConfiguration"]) {
        [jstalk callFunctionNamed:@"blogSetupConfiguration" withArguments:[NSArray arrayWithObjects:doc, _vpbSetup, nil]];
    }
    
    if ([jstalk hasFunctionNamed:@"blogExportWillBegin"]) {
        [jstalk callFunctionNamed:@"blogExportWillBegin" withArguments:[NSArray arrayWithObjects:doc, exportContext, nil]];
    }
    
    NSString *entryPageTemplate = [[doc pageForKey:@"VPBlogPageEntryTemplate"] stringData];
    if (!entryPageTemplate) {
        entryPageTemplate = @"<%= pageContext.pageEntry %>";
    }
    
    
    NSString *rssEntryTemplate = [[doc pageForKey:@"VPBlogRSSEntryTemplate"] stringData];
    if (!rssEntryTemplate) {
        rssEntryTemplate = @"<%= pageContext.pageEntry %>";
    }
    
    NSString *pageTemplate = [[doc pageForKey:@"VPWebExportPageTemplate"] stringData];
    if (!pageTemplate) {
        pageTemplate = @"$page$";
    }
    
    [self makeRSSHeader];
    
    NSInteger currentPageCount = 0;
    NSInteger maxPageCount     = [[_vpbSetup objectForKey:@"frontPageCount"] integerValue];
    
    
    NSMutableString *archivePage = [NSMutableString string];
    
    
    id webExportController = [(id)doc webExportController];
    NSArray *orderedByDate = [doc orderedPageKeysByCreateDate];
    
    for (NSString *key in [orderedByDate reverseObjectEnumerator]) {
        
        @autoreleasepool {
            
            id <VPData>item = [doc pageForKey:key];
            
            if (![item isText]) {
                continue;
            }
            
            BOOL shouldPublish = [[item metaValueForKey:@"vpblog.publish"] boolValue];
            if (!shouldPublish) {
                continue;
            }
            
            
            
            // let's find out where they want us to write the file:
            
            NSString *archiveFileName = [self escapeArchivePageName:[[item key] stringByAppendingPathExtension:@"html"]];
            NSString *outRelativePath = [self askForArchivePathForItem:item fileName:archiveFileName document:doc baseOutputURL:baseOutputURL context:exportContext jstalk:jstalk];
            NSURL *outURL             = [baseOutputURL URLByAppendingPathComponent:outRelativePath];
            
            [self appendItem:item toArchiveString:archivePage usingRelativePath:outRelativePath];
            
            
            if (currentPageCount >= maxPageCount) {
                continue;
            }
            
            currentPageCount++;
            
            
            
            NSDictionary *renderOptions = [NSDictionary dictionaryWithObjectsAndKeys:jstalk, @"jstalk", [NSNumber numberWithBool:YES], @"ignoreTemplateWrapping", nil];
            
            NSDictionary *d = [webExportController renderItem:item options:renderOptions];
            NSString *unwrappedOutput = [d objectForKey:@"output"];
            
            if ([jstalk hasFunctionNamed:@"blogExportWillAppendItemToFrontPage"]) {
                [jstalk callFunctionNamed:@"blogExportWillAppendItemToFrontPage" withArguments:[NSArray arrayWithObjects:doc, item, _indexPage, exportContext, nil]];
            }
            
            [exportContext setObject:outRelativePath forKey:@"pageArchivePath"];
            [exportContext setObject:unwrappedOutput forKey:@"pageEntry"];
            
            NSDictionary *args  = [NSDictionary dictionaryWithObjectsAndKeys:doc, @"document", item, @"page", exportContext, @"pageContext", _vpbSetup, @"vpbSetup", nil];
            NSString *entry     = [(id)doc renderScriptletsInHTMLString:entryPageTemplate withJSTalk:jstalk usingVariables:args];
            NSString *rssentry  = [(id)doc renderScriptletsInHTMLString:rssEntryTemplate withJSTalk:jstalk usingVariables:args];
            
            NSString *archivePage = [pageTemplate stringByReplacingOccurrencesOfString:@"$page$" withString:entry];
            archivePage           = [(id)doc renderScriptletsInHTMLString:archivePage withJSTalk:jstalk usingVariables:args];
            
            
            [_indexPage appendString:entry];
            
            //debug(@"entry: %@", entry);
            [self appendRSSEntry:rssentry archiveURL:outRelativePath toItem:item];
            
            if ([jstalk hasFunctionNamed:@"blogExportDidAppendItemToFrontPage"]) {
                [jstalk callFunctionNamed:@"blogExportDidAppendItemToFrontPage" withArguments:[NSArray arrayWithObjects:doc, item, _indexPage, exportContext, nil]];
            }
            
            NSData *data = [archivePage dataUsingEncoding:NSUTF8StringEncoding];
            
            NSError *writeError = nil;
            if (![data writeToURL:outURL options:NSDataWritingAtomic error:&writeError]) {
                NSLog(@"Could not write to %@", outURL);
                NSLog(@"%@", writeError);
            }
        }
    }
    
    [self appendRSSFooter];
    
    NSURL *rssOutURL    = [baseOutputURL URLByAppendingPathComponent:@"rss.xml"];
    NSError *writeError = nil;
    
    if (![[_rssFeed dataUsingEncoding:NSUTF8StringEncoding] writeToURL:rssOutURL options:NSDataWritingAtomic error:&writeError]) {
        NSLog(@"Could not write to %@", rssOutURL);
        NSLog(@"%@", writeError);
    }
    
    [jstalk deleteObjectWithName:@"page"];
    
    // write the index page!
    {
        NSString *rIndexPage   = [pageTemplate stringByReplacingOccurrencesOfString:@"$page$" withString:_indexPage];
        NSDictionary *args  = [NSDictionary dictionaryWithObjectsAndKeys:doc, @"document", exportContext, @"pageContext", _vpbSetup, @"vpbSetup", nil];
        rIndexPage = [(id)doc renderScriptletsInHTMLString:rIndexPage withJSTalk:jstalk usingVariables:args];
        
        NSData *indexPageData = [rIndexPage dataUsingEncoding:NSUTF8StringEncoding];
        NSURL *outURL         = [baseOutputURL URLByAppendingPathComponent:@"index.html"];
        
        if (![indexPageData writeToURL:outURL options:NSDataWritingAtomic error:&writeError]) {
            NSLog(@"Could not write to %@", outURL);
            NSLog(@"%@", writeError);
        }
    }
    
    
    
    // write the archive page!
    {
        // close the opening div we've got going on.
        [archivePage appendString:@"</div>\n"];
        
        NSString *rArchivePage   = [pageTemplate stringByReplacingOccurrencesOfString:@"$page$" withString:archivePage];
        NSDictionary *args  = [NSDictionary dictionaryWithObjectsAndKeys:doc, @"document", exportContext, @"pageContext", _vpbSetup, @"vpbSetup", nil];
        rArchivePage = [(id)doc renderScriptletsInHTMLString:rArchivePage withJSTalk:jstalk usingVariables:args];

        NSData *archivePageData = [rArchivePage dataUsingEncoding:NSUTF8StringEncoding];
        NSURL *archiveOutURL    = [baseOutputURL URLByAppendingPathComponent:@"archive.html"];
        
        if (![archivePageData writeToURL:archiveOutURL options:NSDataWritingAtomic error:&writeError]) {
            NSLog(@"Could not write to %@", archiveOutURL);
            NSLog(@"%@", writeError);
        }
    }
    
    
    
    
    
    
    if ([jstalk hasFunctionNamed:@"blogExportDidEnd"]) {
        [jstalk callFunctionNamed:@"blogExportDidEnd" withArguments:[NSArray arrayWithObjects:doc, exportContext, nil]];
    }
    
    if ([[_vpbSetup objectForKey:@"viewLocalWhenFinished"] boolValue]) {
        [[NSWorkspace sharedWorkspace] openURL:[baseOutputURL URLByAppendingPathComponent:@"index.html"]];
    }
    
}

- (NSString*)rssDateFromNSDate:(NSDate*)date {
    
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss Z"];
    
    return [formatter stringFromDate:date];
}

- (NSString*)escapeForXML:(NSString*)s {
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    
    return s;
}

- (void)makeRSSHeader {
    
    NSString *siteName = [self escapeForXML:[_vpbSetup objectForKey:@"siteName"]];
    NSString *siteURL  = [self escapeForXML:[_vpbSetup objectForKey:@"siteURL"]];
    NSString *siteDesc = [self escapeForXML:[_vpbSetup objectForKey:@"rssSiteDescription"]];
    NSString *pubDate  = [self rssDateFromNSDate:[NSDate date]];
    
    
    [_rssFeed appendFormat:@""
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<rss version=\"2.0\"\n"
            "  xmlns:content=\"http://purl.org/rss/1.0/modules/content/\"\n"
            "  xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
            "  <channel>\n"
            "    <title>%@</title>\n"
            "    <link>%@</link>\n"
            "    <pubDate>%@</pubDate>\n"
            "    <description>%@</description>\n", siteName, siteURL, pubDate, siteDesc];
}

- (void)appendRSSEntry:(NSString*)entry archiveURL:(NSString*)archiveURL toItem:(id<VPData>)item {
    
    NSString *title = [self escapeForXML:[item displayName]];
    NSString *siteURL  = [self escapeForXML:[_vpbSetup objectForKey:@"siteURL"]];
    NSString *link = [siteURL stringByAppendingString:archiveURL];
    
    NSString *pubDate = [self rssDateFromNSDate:[item createdDate]];
    
    entry = [self escapeForXML:entry];
    
    [_rssFeed appendFormat:@""
     "  <item>\n"
     "    <title>%@</title>\n"
     "    <link>%@</link>\n" 
     "    <description>%@</description>\n"
     "    <guid>%@</guid>\n"
     "    <pubDate>%@</pubDate>\n"
     "  </item>\n", title, link, entry, link, pubDate];
}

- (void)appendRSSFooter {
    [_rssFeed appendString:@"  </channel>\n</rss>"];
}


@end
