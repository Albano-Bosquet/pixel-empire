extends "res://tests/test_case.gd"
## Main-menu updater: version comparison and picking the installer asset.


func test_newer_versions_compare_greater() -> void:
	assert_eq(UpdateChecker.compare_versions("1.1.0", "1.0.0"), 1, "minor bump is newer")
	assert_eq(UpdateChecker.compare_versions("1.10.0", "1.9.3"), 1, "numeric, not lexical")
	assert_eq(UpdateChecker.compare_versions("v1.0.0", "1.0.0"), 0, "leading v is ignored")
	assert_eq(UpdateChecker.compare_versions("1.0", "1.0.0"), 0, "missing parts count as 0")
	assert_eq(UpdateChecker.compare_versions("0.7.0", "1.0.0"), -1, "older is smaller")


func test_only_the_same_version_plays_online() -> void:
	assert_true(UpdateChecker.same_version("1.4.0", "1.4.0"), "same build on PC and Android")
	assert_true(UpdateChecker.same_version("1.4", "v1.4.0"), "same version, different spelling")
	assert_true(not UpdateChecker.same_version("1.4.0", "1.3.2"), "different versions are rejected")
	assert_true(not UpdateChecker.same_version("", "1.4.0"), "a client that sends no version is rejected")


func test_parse_release_finds_installer() -> void:
	var release := {"tag_name": "v1.2.0", "assets": [
		{"name": "notes.txt", "browser_download_url": "https://x/notes.txt"},
		{"name": "PixelEmpire_Setup_1.2.0.exe", "browser_download_url": "https://x/setup.exe"}]}
	var info := UpdateChecker.parse_release(release, "PixelEmpire_Setup_", ".exe")
	assert_eq(info.get("version", ""), "1.2.0", "version from the tag")
	assert_eq(info.get("url", ""), "https://x/setup.exe", "installer asset url")


func test_release_without_installer_is_ignored() -> void:
	var info := UpdateChecker.parse_release({"tag_name": "v2.0.0", "assets": []}, "PixelEmpire_Setup_", ".exe")
	assert_true(info.is_empty(), "no installer -> nothing to offer")
