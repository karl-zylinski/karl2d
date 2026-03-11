#+build darwin

package dispatch

// Simple way to dispatch work to the main thread using NSOperationQueue (Foundation API)
// This is used to dispatch rendering work during live window resize

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

msgSend :: intrinsics.objc_send

// Get the main queue (NSOperationQueue)
@(objc_class="NSOperationQueue")
OperationQueue :: struct { using _: NS.Object }

@(objc_type=OperationQueue, objc_name="mainQueue", objc_is_class_method=true)
OperationQueue_mainQueue :: proc "c" () -> ^OperationQueue {
	return msgSend(^OperationQueue, OperationQueue, "mainQueue")
}

@(objc_type=OperationQueue, objc_name="addOperationWithBlock")
OperationQueue_addOperationWithBlock :: proc "c" (self: ^OperationQueue, block: ^NS.Block) {
	msgSend(nil, self, "addOperationWithBlock:", block)
}
