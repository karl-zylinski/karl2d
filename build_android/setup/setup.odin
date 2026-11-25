// Downloads Android SDK things and Java
package karl2d_build_android_setup

import "base:runtime"
import "core:c"
import "core:compress/deflate"
import "core:crypto/legacy/sha1"
import "core:crypto/sha2"
import "core:encoding/hex"
import "core:fmt"
import "core:hash"
import os "core:os"
import "core:strings"
import curl "vendor:curl"

SDK_DIR :: #directory + "../sdk"
JRE_DIR_NAME :: "jre"
ANDROID_URL :: "https://dl.google.com/android/repository/"
JRE_URL :: "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13.1%2B2/"

Package :: struct {
	dest_dir: string,
	url: string,
	checksum: string,
}

when ODIN_OS == .Windows {
	PACKAGES :: [?]Package {
		{
			"platform-tools",
			ANDROID_URL + "platform-tools_r37.0.3-win.zip",
			"7fea85bc18d0480bc81d3603952d666f49496e5a",
		},
		{
			"build-tools/37.0.0",
			ANDROID_URL + "build-tools_r37_windows.zip",
			"e9c97e26b5b5678002e9d3fed632c841ae62d99f",
		},
		{
			"platforms/android-36",
			ANDROID_URL + "platform-36_r02.zip",
			"2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576",
		},
		{
			"ndk/30.0.16248370",
			ANDROID_URL + "android-ndk-r30-windows.zip",
			"9bf167a1985fa7d4a036186b78f702eab9179408",
		},
		{
			JRE_DIR_NAME,
			JRE_URL + "OpenJDK21U-jre_x64_windows_hotspot_21.0.13.1_2.zip",
			"e15ee1e54a5a3b38027a09cedfa87bc3348d7dd3ce50866dd3d9671d7fffc6c1",
		},
	}
} else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .arm64 {
		JRE_PACKAGE :: Package {
			JRE_DIR_NAME,
			JRE_URL + "OpenJDK21U-jre_aarch64_mac_hotspot_21.0.13.1_2.tar.gz",
			"848feb1906c7de79de4f8391636042193fbd46eff86e26299506c4656f62c260",
		}
	} else {
		JRE_PACKAGE :: Package {
			JRE_DIR_NAME,
			JRE_URL + "OpenJDK21U-jre_x64_mac_hotspot_21.0.13.1_2.tar.gz",
			"10cee6ba4cd83fd4613a3f0bb3ef9dddd68c68d5f3ccfcc7e456707c9e1eafe0",
		}
	}

	PACKAGES :: [?]Package {
		{
			"platform-tools",
			ANDROID_URL + "platform-tools_r37.0.3-darwin.zip",
			"d48920e2650321710b4d15d3acd9e277d59cd55b",
		},
		{
			"build-tools/37.0.0",
			ANDROID_URL + "build-tools_r37_macosx.zip",
			"eb080751b2b2028eb3604f571027d6f7b3c46321",
		},
		{
			"platforms/android-36",
			ANDROID_URL + "platform-36_r02.zip",
			"2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576",
		},
		{
			"ndk/30.0.16248370",
			ANDROID_URL + "android-ndk-r30-darwin.zip",
			"c060be96767eefbb8e0a27796d6f43115fc1a0c4",
		},
		JRE_PACKAGE,
	}
} else {
	when ODIN_ARCH == .arm64 {
		JRE_PACKAGE :: Package {
			JRE_DIR_NAME,
			JRE_URL + "OpenJDK21U-jre_aarch64_linux_hotspot_21.0.13.1_2.tar.gz",
			"52bc58323d9266538a6361a3cf8365fc1186dd9510d7f33f623681c4aabb7e72",
		}
	} else {
		JRE_PACKAGE :: Package {
			JRE_DIR_NAME,
			JRE_URL + "OpenJDK21U-jre_x64_linux_hotspot_21.0.13.1_2.tar.gz",
			"18f44fab9065217f3ba61d0eef8a7b5f3c3713aa7293001b0d4ac10ede3850f0",
		}
	}

	PACKAGES :: [?]Package {
		{
			"platform-tools",
			ANDROID_URL + "platform-tools_r37.0.3-linux.zip",
			"e1579b288a7ae4e9bc28dedec6a154d78b3c04ed",
		},
		{
			"build-tools/37.0.0",
			ANDROID_URL + "build-tools_r37_linux.zip",
			"70954e99f4c3d9d46ee70fa32624672fe7cd6ebe",
		},
		{
			"platforms/android-36",
			ANDROID_URL + "platform-36_r02.zip",
			"2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576",
		},
		{
			"ndk/30.0.16248370",
			ANDROID_URL + "android-ndk-r30-linux.zip",
			"5107f898313790e449e87eee2183d9a20602dee9",
		},
		JRE_PACKAGE,
	}
}

