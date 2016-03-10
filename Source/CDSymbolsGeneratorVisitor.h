#import "CDVisitor.h"


@interface CDSymbolsGeneratorVisitor : CDVisitor
@property (nonatomic, copy) NSArray *classFilter;
@property (nonatomic, copy) NSArray *ignoreSymbols;
@property (nonatomic, readonly) NSString *resultString;
@property (nonatomic, readonly) NSDictionary *symbols;
@property(nonatomic, copy) NSString *symbolsFilePath;
- (void)addSymbolsPadding;

+ (void)appendDefineTo:(NSMutableString *)stringBuilder
              renaming:(NSString *)oldName
                    to:(NSString *)newName;

+ (void)writeSymbols:(NSDictionary<NSString *, NSString *> *)symbols
   symbolsHeaderFile:(NSString *)symbolsHeaderFile;
@end
