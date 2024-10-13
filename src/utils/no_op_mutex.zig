
pub inline fn tryLock(_: *NoOpMutex) bool {
    return true;
}

pub inline fn lock(_: *NoOpMutex) void {
    
}

pub inline fn unlock(_: *NoOpMutex) void {
    
}

const NoOpMutex = @This();