path_join :: proc(parts: []string) -> string {
	p, err := os.join_path(parts, allocator = context.allocator)
	fmt.ensuref(err == nil, "Failed joining path: %v", err)
	return p
}

Download :: struct {
	file: ^os.File,
	sha1_context: sha1.Context,
	sha256_context: sha2.Context_256,
	write_failed: bool,
	percent_shown: int,
}

download_write :: proc "c" (
	buffer: [^]byte,
	size: c.size_t,
	nitems: c.size_t,
	outstream: rawptr,
) -> c.size_t {
	context = runtime.default_context()
	download := (^Download)(outstream)
	data := buffer[:size * nitems]

	if _, write_err := os.write(download.file, data); write_err != nil {
		download.write_failed = true
		return curl.WRITEFUNC_ERROR
	}

	sha1.update(&download.sha1_context, data)
	sha2.update(&download.sha256_context, data)
	return size * nitems
}

download_progress :: proc "c" (
	clientp: rawptr,
	dltotal: curl.off_t,
	dlnow: curl.off_t,
	ultotal: curl.off_t,
	ulnow: curl.off_t,
) -> c.int {
	context = runtime.default_context()
	download := (^Download)(clientp)

	if dltotal <= 0 {
		return 0
	}

	percent := int(dlnow * 100 / dltotal)

	if percent != download.percent_shown {
		download.percent_shown = percent
		fmt.printf("\r    %v%% of %v MB", percent, dltotal / (1024 * 1024))
	}

	return 0
}

download_file :: proc(
	url: string,
	dest_path: string,
) -> (
	sha1_hex: string,
	sha256_hex: string,
	ok: bool,
) {
	file, open_err := os.open(dest_path, { .Write, .Create, .Trunc })

	if open_err != nil {
		fmt.eprintfln("Failed creating %v. Error: %v", dest_path, open_err)
		return
	}

	download := Download {
		file = file,
		percent_shown = -1,
	}

	sha1.init(&download.sha1_context)
	sha2.init_256(&download.sha256_context)

	handle := curl.easy_init()

	if handle == nil {
		fmt.eprintln("Failed starting curl")
		os.close(file)
		return
	}

	curl.easy_setopt(handle, .URL, strings.clone_to_cstring(url, context.temp_allocator))
	curl.easy_setopt(handle, .FOLLOWLOCATION, c.long(1))
	curl.easy_setopt(handle, .FAILONERROR, c.long(1))
	curl.easy_setopt(handle, .WRITEFUNCTION, download_write)
	curl.easy_setopt(handle, .WRITEDATA, &download)
	curl.easy_setopt(handle, .NOPROGRESS, c.long(0))
	curl.easy_setopt(handle, .XFERINFOFUNCTION, download_progress)
	curl.easy_setopt(handle, .XFERINFODATA, &download)

	perform_res := curl.easy_perform(handle)
	curl.easy_cleanup(handle)
	os.close(file)
	fmt.println()

	if perform_res != .E_OK {
		fmt.eprintfln("Failed downloading %v. curl error: %v", url, curl.easy_strerror(perform_res))
		return
	}

	sha1_digest: [sha1.DIGEST_SIZE]u8
	sha256_digest: [sha2.DIGEST_SIZE_256]u8
	sha1.final(&download.sha1_context, sha1_digest[:])
	sha2.final(&download.sha256_context, sha256_digest[:])
	sha1_hex = string(hex.encode(sha1_digest[:], context.allocator))
	sha256_hex = string(hex.encode(sha256_digest[:], context.allocator))
	return sha1_hex, sha256_hex, true
}

