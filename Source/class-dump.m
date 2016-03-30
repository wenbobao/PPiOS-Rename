// -*- mode: ObjC -*-

//  This file is part of class-dump, a utility for examining the Objective-C segment of Mach-O files.
//  Copyright (C) 1997-1998, 2000-2001, 2004-2015 Steve Nygard.

#include <getopt.h>
#include <libgen.h>
#import <mach-o/dyld.h>

#import "CDClassDump.h"
#import "CDFindMethodVisitor.h"
#import "CDMachOFile.h"
#import "CDFatFile.h"
#import "CDFatArch.h"
#import "CDSearchPathState.h"
#import "CDSymbolsGeneratorVisitor.h"
#import "CDCoreDataModelProcessor.h"
#import "CDSymbolMapper.h"
#import "CDSystemProtocolsProcessor.h"
#import "CDdSYMProcessor.h"

NSString *defaultSymbolMappingPath = @"symbols.json";

#define SDK_PATH_BEFORE \
        "/Applications/Xcode.app/Contents/Developer" \
            "/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator"
#define SDK_PATH_AFTER ".sdk"
#define SDK_PATH_USAGE_STRING SDK_PATH_BEFORE "<version>" SDK_PATH_AFTER

void print_usage(void)
{
    fprintf(stderr,
            "PreEmptive Protection for iOS - Class Guard, version %s\n"
            "\n"
            "Usage:\n"
            "ios-class-guard --analyze [options] \n"
            "  ( --sdk-root <path> | --sdk-ios  <version> ) <mach-o-file>\n"
            "ios-class-guard --obfuscate-sources [options]\n"
            "ios-class-guard --list-arches <mach-o-file>\n"
            "ios-class-guard --version\n"
            "ios-class-guard --translate-crashdump [-m <path>] [options] <crash dump file>\n"
            "ios-class-guard --translate-dsym [-m <path>] [options] <input dsym file> <output dsym file>\n"
            "\n"
            "Modes of operation:\n"
            "  --analyze             Analyze a Mach-O binary and generate a symbol map\n"
            "  --obfuscate-sources   Alter source code (relative to current working\n"
            "                        directory), renaming based on the symbol map\n"
            "  --list-arches         List architectures available in a fat binary\n"
            "  --version             Print out the version information of ios-class-guard\n"
            "  --translate-crashdump Translate symbolicated crash dump\n"
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
            "  --sdk-root <path>     Specify full SDK root path (or one of the shortcuts)\n"
            "  --sdk-ios <version>   Specify iOS SDK by version, searching for:\n"
            "                        " SDK_PATH_USAGE_STRING "\n"
            "  --list-excluded-symbols <path>\n"
            "                        Emit the computed list of symbols to exclude from renaming\n"
            "\n"
            "Obfuscate sources mode options:\n"
            "  -X <directory>        Path for XIBs and storyboards (searched recursively)\n"
            "  -O <path>             Path of where to write obfuscated symbols header\n"
            "                        (default: symbols.h)\n"
            "\n"
            "Other options:\n"
            "  -c <path>             Path to symbolicated crash dump\n"
            "  --dsym-in <path>      Path to dSym file to translate\n"
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
#define CD_OPT_SDK_ROOT    6
#define CD_OPT_HIDE        7
#define CD_OPT_TRANSLATE_CRASH 10
#define CD_OPT_TRANSLATE_DSYM 11

#define PPIOS_OPT_ANALYZE ((int)'z')
#define PPIOS_OPT_OBFUSCATE ((int)'y')
#define PPIOS_OPT_LIST_EXCLUDED_SYMBOLS ((int)'x')
char* programName;

void reportError(int exitCode, const char* format, ...){
    va_list  args;
    va_start(args, format);
    fprintf(stderr, "%s: ", programName);
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");
    exit(exitCode);
}

void populateProgramName(){
    uint32_t bufsize;
    // Ask _NSGetExecutablePath() to return the buffer size
    // needed to hold the string containing the executable path

    _NSGetExecutablePath(NULL, &bufsize);

    // Allocate the string buffer and ask _NSGetExecutablePath()
    // to fill it with the executable path
    char *exepath = malloc(bufsize);
    _NSGetExecutablePath(exepath, &bufsize);

    programName = basename(exepath);
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        NSString * const SDK_PATH_PATTERN
                = [NSString stringWithUTF8String:SDK_PATH_BEFORE "%@" SDK_PATH_AFTER];
        NSFileManager * fileManager = [NSFileManager defaultManager];
        BOOL shouldAnalyze = NO;
        BOOL shouldObfuscate = NO;
        BOOL shouldListArches = NO;
        BOOL shouldPrintVersion = NO;
        BOOL shouldTranslateDsym = NO;
        BOOL shouldTranslateCrashDump = NO;
        CDArch targetArch;
        BOOL hasSpecifiedArch = NO;
        NSMutableSet *hiddenSections = [NSMutableSet set];
        NSMutableArray *classFilter = [NSMutableArray new];
        NSMutableArray *ignoreSymbols = [NSMutableArray new];
        NSString *xibBaseDirectory = nil;
        NSString *symbolsPath = nil;
        NSString *symbolMappingPath = nil;

        int ch;
        BOOL errorFlag = NO;

        struct option longopts[] = {
                { "filter-class",            no_argument,       NULL, 'F' },
                { "ignore-symbols",          required_argument, NULL, 'i' },
                { "xib-directory",           required_argument, NULL, 'X' },
                { "symbols-file",            required_argument, NULL, 'O' },
                { "symbols-map",             required_argument, NULL, 'm' },
                { "crash-dump",              required_argument, NULL, 'c' },
                { "arch",                    required_argument, NULL, CD_OPT_ARCH }, //needed?
                { "list-arches",             no_argument,       NULL, CD_OPT_LIST_ARCHES },
                { "list-excluded-symbols",   required_argument, NULL, PPIOS_OPT_LIST_EXCLUDED_SYMBOLS }, //'x'
                { "suppress-header",         no_argument,       NULL, 't' },
                { "version",                 no_argument,       NULL, CD_OPT_VERSION },
                { "sdk-ios",                 required_argument, NULL, CD_OPT_SDK_IOS },
                { "sdk-root",                required_argument, NULL, CD_OPT_SDK_ROOT },
                { "hide",                    required_argument, NULL, CD_OPT_HIDE },
                { "analyze",                 no_argument,       NULL, PPIOS_OPT_ANALYZE }, //'z'
                { "obfuscate-sources",       no_argument,       NULL, PPIOS_OPT_OBFUSCATE }, //'y'
                { "translate-crashdump",     no_argument,       NULL, CD_OPT_TRANSLATE_CRASH},
                { "translate-dsym",          no_argument,       NULL, CD_OPT_TRANSLATE_DSYM},
                { NULL,                      0,                 NULL, 0 },
        };

        populateProgramName();

        if (argc == 1) {
            print_usage();
            exit(0);
        }

        CDClassDump *classDump = [[CDClassDump alloc] init];

        while ( (ch = getopt_long(argc, argv, "Fi:tX:zy:O:m:", longopts, NULL)) != -1) {
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
                    NSString * versionString = [NSString stringWithUTF8String:optarg];
                    classDump.sdkRoot = [NSString stringWithFormat:SDK_PATH_PATTERN, versionString];
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

                case 'i':
                    [ignoreSymbols addObject:[NSString stringWithUTF8String:optarg]];
                    break;

                case 't':
                    classDump.shouldShowHeader = NO;
                    break;

                case PPIOS_OPT_LIST_EXCLUDED_SYMBOLS:
                    classDump.excludedSymbolsListFilename = [NSString stringWithUTF8String:optarg];
                    break;

                //modes..
                case PPIOS_OPT_ANALYZE:
                    //do analysis
                    shouldAnalyze = YES;
                    break;

                case PPIOS_OPT_OBFUSCATE:
                    shouldObfuscate = YES;
                    break;

                case CD_OPT_LIST_ARCHES:
                    shouldListArches = YES;
                    break;

                case CD_OPT_VERSION:
                    shouldPrintVersion = YES;
                    break;

                case CD_OPT_TRANSLATE_DSYM:
                    shouldTranslateDsym = YES;
                    break;
                case CD_OPT_TRANSLATE_CRASH:
                    shouldTranslateCrashDump = YES;
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

        if (!symbolMappingPath) {
            symbolMappingPath = defaultSymbolMappingPath;
        }

        NSString *firstArg = nil;
        if (optind < argc) {
            firstArg = [NSString stringWithFileSystemRepresentation:argv[optind]];
        }
        NSString *secondArg = nil;
        if(optind + 1 < argc ){
            secondArg = [NSString stringWithFileSystemRepresentation:argv[optind + 1]];
        }

        if (shouldPrintVersion) {
            printf("PreEmptive Protection for iOS - Class Guard, version %s\n", CLASS_DUMP_VERSION);
            exit(0);
        }


        if (shouldListArches) {
            if(firstArg == nil){
                reportError(1, "Input file must be specified for --list-arches");
            }
            NSString *executablePath = nil;
            executablePath = [firstArg executablePathForFilename];
            if (executablePath == nil) {
                reportError(1, "Input file (%s) doesn't contain an executable.", [firstArg fileSystemRepresentation]);
            }
            CDSearchPathState *searchPathState = [[CDSearchPathState alloc] init];
            searchPathState.executablePath = executablePath;
            id macho = [CDFile fileWithContentsOfFile:executablePath searchPathState:searchPathState];
            if (macho != nil) {
                if ([macho isKindOfClass:[CDMachOFile class]]) {
                    printf("%s\n", [[macho archName] UTF8String]);
                } else if ([macho isKindOfClass:[CDFatFile class]]) {
                    printf("%s\n", [[[macho archNames] componentsJoinedByString:@" "] UTF8String]);
                }
            }
        }

        if(shouldAnalyze){
            if(firstArg == nil){
                reportError(1, "Input file must be specified for --analyze");
            }
            NSString *executablePath = nil;
            executablePath = [firstArg executablePathForFilename];
            if (executablePath == nil) {
                reportError(1, "Input file (%s) doesn't contain an executable.", [firstArg fileSystemRepresentation]);
            }
            classDump.searchPathState.executablePath = [executablePath stringByDeletingLastPathComponent];

            if (![fileManager fileExistsAtPath:classDump.sdkRoot]) {
                reportError(1, "Specified SDK does not exist: %s", [classDump.sdkRoot UTF8String]);
            }

            CDFile *file = [CDFile fileWithContentsOfFile:executablePath searchPathState:classDump.searchPathState];
            if (file == nil) {
                if ([fileManager fileExistsAtPath:executablePath]) {
                    if ([fileManager isReadableFileAtPath:executablePath]) {
                        reportError(1, "Input file (%s) is neither a Mach-O file nor a fat archive.", [executablePath UTF8String]);
                    } else {
                        reportError(1, "Input file (%s) is not readable (check read permissions).", [executablePath UTF8String]);
                    }
                } else {
                    reportError(1, "Input file (%s) does not exist.", [executablePath UTF8String]);
                }
            }

            if (hasSpecifiedArch == NO) {
                if ([file bestMatchForLocalArch:&targetArch] == NO) {
                    reportError(1, "Error: Couldn't get local architecture");
                }
            }

            classDump.targetArch = targetArch;
            classDump.searchPathState.executablePath = [executablePath stringByDeletingLastPathComponent];

            NSError *error;
            if (![classDump loadFile:file error:&error depth:0]) {
                reportError(1, "Error: %s", [[error localizedFailureReason] UTF8String]);
            }
            if (![classDump.sdkRoot length]) {
                reportError(3, "Please specify either --sdk-ios or --sdk-root");
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
            visitor.excludedSymbolsListFilename = classDump.excludedSymbolsListFilename;

            [classDump recursivelyVisit:visitor];
            CDSymbolMapper *mapper = [[CDSymbolMapper alloc] init];
            [mapper writeSymbolsFromSymbolsVisitor:visitor toFile:symbolMappingPath];
        }

        if(shouldObfuscate){
            int result = [classDump obfuscateSourcesUsingMap:symbolMappingPath
                                           symbolsHeaderFile:symbolsPath
                                            workingDirectory:@"."
                                                xibDirectory:xibBaseDirectory];
            if (result != 0) {
                // errors already reported
                exit(result);
            }
        }

        if(shouldTranslateCrashDump) {
            if (!firstArg) {
                reportError(4, "Crash dump file must be specified");
            }
            NSString* crashDumpPath = firstArg;
            NSString *crashDump = [NSString stringWithContentsOfFile:crashDumpPath encoding:NSUTF8StringEncoding error:nil];
            if (crashDump.length == 0) {
                reportError(4, "Crash dump file does not exist or is empty %s", [crashDumpPath fileSystemRepresentation]);
            }

            NSString *symbolsData = [NSString stringWithContentsOfFile:symbolMappingPath encoding:NSUTF8StringEncoding error:nil];
            if (symbolsData.length == 0) {
                reportError(5, "Symbols file does not exist or is empty %s", [symbolMappingPath fileSystemRepresentation]);
            }

            CDSymbolMapper *mapper = [[CDSymbolMapper alloc] init];
            NSString *processedFile = [mapper processCrashDump:crashDump withSymbols:[NSJSONSerialization JSONObjectWithData:[symbolsData dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]];
            [processedFile writeToFile:crashDumpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }

        if (shouldTranslateDsym){
            NSString *dSYMInPath = firstArg;
            NSString *dSYMOutPath = secondArg;

            if(!dSYMInPath) {
                reportError(5, "No valid dSYM input file provided");
            }
            if(!dSYMOutPath) {
                reportError(5, "No valid dSYM output file path provided");
            }
            NSString *symbolsData = [NSString stringWithContentsOfFile:symbolMappingPath encoding:NSUTF8StringEncoding error:nil];
            if (symbolsData.length == 0) {
                reportError(5, "Symbols file does not exist or is empty %s", [symbolMappingPath fileSystemRepresentation]);
            }

            NSRange dSYMPathRange = [dSYMInPath rangeOfString:@".dSYM"];
            if (dSYMPathRange.location == NSNotFound) {
                reportError(4, "No valid dSYM file provided %s", [dSYMOutPath fileSystemRepresentation]);
            }

            CDdSYMProcessor *processor = [[CDdSYMProcessor alloc] init];
            NSArray *dwarfFilesPaths = [processor extractDwarfPathsForDSYM:dSYMInPath];

            for (NSString *dwarfFilePath in dwarfFilesPaths) {
                NSData *dwarfdumpData = [NSData dataWithContentsOfFile:dwarfFilePath];
                if (dwarfdumpData.length == 0) {
                    reportError(4, "DWARF file does not exist or is empty %s", [dwarfFilePath fileSystemRepresentation]);
                }

                NSData *processedFileContent = [processor processDwarfdump:dwarfdumpData
                                                               withSymbols:[NSJSONSerialization JSONObjectWithData:[symbolsData dataUsingEncoding:NSUTF8StringEncoding]
                                                                                                           options:0
                                                                                                             error:nil]];
                [processor writeDwarfdump:processedFileContent originalDwarfPath:dwarfFilePath inputDSYM:dSYMInPath outputDSYM:dSYMOutPath];
            }
        }
        free(programName);
        exit(0); // avoid costly autorelease pool drain, we’re exiting anyway
    }
}
