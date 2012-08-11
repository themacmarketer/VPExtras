//
//  VPBlogPlugin.m
//  VPBlog
//
//  Created by August Mueller on 4/2/12.
//  Copyright (c) 2012 Flying Meat. All rights reserved.
//

#import "VPBlogPlugin.h"
#import "VPBPaletteController.h"
#import "JSTalk.h"
#import "VPPrivateStuff.h"

@interface NSObject (VPPluginManagerCurrentlyPrivate)

- (void)registerPaletteViewController:(Class)pvc;

@end

@implementation VPBlogPlugin

- (void)dealloc {
    
    for (id observer in _observers) {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }
    
    [super dealloc];
}

- (void)didRegister {
    [(id)[self pluginManager] registerPaletteViewController:[VPBPaletteController class]];
    
    
    _observers = [NSMutableArray array];
    [self setupPreviewListener];
    
}

+ (id <VPPluginDocument>)currentDocument {
    id <VPPluginDocument>doc = [[NSDocumentController sharedDocumentController] currentDocument];
    
    if (!doc && [[[NSDocumentController sharedDocumentController] documents] count]) {
        // wtf, appkit is holding out on us.
        doc = [[[NSDocumentController sharedDocumentController] documents] objectAtIndex:0];
        
        // sanity check.
        if (![(id)doc respondsToSelector:@selector(orderedPageKeysByCreateDate)]) {
            doc = nil;
        }
    }
    
    return doc;
    
}


- (void)setupPreviewListener {
    
    
    // Yes, another bit of private VP stuff leaking out.
    // we want to be able to have the setup dictionary around for previews, and this will allow us to push it on there
    // if it isn't already around.
    id ob = [[NSNotificationCenter defaultCenter] addObserverForName:@"VPHTMLPreviewWillRenderPageWithJSTalk" object:0x00 queue:0x00 usingBlock:^(NSNotification *note) {
        
        JSTalk *jstalk = [note object];
        
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        
        [jstalk pushObject:d withName:@"staticSetup"];
        
        id <VPData>scriptPage = [[VPBlogPlugin currentDocument] pageForKey:"@vpstaticexportscript"];
        
        if (scriptPage) {
            [jstalk executeString:[scriptPage stringData]];
        }
        
        if ([jstalk hasFunctionNamed:@"staticSetupConfiguration"]) {
            [jstalk callFunctionNamed:@"staticSetupConfiguration" withArguments:[NSArray arrayWithObjects:[VPBlogPlugin currentDocument], d, nil]];
        }
    }];
    
    [_observers addObject:ob];
    
}




@end
