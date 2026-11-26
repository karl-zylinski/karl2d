// This program builds a Karl2D game as an Android version.
package karl2d_build_android_tool

import "core:fmt"
import os "core:os"
import "core:strconv"
import "core:strings"

ABI :: struct {
	name: string,
	target: string,
}

ABIS :: [?]ABI {
	{ "arm64-v8a", "linux_arm64" },
	{ "armeabi-v7a", "linux_arm32" },
	{ "x86_64", "linux_amd64" },
	{ "x86", "linux_i386" },
}

DEFAULT_ABIS :: "arm64-v8a"
DEFAULT_MINIMUM_OS_VERSION :: "29"
LIB_NAME :: "main"
ACTIVITY_NAME :: "org.odin_lang.OdinActivity"

USAGE :: `Usage: 'odin run karl2d/build_android -- directory_name -extra -parameters' Any extra parameter that start with a dash will be passed on to Odin compiler.

Special parameters (goes after the '--'):
	-run         Install the APK on a connected Android device (USB debugging must be on).
	-setup       Download Android SDKs and Java and put them in the 'build_android/sdk' folder. build_android will use these automatically.
	-abis:<list> Comma separated list of CPU types to build for. Available: arm64-v8a (default), armeabi-v7a, x86_64, x86.
	-assets:<path> A file, directory or pattern such as 'sprites/*.png', relative to 'directory_name'. It is put into the APK at the same relative path, so the game can load it using that path. Can be used multiple times.

If 'directory_name/android/AndroidManifest.xml' exists, then it is used. A default manifest is used otherwise.

Example: 'odin run karl2d/build_android -- my_game -o:speed -run'`

SETUP_SDK_DIR :: #directory + "sdk"
SETUP_HINT :: "Run 'odin run karl2d/build_android/setup' to download the SDK, NDK and Java."

path_join :: proc(parts: []string) -> string {
	p, err := os.join_path(parts, allocator = context.allocator)
	fmt.ensuref(err == nil, "Failed joining path: %v", err)
	return p
}

run_command :: proc(command: []string) -> bool {
	process, start_err := os.process_start({
		command = command,
		stdin = os.stdin,
		stdout = os.stdout,
		stderr = os.stderr,
	})

	if start_err != nil {
		fmt.eprintfln("Failed running '%v'. Error: %v", command[0], start_err)
		return false
	}

	state, wait_err := os.process_wait(process)

	if wait_err != nil {
		fmt.eprintfln("Failed waiting for '%v'. Error: %v", command[0], wait_err)
		return false
	}

	return state.exit_code == 0
}

