#!/usr/bin/env python3
import os
import uuid

def gen_id():
    return uuid.uuid4().hex[:24].upper()

proj_dir = os.path.dirname(os.path.abspath(__file__))
root_dir = os.path.dirname(proj_dir)
xcode_dir = os.path.join(root_dir, "Constructor.xcodeproj")
os.makedirs(xcode_dir, exist_ok=True)

files = [
    ("AudioRingBuffer.swift", "source", "sourcecode.swift"),
    ("AudioEngineManager.swift", "source", "sourcecode.swift"),
    ("MetalRenderer.swift", "source", "sourcecode.swift"),
    ("InputManager_iOS.swift", "source", "sourcecode.swift"),
    ("GameMTKView_iOS.swift", "source", "sourcecode.swift"),
    ("GameView_iOS.swift", "source", "sourcecode.swift"),
    ("LibretroCore.swift", "source", "sourcecode.swift"),
    ("GameSession.swift", "source", "sourcecode.swift"),
    ("ConstructorApp_iOS.swift", "source", "sourcecode.swift"),
    ("Shaders.metal", "resource", "text"),
    ("ConstructorIOS-Bridging-Header.h", "header", "sourcecode.c.h"),
    ("libretro.h", "header", "sourcecode.c.h"),
    ("Constructor.zip", "resource", "archive.zip"),
    ("dosbox_pure_libretro_ios.dylib", "framework", "compiled.mach-o.dylib"),
    ("Assets.xcassets", "resource", "folder.assetcatalog"),
    ("Info.plist", "none", "text.plist.xml"),
    ("Constructor.entitlements", "none", "text.plist.entitlements")
]

file_entries = {}
for name, kind, file_type in files:
    f_id = gen_id()
    b_id = gen_id() if kind in ("source", "metal", "resource", "framework") else None
    file_entries[name] = {"f_id": f_id, "b_id": b_id, "kind": kind, "type": file_type}

target_id = gen_id()
project_id = gen_id()
main_group_id = gen_id()
sources_group_id = gen_id()
products_group_id = gen_id()
frameworks_group_id = gen_id()
product_ref_id = gen_id()

sources_phase_id = gen_id()
frameworks_phase_id = gen_id()
resources_phase_id = gen_id()
script_phase_id = gen_id()

config_debug_target = gen_id()
config_release_target = gen_id()
config_list_target = gen_id()

config_debug_proj = gen_id()
config_release_proj = gen_id()
config_list_proj = gen_id()

# PBXBuildFile entries
build_file_lines = []
for name, data in file_entries.items():
    if data["b_id"]:
        build_file_lines.append(f'\t\t{data["b_id"]} /* {name} in {data["kind"].capitalize()} */ = {{isa = PBXBuildFile; fileRef = {data["f_id"]} /* {name} */; }};')

# PBXFileReference entries
file_ref_lines = []
for name, data in file_entries.items():
    file_ref_lines.append(f'\t\t{data["f_id"]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {data["type"]}; name = "{name}"; path = "ConstructorIOS/{name}"; sourceTree = "<group>"; }};')

file_ref_lines.append(f'\t\t{product_ref_id} /* Constructor.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Constructor.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')

# Sources build phase
sources_phase_lines = []
for name, data in file_entries.items():
    if data["kind"] in ("source", "metal"):
        sources_phase_lines.append(f'\t\t\t\t{data["b_id"]} /* {name} in Sources */,')

# Resources build phase
resources_phase_lines = []
for name, data in file_entries.items():
    if data["kind"] in ("resource", "framework"):
        resources_phase_lines.append(f'\t\t\t\t{data["b_id"]} /* {name} in Resources */,')

# Children of sources group
group_children = []
for name, data in file_entries.items():
    group_children.append(f'\t\t\t\t{data["f_id"]} /* {name} */,')

pbxproj_content = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_lines)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_lines)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase_id} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group_id} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{sources_group_id} /* ConstructorIOS */,
\t\t\t\t{products_group_id} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{sources_group_id} /* ConstructorIOS */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(group_children)}
\t\t\t);
\t\t\tname = ConstructorIOS;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group_id} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{product_ref_id} /* Constructor.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target_id} /* Constructor */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {config_list_target} /* Build configuration list for PBXNativeTarget "Constructor" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase_id} /* Sources */,
\t\t\t\t{frameworks_phase_id} /* Frameworks */,
\t\t\t\t{resources_phase_id} /* Resources */,
\t\t\t\t{script_phase_id} /* Sign Embedded Dynamic Libraries */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Constructor;
\t\t\tproductName = Constructor;
\t\t\tproductReference = {product_ref_id} /* Constructor.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t\tDevelopmentTeam = "";
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {config_list_proj} /* Build configuration list for PBXProject "Constructor" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = es;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\tes,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group_id};
\t\t\tproductRefGroup = {products_group_id} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target_id} /* Constructor */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase_id} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(resources_phase_lines)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXShellScriptBuildPhase section */
\t\t{script_phase_id} /* Sign Embedded Dynamic Libraries */ = {{
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputFileListPaths = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t);
\t\t\tname = "Sign Embedded Dynamic Libraries";
\t\t\toutputFileListPaths = (
\t\t\t);
\t\t\toutputPaths = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = "if [ -n \\\"$EXPANDED_CODE_SIGN_IDENTITY\\\" ]; then\\n    find \\\"$TARGET_BUILD_DIR/$PRODUCT_NAME.app\\\" -name \\\"*.dylib\\\" -exec codesign --force --sign \\\"$EXPANDED_CODE_SIGN_IDENTITY\\\" --timestamp=none {{}} +\\nfi\\n";
\t\t}};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase_id} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(sources_phase_lines)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{config_debug_proj} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{config_release_proj} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{config_debug_target} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "ConstructorIOS/Constructor.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = "ConstructorIOS/Info.plist";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.margelenders.constructor;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "ConstructorIOS/ConstructorIOS-Bridging-Header.h";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{config_release_target} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "ConstructorIOS/Constructor.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = "ConstructorIOS/Info.plist";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.margelenders.constructor;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "ConstructorIOS/ConstructorIOS-Bridging-Header.h";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{config_list_proj} /* Build configuration list for PBXProject "Constructor" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{config_debug_proj} /* Debug */,
\t\t\t\t{config_release_proj} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{config_list_target} /* Build configuration list for PBXNativeTarget "Constructor" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{config_debug_target} /* Debug */,
\t\t\t\t{config_release_target} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

\t}};
\trootObject = {project_id} /* Project object */;
}}
"""

pbxproj_path = os.path.join(xcode_dir, "project.pbxproj")
with open(pbxproj_path, "w", encoding="utf-8") as f:
    f.write(pbxproj_content)

print(f"✅ Constructor.xcodeproj generado con éxito en: {xcode_dir}")