extract_tar_gz :: proc(tar_gz_path: string, dest_dir: string) -> bool {
	TAR_BLOCK_SIZE :: 512
	TAR_TYPE_FILE :: '0'
	TAR_TYPE_FILE_OLD :: 0
	TAR_TYPE_SYMLINK :: '2'
	TAR_TYPE_DIRECTORY :: '5'
	TAR_TYPE_GNU_LONG_NAME :: 'L'
	TAR_TYPE_PAX_HEADER :: 'x'

	Tar_Header :: struct #packed {
		name: [100]u8,
		mode: [8]u8,
		uid: [8]u8,
		gid: [8]u8,
		size: [12]u8,
		modified_time: [12]u8,
		checksum: [8]u8,
		type: u8,
		link_name: [100]u8,
		magic: [6]u8,
		version: [2]u8,
		user_name: [32]u8,
		group_name: [32]u8,
		device_major: [8]u8,
		device_minor: [8]u8,
		prefix: [155]u8,
		padding: [12]u8,
	}

	#assert(size_of(Tar_Header) == TAR_BLOCK_SIZE)

	tar_string :: proc(field: []u8) -> string {
		return strings.truncate_to_byte(string(field), 0)
	}

	tar_octal :: proc(field: []u8) -> int {
		value: int

		for digit in field {
			if digit < '0' || digit > '7' {
				if value != 0 {
					break
				}

				continue
			}

			value = value * 8 + int(digit - '0')
		}

		return value
	}

	tar_gz, read_err := os.read_entire_file(tar_gz_path, context.allocator)

	if read_err != nil {
		fmt.eprintfln("Failed reading %v. Error: %v", tar_gz_path, read_err)
		return false
	}

	defer delete(tar_gz)
	tar: [dynamic]u8
	defer delete(tar)

	if gzip_err := deflate.decompress_gzip(&tar, tar_gz); gzip_err != nil {
		fmt.eprintfln("Failed unpacking %v. Error: %v", tar_gz_path, gzip_err)
		return false
	}

	tar_pos: int
	long_name: string

	for tar_pos + TAR_BLOCK_SIZE <= len(tar) {
		header := (^Tar_Header)(&tar[tar_pos])
		tar_pos += TAR_BLOCK_SIZE

		if header.name[0] == 0 {
			break
		}

		size := tar_octal(header.size[:])
		data_blocks_size := (size + TAR_BLOCK_SIZE - 1) / TAR_BLOCK_SIZE * TAR_BLOCK_SIZE

		if tar_pos + size > len(tar) {
			fmt.eprintfln("%v is cut short", tar_gz_path)
			return false
		}

		data := tar[tar_pos:][:size]
		tar_pos += data_blocks_size

		if header.type == TAR_TYPE_GNU_LONG_NAME {
			long_name = tar_string(data)
			continue
		}

		if header.type == TAR_TYPE_PAX_HEADER {
			records := string(data)

			for len(records) > 0 {
				length_end := strings.index(records, " ")

				if length_end == -1 {
					break
				}

				record_length: int

				for digit in records[:length_end] {
					record_length = record_length * 10 + int(digit - '0')
				}

				if record_length <= length_end || record_length > len(records) {
					break
				}

				record := records[length_end + 1:record_length - 1]

				if strings.has_prefix(record, "path=") {
					long_name = record[len("path="):]
				}

				records = records[record_length:]
			}

			continue
		}

		name := tar_string(header.name[:])
		prefix := tar_string(header.prefix[:])

		if prefix != "" {
			name = fmt.tprintf("%v/%v", prefix, name)
		}

		if long_name != "" {
			name = long_name
			long_name = ""
		}

		top_dir_end := strings.index(name, "/")

		if top_dir_end == -1 || top_dir_end == len(name) - 1 {
			continue
		}

		if strings.contains(name, "..") {
			fmt.eprintfln("Refusing to extract %v from %v", name, tar_gz_path)
			return false
		}

		dest_path := path_join({dest_dir, name[top_dir_end + 1:]})

		switch header.type {
		case TAR_TYPE_DIRECTORY:
			os.make_directory_all(dest_path)

		case TAR_TYPE_SYMLINK:
			dest_parent, _ := os.split_path(dest_path)
			os.make_directory_all(dest_parent)
			os.remove(dest_path)
			link_target := tar_string(header.link_name[:])

			if symlink_err := os.symlink(link_target, dest_path); symlink_err != nil {
				fmt.eprintfln("Failed creating symlink %v. Error: %v", dest_path, symlink_err)
				return false
			}

		case TAR_TYPE_FILE, TAR_TYPE_FILE_OLD:
			dest_parent, _ := os.split_path(dest_path)
			os.make_directory_all(dest_parent)

			if write_err := os.write_entire_file(dest_path, data); write_err != nil {
				fmt.eprintfln("Failed writing %v. Error: %v", dest_path, write_err)
				return false
			}

			mode := tar_octal(header.mode[:])

			if mode & 0o111 != 0 {
				os.change_mode(dest_path, os.perm_number(mode & 0o777))
			}
		}
	}

	return true
}

