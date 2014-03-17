#import "InputTaskCell.h"
#import "TasksController.h"
#import "TaskCell.h"
#import <Dropbox/Dropbox.h>

@interface TasksController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, readonly) DBAccountManager *accountManager;
@property (nonatomic, readonly) DBAccount *account;
@property (nonatomic, retain) DBDatastore *store;
@property (nonatomic, retain) NSMutableArray *tasks;
@property (nonatomic, retain) InputTaskCell *inputTaskCell;

@end

@implementation TasksController

- (void)dealloc {
    [_store removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.rowHeight = 50.0f;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    __weak TasksController *slf = self;
    [self.accountManager addObserver:self block:^(DBAccount *account) {
        [slf setupTasks];
    }];

    [self setupTasks];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.accountManager removeObserver:self];
    if (_store) {
        [_store removeObserver:self];
    }
    self.store = nil;
}

- (IBAction)didPressLink {
    [[DBAccountManager sharedManager] linkFromController:self];
}

- (IBAction)didPressUnlink {
    [[[DBAccountManager sharedManager] linkedAccount] unlink];
    self.store = nil;

    [self.tableView reloadData];
}


#pragma mark UITableViewDataSource methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!self.account) {
        return 1;
    } else {
        return [_tasks count] + 2;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    if (![DBAccountManager sharedManager].linkedAccount) {
        return [tableView dequeueReusableCellWithIdentifier:@"LinkCell"];
    } else if ([indexPath row] == [_tasks count]) {
        if (!_inputTaskCell) {
            _inputTaskCell = [tableView dequeueReusableCellWithIdentifier:@"InputTaskCell"];
        }
        return _inputTaskCell;
    } else if ([indexPath row] == [_tasks count]+1) {
        return [tableView dequeueReusableCellWithIdentifier:@"UnlinkCell"];
    } else {
        TaskCell *taskCell = [tableView dequeueReusableCellWithIdentifier:@"TaskCell"];
        DBRecord *task = _tasks[[indexPath row]];
        taskCell.taskLabel.text = task[@"taskname"];
        UIView *checkmark = taskCell.taskCompletedView;
        if ([task[@"completed"] boolValue]) {
            checkmark.hidden = NO;
        } else {
            checkmark.hidden = YES;
        }
        return taskCell;
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.account) {
        if ([indexPath row] == [_tasks count]) {
            [self.inputTaskCell.textField becomeFirstResponder];
        } else {
            DBRecord *task = _tasks[[indexPath row]];
            task[@"completed"] = [task[@"completed"] boolValue] ? @NO : @YES;
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.account && [indexPath row] < [_tasks count];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {

    DBRecord *record = _tasks[[indexPath row]];
    [record deleteRecord];
    [_tasks removeObjectAtIndex:[indexPath row]];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 60.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return self.headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 24.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return [UIView new];
}


#pragma mark - UITextFieldDelegate methods

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if ([textField.text length]) {
        DBTable *tasksTbl = [self.store getTable:@"tasks"];

        DBRecord *task = [tasksTbl insert:@{ @"taskname": textField.text, @"completed": @NO, @"created": [NSDate date] } ];
        [_tasks addObject:task];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:([_tasks count] - 1) inSection:0];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];

        textField.text = nil;
    }

    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[_tasks count] inSection:0];
    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionTop animated:YES];
}

#pragma mark - private methods

- (DBAccountManager *)accountManager {
    return [DBAccountManager sharedManager];
}

- (DBAccount *)account {
    return self.accountManager.linkedAccount;
}

- (DBDatastore *)store {
    if (!_store && self.account) {
        _store = [DBDatastore openDefaultStoreForAccount:self.account error:nil];
    }
    return _store;
}

- (void)setupTasks {
    if (self.account) {
        __weak TasksController *slf = self;
        [self.store addObserver:self block:^ {
            if (slf.store.status & (DBDatastoreIncoming | DBDatastoreOutgoing)) {
                [slf syncTasks];
            }
        }];
        _tasks = [NSMutableArray arrayWithArray:[[self.store getTable:@"tasks"] query:nil error:nil]];
        [_tasks sortUsingComparator: ^(DBRecord *obj1, DBRecord *obj2) {
            return [obj1[@"created"] compare:obj2[@"created"]];
        }];
    } else {
        _store = nil;
        _tasks = nil;
    }
    [self.tableView reloadData];
    [self syncTasks];
}

- (void)syncTasks {
    if (self.account) {
        NSDictionary *changed = [self.store sync:nil];
        [self update:changed];
    }
}

- (void)update:(NSDictionary *)changedDict {
    NSMutableDictionary *changed = [NSMutableDictionary dictionary]; // dictionary of recordId -> record
    for (DBRecord *changedTask in [changedDict[@"tasks"] allObjects]) {
        changed[changedTask.recordId] = changedTask;
    }

    // Remove deleted rows, update existing rows
    NSMutableIndexSet *deletes = [[NSMutableIndexSet alloc] init];
    NSMutableArray *deletePaths = [[NSMutableArray alloc] init];
    NSMutableArray *updatePaths = [[NSMutableArray alloc] init];
    [_tasks enumerateObjectsUsingBlock:^(DBRecord *obj, NSUInteger idx, BOOL *stop) {
        if (changed[obj.recordId] != nil) {
            if (obj.deleted) {
                [deletes addIndex:idx];
                [deletePaths addObject:[NSIndexPath indexPathForRow:idx inSection:0]];
            } else {
                [updatePaths addObject:[NSIndexPath indexPathForRow:idx inSection:0]];
            }
            [changed removeObjectForKey:obj.recordId]; // mark that we processed this update
        }
    }];
    [_tasks removeObjectsAtIndexes:deletes];
    [self.tableView deleteRowsAtIndexPaths:deletePaths withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.tableView reloadRowsAtIndexPaths:updatePaths withRowAnimation:UITableViewRowAnimationAutomatic];

    // Add new rows (in sorted order assuming _tasks is already sorted)
    [_tasks addObjectsFromArray:[changed allValues]]; // anything not processed in changed are inserts
    [_tasks sortUsingComparator: ^(DBRecord *obj1, DBRecord *obj2) {
        return [obj1[@"created"] compare:obj2[@"created"]];
    }];
    NSMutableArray *insertPaths = [[NSMutableArray alloc] init];
    [_tasks enumerateObjectsUsingBlock:^(DBRecord *obj, NSUInteger idx, BOOL *stop) {
        if (changed[obj.recordId] != nil) {
            [insertPaths addObject:[NSIndexPath indexPathForRow:idx inSection:0]];
        }
    }];
    [self.tableView insertRowsAtIndexPaths:insertPaths withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
