/* Handle-based map using fixed arrays. By Karl Zylinski (karl@zylinski.se)

The Handle_Map maps a handle to an item. A handle consists of an index and a
generation. The item can be any type. Such a handle can be stored as a permanent
reference, where you'd usually store a pointer. The benefit of handles is that
you know if some other system has destroyed the object at that index, since the
generation will then differ.

This implementation uses fixed arrays and therefore
involves no dynamic memory allocations.

Example (assumes this package is imported under the alias `hm`):

	Entity_Handle :: hm.Handle

	Entity :: struct {
		// All items must contain a handle
		handle: Entity_Handle,
		pos: [2]f32,
	}

	// Note: We use `1024`, if you use a bigger number within a proc you may
	// blow the stack. In those cases: Store the array inside a global variable
	// or a dynamically allocated struct.
	entities: hm.Handle_Map(Entity, Entity_Handle, 1024)

	h1 := hm.add(&entities, Entity { pos = { 5, 7 } })
	h2 := hm.add(&entities, Entity { pos = { 10, 5 } })

	// Resolve handle -> pointer
	if h2e := hm.get(&entities, h2); h2e != nil {
		h2e.pos.y = 123
	}

	// Will remove this entity, leaving an unused slot
	hm.remove(&entities, h1)

	// Will reuse the slot h1 used
	h3 := hm.add(&entities, Entity { pos = { 1, 2 } })

	// Iterate. You can also use `for e in hm.items {}` and skip any item where
	// `e.handle.idx == 0`. The iterator does that automatically. There's also
	// `skip` procedure in this package that check `e.handle.idx == 0` for you.
	ent_iter := hm.make_iter(&entities)
	for e, h in hm.iter(&ent_iter) {
		e.pos += { 5, 1 }
	}
*/
package handle_map_fixed

import "base:intrinsics"

// Returned from the `add` proc. Store these as permanent references to items in
// the handle map. You can resolve the handle to a pointer using the `get` proc.
Handle :: struct {
	// index into `items` array of the `Handle_Map` struct.
	idx: u32,

	// When using the `get` proc, this will be matched to the `gen` on the item
	// in the handle map. The handle is only valid if they match. If they don't
	// match, then it means that the slot in the handle map has been reused.
	gen: u32,
}

Handle_Map :: struct($T: typeid, $HT: typeid, $N: int) {
	// Each item must have a field `handle` of type `HT`.
	//
	// There's always a "dummy element" at index 0. This way, a Handle with
	// `idx == 0` means "no Handle". This means that you actually have `N - 1`
	// items available.
	items: [N]T,

	// How much of `items` that is in use.
	num_items: u32,

	// The index of the first unused element in `items`. At this index in
	// `unused_items` you'll find the next-next unused index. Used by `add` and
	// originally set by `remove`.
	next_unused: u32,

	// An element in this array that is non-zero means the thing at that index
	// in `items` is unused. The non-zero number is the index of the next unused
	// item. This forms a linked series of indices. The series starts with
	// `next_unused`.
	unused_items: [N]u32,

	// Only used for making it possible to quickly calculate the number of valid
	// elements.
	num_unused: u32,
}

// Clears the handle map using `mem_zero`. It doesn't do `m^ = {}` because that
// may blow the stack for a handle map with very big `N`
clear :: proc(m: ^Handle_Map($T, $HT, $N)) {
	intrinsics.mem_zero(m, size_of(m^))
}