extract_zip :: proc(zip_path: string, dest_dir: string) -> bool {
	Zip_End_Of_Central_Directory :: struct #packed {
		signature: u32le,
		disk_number: u16le,
		central_directory_disk: u16le,
		entries_on_disk: u16le,
		entries_total: u16le,
		central_directory_size: u32le,
		central_directory_offset: u32le,
		comment_length: u16le,
	}

	Zip_Central_File_Header :: struct #packed {
		signature: u32le,
		version_made_by: u16le,
		version_needed: u16le,
		flags: u16le,
		compression_method: u16le,
		modified_time: u16le,
		modified_date: u16le,
		crc32: u32le,
		compressed_size: u32le,
		uncompressed_size: u32le,
		name_length: u16le,
		extra_length: u16le,
		comment_length: u16le,
		disk_number_start: u16le,
		internal_attributes: u16le,
		external_attributes: u32le,
		local_header_offset: u32le,
	}

	Zip_Local_File_Header :: struct #packed {
		signature: u32le,
		version_needed: u16le,
		flags: u16le,
		compression_method: u16le,
		modified_time: u16le,
		modified_date: u16le,
		crc32: u32le,
		compressed_size: u32le,
		uncompressed_size: u32le,
		name_length: u16le,
		extra_length: u16le,
	}

	ZIP_END_OF_CENTRAL_DIRECTORY_SIGNATURE :: 0x06054b50
	ZIP_CENTRAL_FILE_HEADER_SIGNATURE :: 0x02014b50
	ZIP_LOCAL_FILE_HEADER_SIGNATURE :: 0x04034b50
	ZIP_COMPRESSION_STORED :: 0
	ZIP_COMPRESSION_DEFLATE :: 8
	ZIP_MADE_BY_UNIX :: 3
	ZIP_UNIX_FILE_TYPE_MASK :: 0o170000
	ZIP_UNIX_SYMLINK :: 0o120000

	zip_file, open_err := os.open(zip_path)

	if open_err != nil {
		fmt.eprintfln("Failed opening %v. Error: %v", zip_path, open_err)
		return false
	}

	defer os.close(zip_file)
	zip_size, _ := os.file_size(zip_file)

	MAX_COMMENT_SIZE :: 65535
	tail_size := min(zip_size, size_of(Zip_End_Of_Central_Directory) + MAX_COMMENT_SIZE)
	tail := make([]u8, tail_size)
	defer delete(tail)

	if _, tail_err := os.read_at(zip_file, tail, zip_size - tail_size); tail_err != nil {
		fmt.eprintfln("Failed reading %v. Error: %v", zip_path, tail_err)
		return false
	}

	end: Zip_End_Of_Central_Directory
	end_found: bool

	#reverse for _, tail_idx in tail {
		if tail_idx + size_of(end) > len(tail) {
			continue
		}

		end = (^Zip_End_Of_Central_Directory)(&tail[tail_idx])^

		if end.signature == ZIP_END_OF_CENTRAL_DIRECTORY_SIGNATURE {
			end_found = true
			break
		}
	}

	if !end_found {
		fmt.eprintfln("%v is not a zip file", zip_path)
		return false
	}

	central_directory := make([]u8, end.central_directory_size)
	defer delete(central_directory)

	_, central_directory_err := os.read_at(
		zip_file,
		central_directory,
		i64(end.central_directory_offset),
	)

	if central_directory_err != nil {
		fmt.eprintfln("Failed reading %v. Error: %v", zip_path, central_directory_err)
		return false
	}

	compressed: [dynamic]u8
	uncompressed: [dynamic]u8
	defer delete(compressed)
	defer delete(uncompressed)
	central_directory_pos: int

	for _ in 0..<end.entries_total {
		if central_directory_pos + size_of(Zip_Central_File_Header) > len(central_directory) {
			fmt.eprintfln("%v has a broken central directory", zip_path)
			return false
		}

		header := (^Zip_Central_File_Header)(&central_directory[central_directory_pos])^

		if header.signature != ZIP_CENTRAL_FILE_HEADER_SIGNATURE {
			fmt.eprintfln("%v has a broken central directory", zip_path)
			return false
		}

		name_start := central_directory_pos + size_of(Zip_Central_File_Header)
		name := string(central_directory[name_start:][:header.name_length])

		central_directory_pos = name_start +
			int(header.name_length) +
			int(header.extra_length) +
			int(header.comment_length)

		top_dir_end := strings.index(name, "/")

		if top_dir_end == -1 || top_dir_end == len(name) - 1 {
			continue
		}

		if strings.contains(name, "..") {
			fmt.eprintfln("Refusing to extract %v from %v", name, zip_path)
			return false
		}

		dest_path := path_join({dest_dir, name[top_dir_end + 1:]})

		if strings.has_suffix(name, "/") {
			os.make_directory_all(dest_path)
			continue
		}

		dest_parent, _ := os.split_path(dest_path)
		os.make_directory_all(dest_parent)

		local_header: Zip_Local_File_Header

		_, local_header_err := os.read_at(
			zip_file,
			([^]u8)(&local_header)[:size_of(local_header)],
			i64(header.local_header_offset),
		)

		if local_header_err != nil || local_header.signature != ZIP_LOCAL_FILE_HEADER_SIGNATURE {
			fmt.eprintfln("%v has a broken entry: %v", zip_path, name)
			return false
		}

		data_offset := i64(header.local_header_offset) +
			size_of(Zip_Local_File_Header) +
			i64(local_header.name_length) +
			i64(local_header.extra_length)

		resize(&compressed, int(header.compressed_size))

		if _, data_err := os.read_at(zip_file, compressed[:], data_offset); data_err != nil {
			fmt.eprintfln("Failed reading %v from %v. Error: %v", name, zip_path, data_err)
			return false
		}

		data: []u8

		switch header.compression_method {
		case ZIP_COMPRESSION_STORED:
			data = compressed[:]

		case ZIP_COMPRESSION_DEFLATE:
			clear(&uncompressed)

			inflate_err := deflate.decompress_raw(
				&uncompressed,
				compressed[:],
				int(header.uncompressed_size),
			)

			if inflate_err != nil {
				fmt.eprintfln("Failed unpacking %v from %v. Error: %v", name, zip_path, inflate_err)
				return false
			}

			data = uncompressed[:]

		case:
			fmt.eprintfln(
				"%v in %v uses unsupported compression method %v",
				name,
				zip_path,
				header.compression_method,
			)

			return false
		}

		if hash.crc32(data) != u32(header.crc32) {
			fmt.eprintfln("%v in %v is corrupt. The checksum does not match.", name, zip_path)
			return false
		}

		unix_mode: u32

		if header.version_made_by >> 8 == ZIP_MADE_BY_UNIX {
			unix_mode = u32(header.external_attributes) >> 16
		}

		if unix_mode & ZIP_UNIX_FILE_TYPE_MASK == ZIP_UNIX_SYMLINK {
			os.remove(dest_path)

			if symlink_err := os.symlink(string(data), dest_path); symlink_err != nil {
				fmt.eprintfln("Failed creating symlink %v. Error: %v", dest_path, symlink_err)
				return false
			}

			continue
		}

		if write_err := os.write_entire_file(dest_path, data); write_err != nil {
			fmt.eprintfln("Failed writing %v. Error: %v", dest_path, write_err)
			return false
		}

		if unix_mode & 0o111 != 0 {
			os.change_mode(dest_path, os.perm_number(int(unix_mode & 0o777)))
		}
	}

	return true
}

