package utils

import "core:testing"
import "core:thread"
import "core:time"

@test
test_sp_sc_queue :: proc(t: ^testing.T) {
    queue : Sp_Sc_Queue(int)

    init_sp_sc_queue(&queue)
    defer destroy_sp_sc_queue(&queue)

    push_sp_sc_queue(&queue, 10)
    push_sp_sc_queue(&queue, 20)
    push_sp_sc_queue(&queue, 30)

    value, ok := peek_sp_sc_queue(&queue)
    testing.expectf(t, ok, "Expected peek to succeed, got %t", ok)
    testing.expectf(t, value == 10, "Expected 10, got %d", value)

    value, ok = peek_sp_sc_queue(&queue)
    testing.expectf(t, ok, "Expected peek to succeed, got %t", ok)
    testing.expectf(t, value == 20, "Expected 20, got %d", value)

    value, ok = peek_sp_sc_queue(&queue)
    testing.expectf(t, ok, "Expected peek to succeed, got %t", ok)
    testing.expectf(t, value == 30, "Expected 30, got %d", value)

    value, ok = peek_sp_sc_queue(&queue)
    testing.expectf(t, !ok, "Expected peek to fail, got %t", ok)
}

@test
test_sp_sc_queue_thread :: proc(t: ^testing.T) {
    queue : Sp_Sc_Queue(int)
    init_sp_sc_queue(&queue)
    defer destroy_sp_sc_queue(&queue)

    Thread_Context :: struct {
        queue: ^Sp_Sc_Queue(int),
        t: ^testing.T,
    }

    ctx := Thread_Context{&queue, t}

    ITERATIONS_COUNT :: 500000

    // Producer thread
    thread.create_and_start_with_data(&ctx, proc(ctx_ptr: rawptr) {
        ctx := (^Thread_Context)(ctx_ptr)
        for i in 0..<ITERATIONS_COUNT {
            push_sp_sc_queue(ctx.queue, i)
            time.sleep(1 * time.Microsecond)
        }
    }, nil, .Normal, true)

    // Consumer thread
    thread.create_and_start_with_data(&ctx, proc(ctx_ptr: rawptr) {
        ctx := (^Thread_Context)(ctx_ptr)
        
        it_count := 0
        for it_count < ITERATIONS_COUNT {
            value, ok := peek_sp_sc_queue(ctx.queue)
            if !ok {
                continue
            }
            testing.expectf(ctx.t, ok, "Expected peek to succeed, got %t", ok)
            expected := it_count
            testing.expectf(ctx.t, value == expected, "Expected %d, got %d", expected, value)
            it_count += 1
        }

        value, ok := peek_sp_sc_queue(ctx.queue)
        testing.expectf(ctx.t, !ok, "Expected peek to fail, got %t", ok)
    }, nil, .Normal, true)

    // Wait for threads to finish
    time.sleep(500 * time.Millisecond)
}