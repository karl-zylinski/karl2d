package karl2d
import "base:intrinsics"

write_int_le :: proc(value: $T, buf: []u8, offset := 0) where intrinsics.type_is_numeric(T) {
	switch size_of(T) {
	case 1:
		buf[offset] = u8(value & 0xFF)
	case 2:
		buf[offset] = u8(value & 0xFF)
		buf[offset + 1] = u8((value >> 8) & 0xFF)
	case 4:
		buf[offset] = u8(value & 0xFF)
		buf[offset + 1] = u8((value >> 8) & 0xFF)
		buf[offset + 2] = u8((value >> 16) & 0xFF)
		buf[offset + 3] = u8((value >> 24) & 0xFF)
	case 8:
		buf[offset] = u8(value & 0xFF)
		buf[offset + 1] = u8((value >> 8) & 0xFF)
		buf[offset + 2] = u8((value >> 16) & 0xFF)
		buf[offset + 3] = u8((value >> 24) & 0xFF)
		buf[offset + 4] = u8((value >> 32) & 0xFF)
		buf[offset + 5] = u8((value >> 40) & 0xFF)
		buf[offset + 6] = u8((value >> 48) & 0xFF)
		buf[offset + 7] = u8((value >> 56) & 0xFF)
	}
}