main :: proc() {
	sdk_dir, _ := os.clean_path(SDK_DIR, context.allocator)

	fmt.printfln(
		"This downloads the Android SDK and NDK from Google, and a Java runtime (Eclipse " +
		"Temurin), into %v\n" +
		"By continuing you accept the Android SDK terms and licenses:\n" +
		"    https://developer.android.com/studio/terms\n" +
		"Continue? (y/N)",
		sdk_dir,
	)

	answer_buf: [16]u8
	answer_len, _ := os.read(os.stdin, answer_buf[:])
	answer := strings.trim_space(string(answer_buf[:max(answer_len, 0)]))

	if answer != "y" && answer != "Y" {
		fmt.println("Setup cancelled.")
		os.exit(1)
	}

	os.make_directory_all(sdk_dir)
	fmt.ensuref(os.is_directory(sdk_dir), "Failed creating %v", sdk_dir)
	curl.global_init(curl.GLOBAL_DEFAULT)

	for pkg in PACKAGES {
		dest_dir := path_join({sdk_dir, pkg.dest_dir})

		if os.is_directory(dest_dir) {
			fmt.printfln("%v is already there, skipping it", dest_dir)
			continue
		}

		archive_name := pkg.url[strings.last_index(pkg.url, "/") + 1:]
		archive_path := path_join({sdk_dir, archive_name})
		fmt.printfln("Downloading %v", pkg.url)
		sha1_hex, sha256_hex, download_ok := download_file(pkg.url, archive_path)

		if !download_ok {
			os.exit(1)
		}

		checksum := sha1_hex

		if len(pkg.checksum) == len(sha256_hex) {
			checksum = sha256_hex
		}

		if checksum != pkg.checksum {
			fmt.eprintfln(
				"%v has the wrong checksum. Expected %v, got %v.",
				archive_path,
				pkg.checksum,
				checksum,
			)

			os.exit(1)
		}

		dest_parent, _ := os.split_path(dest_dir)
		os.make_directory_all(dest_parent)
		unpack_dir := fmt.tprintf("%v_unpacking", dest_dir)
		os.remove_all(unpack_dir)
		fmt.printfln("Unpacking into %v", dest_dir)
		extract_ok: bool

		if strings.has_suffix(archive_name, ".tar.gz") {
			extract_ok = extract_tar_gz(archive_path, unpack_dir)
		} else {
			extract_ok = extract_zip(archive_path, unpack_dir)
		}

		if !extract_ok {
			os.exit(1)
		}

		rename_err := os.rename(unpack_dir, dest_dir)
		fmt.ensuref(rename_err == nil, "Failed creating %v. Error: %v", dest_dir, rename_err)
		os.remove(archive_path)
	}

	curl.global_cleanup()

	home_dir, _ := os.user_home_dir(context.allocator)
	keystore_dir := path_join({home_dir, ".android"})
	keystore_path := path_join({keystore_dir, "debug.keystore"})

	if !os.exists(keystore_path) {
		fmt.printfln("Creating debug keystore %v", keystore_path)
		os.make_directory_all(keystore_dir)

		when ODIN_OS == .Darwin {
			keytool_path := path_join({sdk_dir, JRE_DIR_NAME, "Contents", "Home", "bin", "keytool"})
		} else {
			keytool_path := path_join({sdk_dir, JRE_DIR_NAME, "bin", "keytool"})
		}

		keytool_process, keytool_start_err := os.process_start({
			command = {
				keytool_path,
				"-genkeypair",
				"-keystore", keystore_path,
				"-storepass", "android",
				"-alias", "androiddebugkey",
				"-keypass", "android",
				"-keyalg", "RSA",
				"-keysize", "2048",
				"-validity", "10000",
				"-dname", "CN=Android Debug,O=Android,C=US",
			},
			stdout = os.stdout,
			stderr = os.stderr,
		})

		keytool_ok := keytool_start_err == nil

		if keytool_ok {
			keytool_state, keytool_wait_err := os.process_wait(keytool_process)
			keytool_ok = keytool_wait_err == nil && keytool_state.exit_code == 0
		}

		if !keytool_ok {
			fmt.eprintfln("Failed creating the debug keystore using %v", keytool_path)

			os.exit(1)
		}
	}

	fmt.printfln(
		"Setup done. The Android SDK and NDK are in %v. build_android will find them there.",
		sdk_dir,
	)
}