// Add a value of type `T` to the handle map. Returns a handle you can use as a
// permanent reference.
//
// Will reuse the item at `next_unused` if that value is non-zero.
//
// Second return value is `false` if the handle-based map is full.
add :: proc(m: ^Handle_Map($T, $HT, $N), v: T) -> (HT, bool) #optional_ok {
	v := v

	if m.next_unused != 0 {
		idx := m.next_unused
		item := &m.items[idx]
		m.next_unused = m.unused_items[idx]
		m.unused_items[idx] = 0
		gen := item.handle.gen
		item^ = v
		item.handle.idx = u32(idx)
		item.handle.gen = gen + 1
		m.num_unused -= 1
		return item.handle, true
	}

	// We always have a "dummy item" at index zero. This is because handle.idx
	// being zero means "no item", so we can't use that slot for anything.
	if m.num_items == 0 {
		m.items[0] = {}
		m.num_items += 1
	}

	if m.num_items == len(m.items) {
		return {}, false
	}

	item := &m.items[m.num_items]
	item^ = v
	item.handle.idx = u32(m.num_items)
	item.handle.gen = 1
	m.num_items += 1
	return item.handle, true
}

// Resolve a handle to a pointer of type `^T`. The pointer is stable since the
// handle map uses a fixed array. But you should _not_ store the pointer
// permanently. The item may get reused if any part of your program destroys and
// reuses that slot. Only store handles permanently and temporarily resolve them
// into pointers as needed.
get :: proc(m: ^Handle_Map($T, $HT, $N), h: HT) -> ^T {
	if h.idx <= 0 || h.idx >= m.num_items {
		return nil
	}

	if item := &m.items[h.idx]; item.handle == h {
		return item
	}

	return nil
}

// Remove an item from the handle map. You choose which item by passing a handle
// to this proc. The item is not really destroyed, rather its index is just
// set on `m.next_unused`. Also, the item's `handle.idx` is set to zero, this
// is used by the `iter` proc in order to skip that item when iterating.
remove :: proc(m: ^Handle_Map($T, $HT, $N), h: HT) {
	if h.idx <= 0 || h.idx >= m.num_items {
		return
	}

	if item := &m.items[h.idx]; item.handle == h {
		m.unused_items[h.idx] = m.next_unused
		m.next_unused = h.idx
		m.num_unused += 1
		item.handle.idx = 0
	}
}

// Tells you if a handle maps to a valid item. This is done by checking if the
// handle on the item is the same as the passed handle.
valid :: proc(m: Handle_Map($T, $HT, $N), h: HT) -> bool {
	return h.idx > 0 && h.idx < m.num_items && m.items[h.idx].handle == h
}

// Tells you how many valid items there are in the handle map.
num_used :: proc(m: Handle_Map($T, $HT, $N)) -> int {
	return int(m.num_items - m.num_unused)
}

// The maximum number of items the handle map can contain.
cap :: proc(m: Handle_Map($T, $HT, $N)) -> int {
	return N
}

// For iterating a handle map. Create using `make_iter`.
Handle_Map_Iterator :: struct($T: typeid, $HT: typeid, $N: int) {
	m: ^Handle_Map(T, HT, N),
	index: u32,
}

// Create an iterator. Use with `iter` to do the actual iteration.
make_iter :: proc(m: ^Handle_Map($T, $HT, $N)) -> Handle_Map_Iterator(T, HT, N) {
	return { m = m, index = 1 }
}

// Iterate over the handle map. Skips unused slots, meaning that it skips slots
// with handle.idx == 0.
//
// Usage:
//     my_iter := hm.make_iter(&my_handle_map)
//     for e in hm.iter(&my_iter) {}
// 
// Instead of using an iterator you can also loop over `items` and check if
// `item.handle.idx == 0` and in that case skip that item.
iter :: proc(it: ^Handle_Map_Iterator($T, $HT, $N)) -> (val: ^T, h: HT, cond: bool) {
	for _ in it.index..<it.m.num_items {
		item := &it.m.items[it.index]
		it.index += 1

		if item.handle.idx != 0 {
			return item, item.handle, true
		}
	}

	return nil, {}, false
}

// If you don't want to use iterator, you can instead do:
// for &item in my_map.items {
//     if hm.skip(item) {
//         continue
//     }
//     // do stuff
// }
skip :: proc(e: $T) -> bool {
	return e.handle.idx == 0
}