main :: proc() {
	print_usage: bool

	if len(os.args) < 2 {
		print_usage = true
	}

	dir: string
	sdk_param: string
	ndk_param: string
	abis_param := DEFAULT_ABIS
	run_on_device: bool
	has_minimum_os_version: bool
	has_keystore_param: bool
	build_params: [dynamic]string
	bundle_params: [dynamic]string
	asset_patterns: [dynamic]string

	for a in os.args[1:] {
		if a == "-help" || a == "--help" {
			print_usage = true
		} else if strings.has_prefix(a, "-abis:") {
			abis_param = a[len("-abis:"):]
		} else if strings.has_prefix(a, "-android-sdk:") {
			sdk_param = a[len("-android-sdk:"):]
		} else if strings.has_prefix(a, "-android-ndk:") {
			ndk_param = a[len("-android-ndk:"):]
		} else if strings.has_prefix(a, "-assets:") {
			append(&asset_patterns, a[len("-assets:"):])
		} else if a == "-run" {
			run_on_device = true
		} else if strings.has_prefix(a, "-minimum-os-version:") {
			has_minimum_os_version = true
			append(&build_params, a)
			append(&bundle_params, a)
		} else if strings.has_prefix(a, "-android-keystore") {
			has_keystore_param = true
			append(&bundle_params, a)
		} else if strings.has_prefix(a, "-") {
			append(&build_params, a)
		} else {
			dir = a
		}
	}

	if dir == "" {
		print_usage = true
	}

	if print_usage {
		fmt.eprintln(USAGE)
		return
	}

	if !has_minimum_os_version {
		minimum_os_version := fmt.tprintf("-minimum-os-version:%v", DEFAULT_MINIMUM_OS_VERSION)
		append(&build_params, minimum_os_version)
		append(&bundle_params, minimum_os_version)
	}

	if !has_keystore_param {
		setup_keystore_path := path_join({SETUP_SDK_DIR, "debug.keystore"})

		if os.exists(setup_keystore_path) {
			append(&bundle_params, fmt.tprintf("-android-keystore:%v", setup_keystore_path))
			append(&bundle_params, "-android-keystore-alias:androiddebugkey")
		}

		append(&bundle_params, "-android-keystore-password:android")
	}

	MANIFEST_TEMPLATE :: #load("android_templates/AndroidManifest.xml", string)

	dir_handle, dir_err := os.open(dir)
	fmt.ensuref(dir_err == nil, "Failed finding directory %v. Error: %v", dir, dir_err)

	dir_stat, dir_stat_err := os.fstat(dir_handle, context.allocator)

	fmt.ensuref(
		dir_stat_err == nil,
		"Failed checking status of directory %v. Error: %v",
		dir,
		dir_stat_err,
	)

	fmt.ensuref(dir_stat.type == .Directory, "%v is not a directory!", dir)

	dir_name := dir_stat.name

	home_dir, _ := os.user_home_dir(context.allocator)

	when ODIN_OS == .Windows {
		default_sdk_path := path_join({
			os.get_env("LOCALAPPDATA", context.allocator),
			"Android",
			"Sdk",
		})
	} else when ODIN_OS == .Darwin {
		default_sdk_path := path_join({home_dir, "Library", "Android", "sdk"})
	} else {
		default_sdk_path := path_join({home_dir, "Android", "Sdk"})
	}

	sdk_candidates := [?]string {
		SETUP_SDK_DIR,
		sdk_param,
		os.get_env("ODIN_ANDROID_SDK", context.allocator),
		os.get_env("ANDROID_HOME", context.allocator),
		default_sdk_path,
	}

	sdk_path: string

	for candidate in sdk_candidates {
		if candidate != "" && os.is_directory(candidate) {
			sdk_path = candidate
			break
		}
	}

	if sdk_path == "" {
		fmt.eprintfln(
			"Could not find the Android SDK. Looked in:\n" +
			"- %v\n" +
			"- The -android-sdk parameter (%v)\n" +
			"- The environment variable ODIN_ANDROID_SDK (%v)\n" +
			"- The environment variable ANDROID_HOME (%v)\n" +
			"- %v\n" +
			SETUP_HINT,
			sdk_candidates[0],
			sdk_candidates[1] == "" ? "not given" : sdk_candidates[1],
			sdk_candidates[2] == "" ? "not set" : sdk_candidates[2],
			sdk_candidates[3] == "" ? "not set" : sdk_candidates[3],
			sdk_candidates[4],
		)

		os.exit(1)
	}

	newest_sdk_ndk_path: string
	newest_sdk_ndk_version: [3]int
	sdk_ndk_dir := path_join({sdk_path, "ndk"})
	sdk_ndks, _ := os.read_all_directory_by_path(sdk_ndk_dir, context.allocator)

	for sdk_ndk in sdk_ndks {
		if sdk_ndk.type != .Directory {
			continue
		}

		version: [3]int
		version_parts := strings.split(sdk_ndk.name, ".", context.allocator)

		for part, part_idx in version_parts {
			if part_idx < len(version) {
				version[part_idx], _ = strconv.parse_int(part)
			}
		}

		is_newer := newest_sdk_ndk_path == ""

		for component, component_idx in version {
			if component != newest_sdk_ndk_version[component_idx] {
				is_newer ||= component > newest_sdk_ndk_version[component_idx]
				break
			}
		}

		if is_newer {
			newest_sdk_ndk_path = sdk_ndk.fullpath
			newest_sdk_ndk_version = version
		}
	}

	ndk_candidates := [?]string {
		sdk_path == SETUP_SDK_DIR ? newest_sdk_ndk_path : "",
		ndk_param,
		os.get_env("ODIN_ANDROID_NDK", context.allocator),
		os.get_env("ANDROID_NDK_HOME", context.allocator),
		newest_sdk_ndk_path,
	}

	ndk_path: string

	for candidate in ndk_candidates {
		if candidate != "" && os.is_directory(candidate) {
			ndk_path = candidate
			break
		}
	}

	if ndk_path == "" {
		fmt.eprintfln(
			"Could not find the Android NDK. Looked in:\n" +
			"- %v\n" +
			"- The -android-ndk parameter (%v)\n" +
			"- The environment variable ODIN_ANDROID_NDK (%v)\n" +
			"- The environment variable ANDROID_NDK_HOME (%v)\n" +
			"- %v\n" +
			SETUP_HINT,
			path_join({SETUP_SDK_DIR, "ndk"}),
			ndk_candidates[1] == "" ? "not given" : ndk_candidates[1],
			ndk_candidates[2] == "" ? "not set" : ndk_candidates[2],
			ndk_candidates[3] == "" ? "not set" : ndk_candidates[3],
			sdk_ndk_dir,
		)

		os.exit(1)
	}

	os.set_env("ODIN_ANDROID_SDK", sdk_path)
	os.set_env("ODIN_ANDROID_NDK", ndk_path)
	fmt.printfln("Android SDK: %v\nAndroid NDK: %v", sdk_path, ndk_path)

	when ODIN_OS == .Darwin {
		setup_java_home := path_join({SETUP_SDK_DIR, "jre", "Contents", "Home"})
	} else {
		setup_java_home := path_join({SETUP_SDK_DIR, "jre"})
	}

	if os.is_directory(setup_java_home) {
		PATH_SEPARATOR :: ";" when ODIN_OS == .Windows else ":"
		setup_java_bin := path_join({setup_java_home, "bin"})
		path_env := os.get_env("PATH", context.allocator)
		os.set_env("JAVA_HOME", setup_java_home)
		os.set_env("PATH", fmt.tprintf("%v%v%v", setup_java_bin, PATH_SEPARATOR, path_env))
		fmt.printfln("Java: %v", setup_java_home)
	} else {
		_, _, _, java_err := os.process_exec(
			{ command = { "java", "-version" } },
			context.allocator,
		)

		if java_err != nil {
			fmt.eprintln("Could not find Java. It is needed for signing the apk.\n" + SETUP_HINT)
			os.exit(1)
		}
	}

	bin_android_dir := path_join({dir, "bin", "android"})
	app_dir := path_join({dir, "build", "android", "app"})
	lib_dir := path_join({app_dir, "lib"})
	os.remove_all(lib_dir)

	os.make_directory_all(bin_android_dir)
	fmt.ensuref(os.is_directory(bin_android_dir), "Failed creating %v", bin_android_dir)

	os.make_directory_all(app_dir)
	fmt.ensuref(os.is_directory(app_dir), "Failed creating %v", app_dir)

	assets_dir := path_join({app_dir, "assets"})
	os.remove_all(assets_dir)

	for pattern in asset_patterns {
		matches, glob_err := os.glob(path_join({dir, pattern}), context.allocator)
		fmt.ensuref(glob_err == nil, "Failed finding assets %v. Error: %v", pattern, glob_err)

		num_copied := 0

		for match in matches {
			if !os.exists(match) {
				continue
			}

			relative_path, relative_err := os.get_relative_path(dir, match, context.allocator)

			fmt.ensuref(
				relative_err == nil,
				"Failed finding path of %v relative to %v. Error: %v",
				match,
				dir,
				relative_err,
			)

			fmt.ensuref(
				!strings.has_prefix(relative_path, ".."),
				"Asset %v is outside %v. Assets must be inside the game directory.",
				match,
				dir,
			)

			asset_path := path_join({assets_dir, relative_path})
			asset_parent_dir, _ := os.split_path(asset_path)
			os.make_directory_all(asset_parent_dir)

			copy_err: os.Error

			if os.is_directory(match) {
				copy_err = os.copy_directory_all(asset_path, match)
			} else {
				copy_err = os.copy_file(asset_path, match)
			}

			fmt.ensuref(copy_err == nil, "Failed copying asset %v. Error: %v", match, copy_err)
			num_copied += 1
		}

		fmt.ensuref(num_copied > 0, "No assets found for -assets:%v", pattern)
	}

	manifest: string
	custom_manifest_path := path_join({dir, "android", "AndroidManifest.xml"})

	if os.exists(custom_manifest_path) {
		custom_manifest, custom_manifest_err := os.read_entire_file(
			custom_manifest_path,
			context.allocator,
		)

		fmt.ensuref(
			custom_manifest_err == nil,
			"Failed reading %v. Error: %v",
			custom_manifest_path,
			custom_manifest_err,
		)

		manifest = string(custom_manifest)
	} else {
		package_name_builder := strings.builder_make(context.allocator)
		strings.write_string(&package_name_builder, "com.karl2d.")

		for r, r_idx in dir_name {
			switch r {
			case 'a'..='z':
				strings.write_rune(&package_name_builder, r)

			case 'A'..='Z':
				strings.write_rune(&package_name_builder, r - 'A' + 'a')

			case '0'..='9':
				if r_idx == 0 {
					strings.write_rune(&package_name_builder, '_')
				}

				strings.write_rune(&package_name_builder, r)

			case:
				strings.write_rune(&package_name_builder, '_')
			}
		}

		manifest, _ = strings.replace_all(
			MANIFEST_TEMPLATE,
			"KARL2D_PACKAGE_NAME",
			strings.to_string(package_name_builder),
			context.allocator,
		)

		manifest, _ = strings.replace_all(
			manifest,
			"KARL2D_APP_LABEL",
			dir_name,
			context.allocator,
		)
	}

	PACKAGE_ATTRIBUTE :: "package=\""
	package_start := strings.index(manifest, PACKAGE_ATTRIBUTE)
	fmt.ensuref(package_start != -1, "The Android manifest has no package attribute")
	package_start += len(PACKAGE_ATTRIBUTE)
	package_len := strings.index(manifest[package_start:], "\"")
	fmt.ensuref(package_len != -1, "The Android manifest has a broken package attribute")
	package_name := manifest[package_start:][:package_len]

	manifest_path := path_join({app_dir, "AndroidManifest.xml"})
	write_manifest_err := os.write_entire_file(manifest_path, manifest)

	fmt.ensuref(
		write_manifest_err == nil,
		"Failed writing %v. Error: %v",
		manifest_path,
		write_manifest_err,
	)

	abi_names := strings.split(abis_param, ",", context.allocator)

	for abi_name in abi_names {
		target: string

		for abi in ABIS {
			if abi.name == abi_name {
				target = abi.target
			}
		}

		fmt.ensuref(target != "", "Unknown ABI: %v. See -help for a list.", abi_name)

		abi_dir := path_join({lib_dir, abi_name})
		os.make_directory_all(abi_dir)
		fmt.ensuref(os.is_directory(abi_dir), "Failed creating %v", abi_dir)

		build_command: [dynamic]string

		append(&build_command, ..[]string {
			"odin",
			"build",
			dir,
			fmt.tprintf("-out:%v", path_join({abi_dir, "lib" + LIB_NAME + ".so"})),
			fmt.tprintf("-target:%v", target),
			"-subtarget:android",
			"-build-mode:shared",
		})

		append(&build_command, ..build_params[:])

		if !run_command(build_command[:]) {
			fmt.eprintfln("Build failed for ABI %v.", abi_name)
			os.exit(1)
		}
	}

	apk_path := path_join({bin_android_dir, fmt.tprintf("%v.apk", dir_name)})
	bundle_command: [dynamic]string

	append(&bundle_command, ..[]string {
		"odin",
		"bundle",
		"android",
		app_dir,
		fmt.tprintf("-out:%v", apk_path),
	})

	append(&bundle_command, ..bundle_params[:])

	if !run_command(bundle_command[:]) {
		fmt.eprintln("Bundling the apk failed.")
		os.exit(1)
	}

	fmt.printfln("Success. The apk is at `%v`.", apk_path)

	if run_on_device {
		adb_path := path_join({sdk_path, "platform-tools", "adb"})

		if !run_command({ adb_path, "install", "-r", apk_path }) {
			fmt.eprintln("Installing the apk using adb failed.")
			os.exit(1)
		}

		activity := fmt.tprintf("%v/%v", package_name, ACTIVITY_NAME)

		if !run_command({ adb_path, "shell", "am", "start", "-n", activity }) {
			fmt.eprintln("Starting the app using adb failed.")
			os.exit(1)
		}
	}
}
