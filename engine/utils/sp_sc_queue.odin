package utils

import "core:mem"
import "core:sync"

// Sp_Sc_Queue_Node represents a single node in a single-producer, single-consumer queue.
@(private="file")
Sp_Sc_Queue_Node :: struct($Type: typeid) {
    value: Type,                        // The value stored in the node.
    next: ^Sp_Sc_Queue_Node(Type),      // Pointer to the next node in the queue.
}

// Sp_Sc_Queue represents a single-producer, single-consumer queue.
Sp_Sc_Queue :: struct($Type: typeid) {
    allocator: mem.Allocator,           // Memory allocator used for node allocations.
    head: ^Sp_Sc_Queue_Node(Type),      // Pointer to the head node of the queue.
    tail: ^Sp_Sc_Queue_Node(Type),      // Pointer to the tail node of the queue.
}

// Initializes a single-producer, single-consumer queue.
//
// Parameters:
//   queue: ^Sp_Sc_Queue($Type) - A pointer to the Sp_Sc_Queue instance.
//   allocator: mem.Allocator - The memory allocator to use for the queue
//                              (default is context.allocator).
init_sp_sc_queue :: proc(queue: ^Sp_Sc_Queue($Type), allocator: mem.Allocator = context.allocator) {
    queue.allocator = allocator
    queue.head = new(Sp_Sc_Queue_Node(Type), allocator)
    queue.tail = queue.head
}

// Destroys a single-producer, single-consumer queue, freeing all allocated nodes.
//
// Parameters:
//   queue: ^Sp_Sc_Queue($Type) - A pointer to the Sp_Sc_Queue instance to destroy.
destroy_sp_sc_queue :: proc(queue: ^Sp_Sc_Queue($Type)) {
    node := queue.head
    for node != nil {
        next := node.next
        mem.free(node)
        node = next
    }
}

// Pushes a new value onto the queue.
//
// Parameters:
//   queue: ^Sp_Sc_Queue($Type) - A pointer to the Sp_Sc_Queue instance.
//   value: Type - The value to push onto the queue.
push_sp_sc_queue :: proc(queue: ^Sp_Sc_Queue($Type), value: Type) {
    node := new(Sp_Sc_Queue_Node(Type), queue.allocator)
    node.value = value

    prev_node := sync.atomic_exchange_explicit(&queue.tail, node, .Acq_Rel)
    sync.atomic_store_explicit(&prev_node.next, node, .Relaxed)
}

// Removes and returns the value from the front of the queue.
//
// Parameters:
//   queue: ^Sp_Sc_Queue($Type) - A pointer to the Sp_Sc_Queue instance.
//
// Returns:
//   (Type, bool) - The value from the front of the queue and a boolean indicating success.
peek_sp_sc_queue :: proc(queue: ^Sp_Sc_Queue($Type)) -> (Type, bool) {
    head := sync.atomic_load_explicit(&queue.head, .Relaxed)
    next := sync.atomic_load_explicit(&head.next, .Acquire)

    if next != nil {
        result := next.value
        sync.atomic_store_explicit(&queue.head, next, .Release)
        free(head)
        return result, true
    }

    return {}, false
}