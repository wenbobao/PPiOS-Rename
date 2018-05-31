// -*- mode: ObjC -*-

/*************************************************
  Copyright 2016-2017 PreEmptive Solutions, LLC
  See LICENSE.txt for licensing information
*************************************************/
  
//  This file is part of class-dump, a utility for examining the Objective-C segment of Mach-O files.
//  Copyright (C) 1997-1998, 2000-2001, 2004-2015 Steve Nygard.

#import "CDFile.h" // For CDArch

#define NOT_MACHO_OR_FAT_MESSAGE "Input file (%s) is neither a Mach-O file nor a fat archive."
#define STATIC_LIBRARY_MESSAGE "If you are trying to obfuscate a static library, please review the " \
    "'Obfuscating Static Libraries' section of the documentation."

@class CDFile;
@class CDTypeController;
@class CDVisitor;
@class CDSearchPathState;

@interface CDClassDump : NSObject

@property (readonly) CDSearchPathState *searchPathState;
@property (copy, nonatomic) NSArray *forceRecursiveAnalyze;

@property (strong) NSString *sdkRoot;
@property (strong) NSString *headersRoot;

@property (readonly) NSArray *machOFiles;
@property (readonly) NSArray *objcProcessors;

@property (assign) CDArch targetArch;

@property (nonatomic, readonly) BOOL containsObjectiveCData;
@property (nonatomic, readonly) BOOL hasEncryptedFiles;
@property (nonatomic, readonly) BOOL hasObjectiveCRuntimeInfo;

@property (readonly) CDTypeController *typeController;

- (BOOL)loadFile:(CDFile *)file error:(NSError **)error depth:(int)depth;
- (void)processObjectiveCData;

- (void)recursivelyVisit:(CDVisitor *)visitor;

- (void)appendHeaderToString:(NSMutableString *)resultString;

- (void)registerTypes;

- (void)showHeader;
- (void)showLoadCommands;

- (int)obfuscateSourcesUsingMap:(NSString *)symbolsPath
              symbolsHeaderFile:(NSString *)symbolsHeaderFile
               workingDirectory:(NSString *)workingDirectory
                   xibDirectory:(NSString *)xibDirectory;

@end

extern NSString *CDErrorDomain_ClassDump;
extern NSString *CDErrorKey_Exception;


