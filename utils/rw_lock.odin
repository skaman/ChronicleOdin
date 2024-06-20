package utils

import "core:sync"

// RW_Lock represents a readers-writer lock that allows concurrent reads but exclusive writes.
RW_Lock :: struct {
    lock: sync.Mutex,                // Mutex to protect the critical section.
    readers_proceed: sync.Cond,      // Condition variable to signal readers.
    writer_proceed: sync.Cond,       // Condition variable to signal writers.
    pending_writers: i32,            // Count of pending writers.
    readers: i32,                    // Count of active readers.
    writer: bool,                    // Indicates if a writer is active.
}

// Acquires the read lock, allowing multiple readers but blocking writers.
//
// Parameters:
//   rw: ^RW_Lock - A pointer to the RW_Lock instance.
read_lock :: proc(rw: ^RW_Lock) {
    sync.mutex_lock(&rw.lock)
    defer sync.mutex_unlock(&rw.lock);
    for rw.pending_writers > 0 || rw.writer {
        sync.cond_wait(&rw.readers_proceed, &rw.lock);
    }
    rw.readers += 1
}

// Releases the read lock.
//
// Parameters:
//   rw: ^RW_Lock - A pointer to the RW_Lock instance.
read_unlock :: proc(rw: ^RW_Lock) {
    assert(rw.readers > 0, "read_unlock: no readers")

    sync.mutex_lock(&rw.lock)
    defer sync.mutex_unlock(&rw.lock);
    rw.readers -= 1
    if rw.readers == 0 && rw.pending_writers > 0 {
        sync.cond_signal(&rw.writer_proceed);
    }
}

// Acquires the write lock, blocking all readers and writers until the lock is acquired.
//
// Parameters:
//   rw: ^RW_Lock - A pointer to the RW_Lock instance.
write_lock :: proc(rw: ^RW_Lock) {
    sync.mutex_lock(&rw.lock);
    defer sync.mutex_unlock(&rw.lock);
    rw.pending_writers += 1;
    for rw.readers > 0 || rw.writer {
        sync.cond_wait(&rw.writer_proceed, &rw.lock);
    }
    rw.pending_writers -= 1;
    rw.writer = true;
}

// Releases the write lock.
//
// Parameters:
//   rw: ^RW_Lock - A pointer to the RW_Lock instance.
write_unlock :: proc(rw: ^RW_Lock) {
    assert(rw.writer, "write_unlock: not a writer")

    sync.mutex_lock(&rw.lock);
    defer sync.mutex_unlock(&rw.lock);
    rw.writer = false;
    if rw.pending_writers > 0 {
        sync.cond_signal(&rw.writer_proceed);
    } else {
        sync.cond_broadcast(&rw.readers_proceed);
    }
}