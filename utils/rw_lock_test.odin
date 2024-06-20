package utils

import "core:testing"
import "core:thread"
import "core:time"

@test
test_rw_lock :: proc(t: ^testing.T) {
    rw : RW_Lock
    
    RW_Context :: struct {
        rw: ^RW_Lock,
        t: ^testing.T,
        readers: i32,
        writers: i32,
    }

    rw_ctx := RW_Context{&rw, t, 0, 0}

    // Test multiple readers
    thread.create_and_start_with_data(&rw_ctx, proc(rw_ctx_ptr: rawptr) {
        rw_ctx := (^RW_Context)(rw_ctx_ptr)
        read_lock(rw_ctx.rw)
        defer read_unlock(rw_ctx.rw)

        testing.expectf(rw_ctx.t, rw_ctx.writers == 0, "Expected 0 writer, got %d", rw_ctx.writers)
        rw_ctx.readers += 1

        testing.log(rw_ctx.t, "Reader 1 acquired the lock")
        time.sleep(100 * time.Millisecond)

        testing.expectf(rw_ctx.t, rw_ctx.writers == 0, "Expected 0 writer, got %d", rw_ctx.writers)
        rw_ctx.readers -= 1
        testing.log(rw_ctx.t, "Reader 1 released the lock")
    }, nil, .Normal, true)

    thread.create_and_start_with_data(&rw_ctx, proc(rw_ctx_ptr: rawptr) {
        rw_ctx := (^RW_Context)(rw_ctx_ptr)
        read_lock(rw_ctx.rw)
        defer read_unlock(rw_ctx.rw)

        testing.expectf(rw_ctx.t, rw_ctx.writers == 0, "Expected 0 writer, got %d", rw_ctx.writers)
        rw_ctx.readers += 1

        testing.log(rw_ctx.t, "Reader 2 acquired the lock")
        time.sleep(100 * time.Millisecond)

        testing.expectf(rw_ctx.t, rw_ctx.writers == 0, "Expected 0 writer, got %d", rw_ctx.writers)
        rw_ctx.readers -= 1
        testing.log(rw_ctx.t, "Reader 2 released the lock")
    }, nil, .Normal, true)


    time.sleep(50 * time.Millisecond)

    // Test single writer
    thread.create_and_start_with_data(&rw_ctx, proc(rw_ctx_ptr: rawptr) {
        rw_ctx := (^RW_Context)(rw_ctx_ptr)
        write_lock(rw_ctx.rw)
        defer write_unlock(rw_ctx.rw)

        testing.expectf(rw_ctx.t, rw_ctx.readers == 0, "Expected 0 writer, got %d", rw_ctx.readers)
        rw_ctx.writers += 1

        testing.log(rw_ctx.t, "Writer acquired the lock")
        time.sleep(100 * time.Millisecond)

        testing.expectf(rw_ctx.t, rw_ctx.readers == 0, "Expected 0 writer, got %d", rw_ctx.readers)
        rw_ctx.writers -= 1
        testing.log(rw_ctx.t, "Writer released the lock")
    }, nil, .Normal, true)

    // Wait for the writer to acquire and release the lock
    time.sleep(300 * time.Millisecond)
    
    // Test with multiple readers and a writer in sequence
    thread.create_and_start_with_data(&rw_ctx, proc(rw_ctx_ptr: rawptr) {
        rw_ctx := (^RW_Context)(rw_ctx_ptr)
        read_lock(rw_ctx.rw)
        defer read_unlock(rw_ctx.rw)

        testing.expectf(rw_ctx.t, rw_ctx.writers == 0, "Expected 0 writer, got %d", rw_ctx.writers)
        rw_ctx.readers += 1

        testing.log(rw_ctx.t, "Reader 3 acquired the lock")
        time.sleep(100 * time.Millisecond)

        testing.expectf(rw_ctx.t, rw_ctx.writers == 0, "Expected 0 writer, got %d", rw_ctx.writers)
        rw_ctx.readers -= 1
        testing.log(rw_ctx.t, "Reader 3 released the lock")
    }, nil, .Normal, true)

    thread.create_and_start_with_data(&rw_ctx, proc(rw_ctx_ptr: rawptr) {
        rw_ctx := (^RW_Context)(rw_ctx_ptr)
        write_lock(rw_ctx.rw)
        defer write_unlock(rw_ctx.rw)

        testing.expectf(rw_ctx.t, rw_ctx.readers == 0, "Expected 0 writer, got %d", rw_ctx.readers)
        rw_ctx.writers += 1

        testing.log(rw_ctx.t, "Writer 2 acquired the lock")
        time.sleep(100 * time.Millisecond)

        testing.expectf(rw_ctx.t, rw_ctx.readers == 0, "Expected 0 writer, got %d", rw_ctx.readers)
        rw_ctx.writers -= 1
        testing.log(rw_ctx.t, "Writer 2 released the lock")
    }, nil, .Normal, true)

    thread.create_and_start_with_data(&rw_ctx, proc(rw_ctx_ptr: rawptr) {
        rw_ctx := (^RW_Context)(rw_ctx_ptr)
        read_lock(rw_ctx.rw)
        defer read_unlock(rw_ctx.rw)

        testing.expectf(rw_ctx.t, rw_ctx.writers == 0, "Expected 0 writer, got %d", rw_ctx.writers)
        rw_ctx.readers += 1

        testing.log(rw_ctx.t, "Reader 4 acquired the lock")
        time.sleep(100 * time.Millisecond)

        testing.expectf(rw_ctx.t, rw_ctx.writers == 0, "Expected 0 writer, got %d", rw_ctx.writers)
        rw_ctx.readers -= 1
        testing.log(rw_ctx.t, "Reader 4 released the lock")
    }, nil, .Normal, true)

    time.sleep(500 * time.Millisecond)
}