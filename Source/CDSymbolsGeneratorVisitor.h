#import "CDVisitor.h"


@interface CDSymbolsGeneratorVisitor : CDVisitor
@property (nonatomic, copy) NSArray<NSString *> *classFilters;
@property (nonatomic, copy) NSArray<NSString *> *exclusionPatterns;
@property (nonatomic, readonly) NSDictionary *symbols;
@property (nonatomic, copy) NSString *diagnosticFilesPrefix;
- (void)addSymbolsPadding;

+ (void)appendDefineTo:(NSMutableString *)stringBuilder
              renaming:(NSString *)oldName
                    to:(NSString *)newName;

+ (void)writeSymbols:(NSDictionary<NSString *, NSString *> *)symbols
   symbolsHeaderFile:(NSString *)symbolsHeaderFile;
@end
