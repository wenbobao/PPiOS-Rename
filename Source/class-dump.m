// -*- mode: ObjC -*-

//  This file is part of class-dump, a utility for examining the Objective-C segment of Mach-O files.
//  Copyright (C) 1997-1998, 2000-2001, 2004-2015 Steve Nygard.

#include <getopt.h>

#import "CDClassDump.h"
#import "CDFindMethodVisitor.h"
#import "CDClassDumpVisitor.h"
#import "CDMultiFileVisitor.h"
#import "CDMachOFile.h"
#import "CDFatFile.h"
#import "CDFatArch.h"
#import "CDSearchPathState.h"
#import "CDSymbolsGeneratorVisitor.h"
#import "CDXibStoryBoardProcessor.h"
#import "CDCoreDataModelProcessor.h"
#import "CDSymbolMapper.h"
#import "CDSystemProtocolsProcessor.h"
#import "CDdSYMProcessor.h"

NSString *defaultSymbolMappingPath = @"symbols.json";

void print_usage(void)
{
    fprintf(stderr,
            "PreEmptive Protection for iOS - Class Guard, version %s\n"
            "\n"
            "Usage:\n"
            "ios-class-guard --analyze [options] \n"
            "  ( --sdk-root <path> | ( --sdk-ios | --sdk-mac ) <version> ) <mach-o-file>\n"
            "ios-class-guard --obfuscate-sources [options]\n"
            "ios-class-guard --list-arches <mach-o-file>\n"
            "ios-class-guard --version\n"
            "ios-class-guard --translate-crashdump [options] -c <crash dump file>\n"
            "ios-class-guard --translate-dsym [options] --dsym-in <input file> --dsym-out <output file>\n"
            "\n"
            "Modes of operation:\n"
            "  --analyze             Analyze a Mach-O binary and generate a symbol map\n"
            "  --obfuscate-sources   Alter source code (relative to current working\n"
            "                        directory), renaming based on the symbol map\n"
            "  --list-arches         List architectures available in a fat binary\n"
            "  --version             Print out the version information of ios-class-guard\n"
            "  --translate-crash-dump\n"
            "                        Translate symbolicated crash dump\n"
            "  --translate-dsym      Translates a dsym file with obfuscated symbols to a\n"
            "                        dsym with unobfuscated names\n"
            "\n"
            "Common options:\n"
            "  -m <path>             Path to symbol map file (default: symbols.json)\n"
            "                        This option is required for analysis, obfuscation,\n"
            "                        and translation of symbols\n"
            "\n"
            "Analyze mode options:\n"
            "  -F <name>             Specify filter for a class or protocol pattern\n"
            "  -i <symbol>           Ignore obfuscation of specific symbol\n"
            "  --arch <arch>         Choose specific architecture from universal binary:\n"
            "                        ppc|ppc64|i386|x86_64|armv6|armv7|armv7s|arm64\n"
            "  --sdk-root            Specify full SDK root path (or one of the shortcuts)\n"
            "  --sdk-ios             Specify iOS SDK by version, searching for:\n"
            "                        /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS<version>.sdk\n"
            "                        and /Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS<version>.sdk\n"
            "  --sdk-mac             Specify Mac OS X SDK by version, searching:\n"
            "                        /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX<version>.sdk\n"
            "                        and /Developer/SDKs/MacOSX<version>.sdk\n"
            "\n"
            "Obfuscate sources mode options:\n"
            "  -X <directory>        Path for XIBs and storyboards (searched recursively)\n"
            "  -O <path>             Path of where to write obfuscated symbols header\n"
            "                        (default: symbols.h)\n"
            "\n"
            "Other options:\n"
            "  -c <path>             Path to symbolicated crash dump\n"
            "  --dsym-in <path>         Path to dSym file to translate\n"
            "  --dsym-out <path>     Path to dSym file to translate\n"
            "\n"
            ,
            CLASS_DUMP_VERSION
    );
}

#define CD_OPT_ARCH        1
#define CD_OPT_LIST_ARCHES 2
#define CD_OPT_VERSION     3
#define CD_OPT_SDK_IOS     4
#define CD_OPT_SDK_MAC     5
#define CD_OPT_SDK_ROOT    6
#define CD_OPT_HIDE        7
#define CD_OPT_DSYM_IN     8
#define CD_OPT_DSYM_OUT    9
#define CD_OPT_TRANSLATE_CRASH 10
#define CD_OPT_TRANSLATE_DSYM 11

#define PPIOS_CG_OPT_ANALYZE ((int)'z')
#define PPIOS_CG_OPT_OBFUSCATE ((int)'y')


