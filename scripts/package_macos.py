#!/usr/bin/env python3
"""
Package self-contained macOS Application Bundle (`Lightning.app`),
Apple Disk Image (`Lightning.dmg`), and zip archive (`Lightning-macos.zip`).
"""

import os
import shutil
import subprocess
import sys

APP_NAME = "Lightning"
BUNDLE_ID = "com.lightning.editor"
VERSION = "0.1.0"
BUILD_NUM = "1"

INFO_PLIST_CONTENT = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>{APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>{APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>{APP_NAME}.icns</string>
    <key>CFBundleIdentifier</key>
    <string>{BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>{APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>{VERSION}</string>
    <key>CFBundleVersion</key>
    <string>{BUILD_NUM}</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSPrefersDisplaySafeAreaCompatibilityMode</key>
    <false/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Source Code and Text</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.text</string>
                <string>public.plain-text</string>
                <string>public.source-code</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
"""

def ensure_icon():
    icns_path = "assets/icons/Lightning.icns"
    if not os.path.exists(icns_path):
        print("⚡ Icon not found. Running scripts/build_icon.py...")
        subprocess.run(["uv", "run", "--with", "pillow", "python3", "scripts/build_icon.py"], check=True)
    if not os.path.exists(icns_path):
        raise FileNotFoundError(f"Failed to find or generate {icns_path}")
    return icns_path

def build_app_bundle():
    print("⚡ Assembling Lightning.app bundle...")

    icns_path = ensure_icon()

    app_dir = "zig-out/Lightning.app"
    contents_dir = os.path.join(app_dir, "Contents")
    macos_dir = os.path.join(contents_dir, "MacOS")
    resources_dir = os.path.join(contents_dir, "Resources")
    lib_dir = os.path.join(contents_dir, "lib")
    plugins_dir = os.path.join(contents_dir, "plugins")

    # Clean existing bundle
    if os.path.exists(app_dir):
        shutil.rmtree(app_dir)

    os.makedirs(macos_dir, exist_ok=True)
    os.makedirs(resources_dir, exist_ok=True)
    os.makedirs(lib_dir, exist_ok=True)
    os.makedirs(plugins_dir, exist_ok=True)

    # 1. Info.plist & PkgInfo
    with open(os.path.join(contents_dir, "Info.plist"), "w") as f:
        f.write(INFO_PLIST_CONTENT)

    with open(os.path.join(contents_dir, "PkgInfo"), "w") as f:
        f.write("APPL????")

    # 2. Main Executable
    src_bin = "zig-out/bin/lightning"
    if not os.path.exists(src_bin):
        src_bin = "zig-out/bin/skia-window"
    if not os.path.exists(src_bin):
        raise FileNotFoundError(f"Neither zig-out/bin/lightning nor zig-out/bin/skia-window found! Run 'zig build' first.")

    target_bin = os.path.join(macos_dir, APP_NAME)
    shutil.copy2(src_bin, target_bin)
    os.chmod(target_bin, 0o755)

    # Alias symlink in MacOS
    alias_bin = os.path.join(macos_dir, "skia-window")
    if not os.path.exists(alias_bin):
        os.symlink(APP_NAME, alias_bin)

    # 3. Resources (Icon)
    shutil.copy2(icns_path, os.path.join(resources_dir, f"{APP_NAME}.icns"))

    # 4. Libraries (libSkiaSharp.dylib & libeditor_app.dylib)
    skia_dylib = "zig-out/lib/libSkiaSharp.dylib"
    if not os.path.exists(skia_dylib):
        skia_dylib = "vendor/skiasharp/lib/libSkiaSharp.dylib"
    target_skia = os.path.join(lib_dir, "libSkiaSharp.dylib")

    # Determine host architecture for universal binary thinning (e.g. arm64 or x86_64)
    arch = subprocess.check_output(["uname", "-m"], text=True).strip()
    try:
        # Thin fat binary to native host arch to save ~8MB
        subprocess.run(["lipo", "-thin", arch, skia_dylib, "-output", target_skia], check=True)
        print(f"   Thinned libSkiaSharp.dylib to native {arch} (saved ~8 MB)")
    except Exception:
        shutil.copy2(skia_dylib, target_skia)

    app_dylib = "zig-out/lib/libeditor_app.dylib"
    target_app_dylib = os.path.join(lib_dir, "libeditor_app.dylib")
    if os.path.exists(app_dylib):
        shutil.copy2(app_dylib, target_app_dylib)
    else:
        print("Warning: zig-out/lib/libeditor_app.dylib not found!")

    # 5. Extension Plugins
    if os.path.exists("zig-out/plugins"):
        for f in os.listdir("zig-out/plugins"):
            if f.endswith(".dylib"):
                shutil.copy2(os.path.join("zig-out/plugins", f), os.path.join(plugins_dir, f))
        print(f"   Copied {len(os.listdir(plugins_dir))} plugins into {plugins_dir}")

    # Strip local symbols (-x) from all binaries and dylibs in bundle
    print("⚡ Stripping local symbols (-x) for optimized footprint...")
    binaries_to_strip = [target_bin, target_app_dylib, target_skia]
    for f in os.listdir(plugins_dir):
        if f.endswith(".dylib"):
            binaries_to_strip.append(os.path.join(plugins_dir, f))
    for b in binaries_to_strip:
        if os.path.exists(b):
            try:
                subprocess.run(["strip", "-x", b], check=False, stderr=subprocess.DEVNULL)
            except Exception:
                pass

    # 6. Ad-hoc Code Sign bundle
    print("⚡ Signing Lightning.app with ad-hoc signature...")
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", app_dir], check=True)
    subprocess.run(["codesign", "-vvv", "--deep", "--strict", app_dir], check=True)

    print(f"✅ Successfully assembled {app_dir}")
    return app_dir

def build_dmg(app_dir):
    print("⚡ Building Lightning.dmg...")
    dmg_path = "zig-out/Lightning.dmg"
    staging_dir = "zig-out/dmg_staging"

    if os.path.exists(dmg_path):
        os.remove(dmg_path)
    if os.path.exists(staging_dir):
        shutil.rmtree(staging_dir)

    os.makedirs(staging_dir, exist_ok=True)
    # Copy Lightning.app to staging using ditto
    subprocess.run(["ditto", app_dir, os.path.join(staging_dir, f"{APP_NAME}.app")], check=True)

    # Create /Applications symlink
    os.symlink("/Applications", os.path.join(staging_dir, "Applications"))

    # Create UDZO compressed DMG
    subprocess.run([
        "hdiutil", "create",
        "-volname", APP_NAME,
        "-srcfolder", staging_dir,
        "-ov",
        "-format", "UDZO",
        dmg_path
    ], check=True)

    shutil.rmtree(staging_dir)
    dmg_sz = os.path.getsize(dmg_path)
    print(f"✅ Successfully created {dmg_path} ({dmg_sz / (1024 * 1024):.2f} MB)")

def build_zip(app_dir):
    print("⚡ Packaging Lightning-macos.zip...")
    zip_path = "zig-out/Lightning-macos.zip"
    if os.path.exists(zip_path):
        os.remove(zip_path)

    subprocess.run([
        "ditto", "-c", "-k",
        "--keepParent",
        app_dir,
        zip_path
    ], check=True)

    zip_sz = os.path.getsize(zip_path)
    print(f"✅ Successfully created {zip_path} ({zip_sz / (1024 * 1024):.2f} MB)")

def verify_package():
    print("⚡ Verifying packaged application launch...")
    app_bin = "zig-out/Lightning.app/Contents/MacOS/Lightning"
    cmd = [app_bin, "--frames", "2", "--bench"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Packaging self-test failed with code {res.returncode}:\n{res.stderr}", file=sys.stderr)
        sys.exit(res.returncode)
    print("✅ Packaged Lightning.app launched and verified successfully!")

def main():
    app_dir = build_app_bundle()
    build_dmg(app_dir)
    build_zip(app_dir)
    verify_package()
    print("\n🎉 Lightning macOS Packaging Complete!")
    print("   - Bundle:      zig-out/Lightning.app")
    print("   - Disk Image:  zig-out/Lightning.dmg")
    print("   - Zip Archive: zig-out/Lightning-macos.zip")

if __name__ == "__main__":
    main()
