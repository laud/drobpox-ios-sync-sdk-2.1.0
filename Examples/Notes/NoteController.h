#import <Dropbox/Dropbox.h>

@interface NoteController : UIViewController

- (id)initWithFile:(DBFile *)file filesystem:(DBFilesystem *)filesystem;

@property (nonatomic) BOOL newFile;

@end
