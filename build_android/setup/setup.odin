package karl2d_build_android_setup

import "base:runtime"
import "core:c"
import "core:compress/deflate"
import "core:crypto/legacy/sha1"
import "core:encoding/hex"
import "core:fmt"
import "core:hash"
import os "core:os"
import "core:strings"
import curl "vendor:curl"

USAGE :: `Usage: 'odin run karl2d/build_android/setup'

Downloads the Android SDK and NDK from Google into the 'android_sdk' folder inside
build_android. The build_android tool looks for them there.

Also creates the debug keystore ~/.android/debug.keystore if it is missing. That needs keytool,
which is part of the JDK. Building needs the JDK too.`

SDK_DIR :: #directory + "../android_sdk"
REPOSITORY_URL :: "https://dl.google.com/android/repository/"

Package :: struct {
	dest_dir: string,
	zip_name: string,
	sha1: string,
}

when ODIN_OS == .Windows {
	PACKAGES :: [?]Package {
		{
			"platform-tools",
			"platform-tools_r37.0.3-win.zip",
			"7fea85bc18d0480bc81d3603952d666f49496e5a",
		},
		{
			"build-tools/37.0.0",
			"build-tools_r37_windows.zip",
			"e9c97e26b5b5678002e9d3fed632c841ae62d99f",
		},
		{
			"platforms/android-36",
			"platform-36_r02.zip",
			"2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576",
		},
		{
			"ndk/30.0.16248370",
			"android-ndk-r30-windows.zip",
			"9bf167a1985fa7d4a036186b78f702eab9179408",
		},
	}
} else when ODIN_OS == .Darwin {
	PACKAGES :: [?]Package {
		{
			"platform-tools",
			"platform-tools_r37.0.3-darwin.zip",
			"d48920e2650321710b4d15d3acd9e277d59cd55b",
		},
		{
			"build-tools/37.0.0",
			"build-tools_r37_macosx.zip",
			"eb080751b2b2028eb3604f571027d6f7b3c46321",
		},
		{
			"platforms/android-36",
			"platform-36_r02.zip",
			"2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576",
		},
		{
			"ndk/30.0.16248370",
			"android-ndk-r30-darwin.zip",
			"c060be96767eefbb8e0a27796d6f43115fc1a0c4",
		},
	}
} else {
	PACKAGES :: [?]Package {
		{
			"platform-tools",
			"platform-tools_r37.0.3-linux.zip",
			"e1579b288a7ae4e9bc28dedec6a154d78b3c04ed",
		},
		{
			"build-tools/37.0.0",
			"build-tools_r37_linux.zip",
			"70954e99f4c3d9d46ee70fa32624672fe7cd6ebe",
		},
		{
			"platforms/android-36",
			"platform-36_r02.zip",
			"2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576",
		},
		{
			"ndk/30.0.16248370",
			"android-ndk-r30-linux.zip",
			"5107f898313790e449e87eee2183d9a20602dee9",
		},
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

download_file :: proc(url: string, dest_path: string) -> (sha1_hex: string, ok: bool) {
	file, open_err := os.open(dest_path, { .Write, .Create, .Trunc })

	if open_err != nil {
		fmt.eprintfln("Failed creating %v. Error: %v", dest_path, open_err)
		return "", false
	}

	download := Download {
		file = file,
		percent_shown = -1,
	}

	sha1.init(&download.sha1_context)

	handle := curl.easy_init()

	if handle == nil {
		fmt.eprintln("Failed starting curl")
		os.close(file)
		return "", false
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
		return "", false
	}

	sha1_digest: [sha1.DIGEST_SIZE]u8
	sha1.final(&download.sha1_context, sha1_digest[:])
	return string(hex.encode(sha1_digest[:], context.allocator)), true
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
	for a in os.args[1:] {
		if a == "-help" || a == "--help" {
			fmt.println(USAGE)
			return
		}
	}

	sdk_dir, _ := os.clean_path(SDK_DIR, context.allocator)

	fmt.printfln(
		"This downloads the Android SDK and NDK from Google into %v\n" +
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

		url := fmt.tprintf("%v%v", REPOSITORY_URL, pkg.zip_name)
		zip_path := path_join({sdk_dir, pkg.zip_name})
		fmt.printfln("Downloading %v", url)
		sha1_hex, download_ok := download_file(url, zip_path)

		if !download_ok {
			os.exit(1)
		}

		if sha1_hex != pkg.sha1 {
			fmt.eprintfln(
				"%v has the wrong checksum. Expected %v, got %v.",
				zip_path,
				pkg.sha1,
				sha1_hex,
			)

			os.exit(1)
		}

		unpack_dir := fmt.tprintf("%v_unpacking", dest_dir)
		os.remove_all(unpack_dir)
		fmt.printfln("Unpacking into %v", dest_dir)

		if !extract_zip(zip_path, unpack_dir) {
			os.exit(1)
		}

		rename_err := os.rename(unpack_dir, dest_dir)
		fmt.ensuref(rename_err == nil, "Failed creating %v. Error: %v", dest_dir, rename_err)
		os.remove(zip_path)
	}

	curl.global_cleanup()

	home_dir, _ := os.user_home_dir(context.allocator)
	keystore_dir := path_join({home_dir, ".android"})
	keystore_path := path_join({keystore_dir, "debug.keystore"})

	if !os.exists(keystore_path) {
		fmt.printfln("Creating debug keystore %v", keystore_path)
		os.make_directory_all(keystore_dir)

		keytool_process, keytool_start_err := os.process_start({
			command = {
				"keytool",
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
			fmt.eprintln(
				"Failed creating the debug keystore using keytool. keytool is part of the JDK, " +
				"which is also needed for building. Install a JDK and run this again.",
			)

			os.exit(1)
		}
	}

	fmt.printfln(
		"Setup done. The Android SDK and NDK are in %v. build_android will find them there.",
		sdk_dir,
	)
}