int main(int argc, char *argv[])
{
    @autoreleasepool {
        BOOL shouldListArches = NO;
        BOOL shouldPrintVersion = NO;
        CDArch targetArch;
        BOOL hasSpecifiedArch = NO;
        NSMutableSet *hiddenSections = [NSMutableSet set];
        NSMutableArray *classFilter = [NSMutableArray new];
        NSMutableArray *ignoreSymbols = [NSMutableArray new];
        NSString *xibBaseDirectory = nil;
        NSString *symbolsPath = nil;
        NSString *symbolMappingPath = nil;
        NSString *crashDumpPath = nil;
        NSString *dSYMInPath = nil;
        NSString *dSYMOutPath = nil;

        int ch;
        BOOL errorFlag = NO;

        struct option longopts[] = {
                { "filter-class",            no_argument,       NULL, 'F' },
                { "ignore-symbols",          required_argument, NULL, 'i' },
                { "xib-directory",           required_argument, NULL, 'X' },
                { "symbols-file",            required_argument, NULL, 'O' },
                { "symbols-map",             required_argument, NULL, 'm' },
                { "crash-dump",              required_argument, NULL, 'c' },
                { "dsym",                    required_argument, NULL, CD_OPT_DSYM_IN },
                { "dsym-out",                required_argument, NULL, CD_OPT_DSYM_OUT },
                { "arch",                    required_argument, NULL, CD_OPT_ARCH }, //needed?
                { "list-arches",             no_argument,       NULL, CD_OPT_LIST_ARCHES },
                { "suppress-header",         no_argument,       NULL, 't' },
                { "version",                 no_argument,       NULL, CD_OPT_VERSION },
                { "sdk-ios",                 required_argument, NULL, CD_OPT_SDK_IOS },
                { "sdk-mac",                 required_argument, NULL, CD_OPT_SDK_MAC },
                { "sdk-root",                required_argument, NULL, CD_OPT_SDK_ROOT },
                { "hide",                    required_argument, NULL, CD_OPT_HIDE },
                { "analyze",                 no_argument,       NULL, PPIOS_CG_OPT_ANALYZE }, //'z'
                { "obfuscate-sources",       no_argument,       NULL, PPIOS_CG_OPT_OBFUSCATE }, //'y'
                { "translate-crashdump",     no_argument,       NULL, CD_OPT_TRANSLATE_CRASH},
                { "translate-dsym",          no_argument,       NULL, CD_OPT_TRANSLATE_DSYM},
                { NULL,                      0,                 NULL, 0 },
        };

        if (argc == 1) {
            print_usage();
            exit(0);
        }

        CDClassDump *classDump = [[CDClassDump alloc] init];

        while ( (ch = getopt_long(argc, argv, "Fi:tX:zy:O:m:c:", longopts, NULL)) != -1) {
            switch (ch) {
                case CD_OPT_ARCH: {
                    NSString *name = [NSString stringWithUTF8String:optarg];
                    targetArch = CDArchFromName(name);
                    if (targetArch.cputype != CPU_TYPE_ANY)
                        hasSpecifiedArch = YES;
                    else {
                        fprintf(stderr, "Error: Unknown arch %s\n\n", optarg);
                        errorFlag = YES;
                    }
                    break;
                }

                case CD_OPT_SDK_IOS: {
                    NSString *root = [NSString stringWithUTF8String:optarg];
                    NSString *str;
                    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/Xcode.app"]) {
                        str = [NSString stringWithFormat:@"/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS%@.sdk", root];
                    } else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Developer"]) {
                        str = [NSString stringWithFormat:@"/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS%@.sdk", root];
                    }
                    classDump.sdkRoot = str;

                    break;
                }

                case CD_OPT_SDK_MAC: {
                    NSString *root = [NSString stringWithUTF8String:optarg];
                    NSString *str;
                    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/Xcode.app"]) {
                        str = [NSString stringWithFormat:@"/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX%@.sdk", root];
                    } else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Developer"]) {
                        str = [NSString stringWithFormat:@"/Developer/SDKs/MacOSX%@.sdk", root];
                    }
                    classDump.sdkRoot = str;

                    break;
                }

                case CD_OPT_SDK_ROOT: {
                    NSString *root = [NSString stringWithUTF8String:optarg];
                    classDump.sdkRoot = root;

                    break;
                }

                case CD_OPT_HIDE: {
                    NSString *str = [NSString stringWithUTF8String:optarg];
                    if ([str isEqualToString:@"all"]) {
                        [hiddenSections addObject:@"structures"];
                        [hiddenSections addObject:@"protocols"];
                    } else {
                        [hiddenSections addObject:str];
                    }
                    break;
                }

                case CD_OPT_DSYM_IN: {
                    dSYMInPath = [NSString stringWithUTF8String:optarg];
                    break;
                }

                case CD_OPT_DSYM_OUT: {
                    dSYMOutPath = [NSString stringWithUTF8String:optarg];
                    break;
                }

                case 'F':
                    [classFilter addObject:[NSString stringWithUTF8String:optarg]];
                    break;

                case 'X':
                    xibBaseDirectory = [NSString stringWithUTF8String:optarg];
                    break;

                case 'O':
                    symbolsPath = [NSString stringWithUTF8String:optarg];
                    break;

                case 'm':
                    symbolMappingPath = [NSString stringWithUTF8String:optarg];
                    break;

                case 'c':
                    crashDumpPath = [NSString stringWithUTF8String:optarg];
                    break;

                case 'i':
                    [ignoreSymbols addObject:[NSString stringWithUTF8String:optarg]];
                    break;

                case 't':
                    classDump.shouldShowHeader = NO;
                    break;

                //modes..
                case PPIOS_CG_OPT_ANALYZE:
                    //do analysis
                    classDump.shouldAnalyze = YES;
                    break;

                case PPIOS_CG_OPT_OBFUSCATE:
                    classDump.shouldObfuscate = YES;
                    break;

                case CD_OPT_LIST_ARCHES:
                    shouldListArches = YES;
                    break;

                case CD_OPT_VERSION:
                    shouldPrintVersion = YES;
                    break;

                case '?':
                default:
                    errorFlag = YES;
                    break;
            }
        }

        if (errorFlag) {
            print_usage();
            exit(2);
        }

        if (shouldPrintVersion) {
            printf("PreEmptive Protection for iOS - Class Guard, version %s\n", CLASS_DUMP_VERSION);
            exit(0);
        }

        if (!symbolMappingPath) {
            symbolMappingPath = defaultSymbolMappingPath;
        }

        if (classDump.shouldObfuscate) {
            int result = [classDump obfuscateSourcesUsingMap:symbolMappingPath
                                           symbolsHeaderFile:symbolsPath
                                            workingDirectory:@"."
                                                xibDirectory:xibBaseDirectory];
            if (result != 0) {
                // errors already reported
                exit(result);
            }
        } else if (optind < argc) {
            NSString *arg = [NSString stringWithFileSystemRepresentation:argv[optind]];
            NSString *executablePath = [arg executablePathForFilename];
            if (shouldListArches) {
                if (executablePath == nil) {
                    printf("none\n");
                } else {
                    CDSearchPathState *searchPathState = [[CDSearchPathState alloc] init];
                    searchPathState.executablePath = executablePath;
                    id macho = [CDFile fileWithContentsOfFile:executablePath searchPathState:searchPathState];
                    if (macho == nil) {
                        printf("none\n");
                    } else {
                        if ([macho isKindOfClass:[CDMachOFile class]]) {
                            printf("%s\n", [[macho archName] UTF8String]);
                        } else if ([macho isKindOfClass:[CDFatFile class]]) {
                            printf("%s\n", [[[macho archNames] componentsJoinedByString:@" "] UTF8String]);
                        }
                    }
                }
            } else {
                if (executablePath == nil) {
                    fprintf(stderr, "class-dump: Input file (%s) doesn't contain an executable.\n", [arg fileSystemRepresentation]);
                    exit(1);
                }

                classDump.searchPathState.executablePath = [executablePath stringByDeletingLastPathComponent];
                CDFile *file = [CDFile fileWithContentsOfFile:executablePath searchPathState:classDump.searchPathState];
                if (file == nil) {
                    NSFileManager *defaultManager = [NSFileManager defaultManager];

                    if ([defaultManager fileExistsAtPath:executablePath]) {
                        if ([defaultManager isReadableFileAtPath:executablePath]) {
                            fprintf(stderr, "class-dump: Input file (%s) is neither a Mach-O file nor a fat archive.\n", [executablePath UTF8String]);
                        } else {
                            fprintf(stderr, "class-dump: Input file (%s) is not readable (check read permissions).\n", [executablePath UTF8String]);
                        }
                    } else {
                        fprintf(stderr, "class-dump: Input file (%s) does not exist.\n", [executablePath UTF8String]);
                    }

                    exit(1);
                }

                if (hasSpecifiedArch == NO) {
                    if ([file bestMatchForLocalArch:&targetArch] == NO) {
                        fprintf(stderr, "Error: Couldn't get local architecture\n");
                        exit(1);
                    }
                }

                classDump.targetArch = targetArch;
                classDump.searchPathState.executablePath = [executablePath stringByDeletingLastPathComponent];

                NSError *error;
                if (![classDump loadFile:file error:&error depth:0]) {
                    fprintf(stderr, "Error: %s\n", [[error localizedFailureReason] UTF8String]);
                    exit(1);
                } else {
                    if (![classDump.sdkRoot length]) {
                        printf("Please specify either --sdk-mac/--sdk-ios or --sdk-root\n");
                        print_usage();
                        exit(3);
                    }
                    if (symbolsPath == nil && !classDump.shouldAnalyze) {
                        printf("Please specify symbols file path\n");
                        print_usage();
                        exit(3);
                    }else if(symbolsPath != nil && classDump.shouldAnalyze) {
                        printf("Do not specify the symbols file path when using --analyze\n");
                        print_usage();
                        exit(3);
                    }
                    
                    [classDump processObjectiveCData];
                    [classDump registerTypes];

                    CDCoreDataModelProcessor *coreDataModelProcessor = [[CDCoreDataModelProcessor alloc] init];
                    [classFilter addObjectsFromArray:[coreDataModelProcessor coreDataModelSymbolsToExclude]];


                    CDSystemProtocolsProcessor *systemProtocolsProcessor = [[CDSystemProtocolsProcessor alloc] initWithSdkPath:classDump.sdkRoot];
                    [ignoreSymbols addObjectsFromArray:[systemProtocolsProcessor systemProtocolsSymbolsToExclude]];

                    CDSymbolsGeneratorVisitor *visitor = [CDSymbolsGeneratorVisitor new];
                    visitor.classDump = classDump;
                    visitor.classFilter = classFilter;
                    visitor.ignoreSymbols = ignoreSymbols;
                    visitor.symbolsFilePath = symbolsPath;

                    [classDump recursivelyVisit:visitor];
                    if(!classDump.shouldAnalyze){
                        CDXibStoryBoardProcessor *processor = [[CDXibStoryBoardProcessor alloc] init];
                        processor.xibBaseDirectory = xibBaseDirectory;
                        [processor obfuscateFilesUsingSymbols:visitor.symbols];
                    }
                    CDSymbolMapper *mapper = [[CDSymbolMapper alloc] init];
                    [mapper writeSymbolsFromSymbolsVisitor:visitor toFile:symbolMappingPath];
                }
            }
        }  else if (crashDumpPath) {
            NSString *crashDump = [NSString stringWithContentsOfFile:crashDumpPath encoding:NSUTF8StringEncoding error:nil];
            if (crashDump.length == 0) {
                fprintf(stderr, "class-dump: crash dump file does not exist or is empty %s", [crashDumpPath fileSystemRepresentation]);
                exit(4);
            }

            NSString *symbolsData = [NSString stringWithContentsOfFile:symbolMappingPath encoding:NSUTF8StringEncoding error:nil];
            if (symbolsData.length == 0) {
                fprintf(stderr, "class-dump: symbols file does not exist or is empty %s", [symbolMappingPath fileSystemRepresentation]);
                exit(5);
            }

            CDSymbolMapper *mapper = [[CDSymbolMapper alloc] init];
            NSString *processedFile = [mapper processCrashDump:crashDump withSymbols:[NSJSONSerialization JSONObjectWithData:[symbolsData dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]];
            [processedFile writeToFile:crashDumpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else if (dSYMInPath) {
            NSString *symbolsData = [NSString stringWithContentsOfFile:symbolMappingPath encoding:NSUTF8StringEncoding error:nil];
            if (symbolsData.length == 0) {
                fprintf(stderr, "class-dump: symbols file does not exist or is empty %s", [symbolMappingPath fileSystemRepresentation]);
                exit(5);
            }

            NSRange dSYMPathRange = [dSYMInPath rangeOfString:@".dSYM"];
            if (dSYMPathRange.location == NSNotFound) {
                fprintf(stderr, "class-dump: no valid dsym file provided %s", [dSYMOutPath fileSystemRepresentation]);
                exit(4);
            }

            CDdSYMProcessor *processor = [[CDdSYMProcessor alloc] init];
            NSArray *dwarfFilesPaths = [processor extractDwarfPathsForDSYM:dSYMInPath];

            for (NSString *dwarfFilePath in dwarfFilesPaths) {
                NSData *dwarfdumpData = [NSData dataWithContentsOfFile:dwarfFilePath];
                if (dwarfdumpData.length == 0) {
                    fprintf(stderr, "class-dump: dwarf file does not exist or is empty %s", [dwarfFilePath fileSystemRepresentation]);
                    exit(4);
                }

                NSData *processedFileContent = [processor processDwarfdump:dwarfdumpData
                                                               withSymbols:[NSJSONSerialization JSONObjectWithData:[symbolsData dataUsingEncoding:NSUTF8StringEncoding]
                                                                                                           options:0
                                                                                                             error:nil]];
                [processor writeDwarfdump:processedFileContent originalDwarfPath:dwarfFilePath inputDSYM:dSYMInPath outputDSYM:dSYMOutPath];
            }
        }
        exit(0); // avoid costly autorelease pool drain, we’re exiting anyway
    }
}
