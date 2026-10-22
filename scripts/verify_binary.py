"""Reject incompatible or unexpectedly linked plugin Mach-O artifacts."""

import hashlib
import struct
import sys
from pathlib import Path


def check(path: Path, expected_name: str | None = None) -> None:
    data = path.read_bytes()
    if len(data) < 32:
        raise ValueError("Not a Mach-O binary")
    magic, cpu, subtype, filetype, count, commands_size, _, _ = struct.unpack_from(
        "<8I", data
    )
    if (magic, cpu, subtype, filetype) != (0xFEEDFACF, 0x100000C, 0, 6):
        raise ValueError("Expected a thin arm64 (not arm64e) MH_DYLIB")
    commands_end = 32 + commands_size
    if commands_end > len(data):
        raise ValueError("Truncated load commands")
    offset = 32
    dependencies = []
    install_name = None
    minimum_os = None
    signature = False
    initializer = False

    for _ in range(count):
        if offset + 8 > commands_end:
            raise ValueError("Truncated load command")
        command, size = struct.unpack_from("<2I", data, offset)
        if size < 8 or offset + size > commands_end:
            raise ValueError("Invalid load command length")
        if command in (0xC, 0xD, 0x80000018, 0x8000001F, 0x80000023):
            string_offset = struct.unpack_from("<I", data, offset + 8)[0]
            value = data[offset + string_offset : offset + size].split(b"\0", 1)[0].decode()
            if command == 0xD:
                install_name = value
            else:
                dependencies.append(value)
        elif command == 0x32:  # LC_BUILD_VERSION
            platform, minimum_os = struct.unpack_from("<2I", data, offset + 8)
            if platform != 2:
                raise ValueError("Binary is not built for physical iOS devices")
        elif command == 0x25:  # LC_VERSION_MIN_IPHONEOS
            minimum_os = struct.unpack_from("<I", data, offset + 8)[0]
        elif command == 0x1D:  # LC_CODE_SIGNATURE
            start, length = struct.unpack_from("<2I", data, offset + 8)
            signature = length > 0 and start + length <= len(data)
        elif command == 0x19:  # LC_SEGMENT_64
            sections = struct.unpack_from("<I", data, offset + 64)[0]
            for index in range(sections):
                section = offset + 72 + index * 80
                if section + 80 > offset + size:
                    raise ValueError("Truncated section table")
                name = data[section : section + 16].rstrip(b"\0")
                section_size = struct.unpack_from("<Q", data, section + 40)[0]
                if name == b"__mod_init_func" and section_size:
                    initializer = True
        offset += size

    allowed = {
        "/System/Library/Frameworks/UIKit.framework/UIKit",
        "/System/Library/Frameworks/Foundation.framework/Foundation",
        "/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
        "/System/Library/Frameworks/Security.framework/Security",
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        "/usr/lib/libobjc.A.dylib",
        "/usr/lib/libSystem.B.dylib",
    }
    if offset != commands_end:
        raise ValueError("Load command table does not match header")
    if not dependencies or set(dependencies) - allowed:
        raise ValueError(f"Unexpected dependencies: {dependencies}")
    if install_name != f"@rpath/{expected_name or path.name}":
        raise ValueError(f"Unexpected install name: {install_name}")
    if minimum_os != 14 << 16:
        raise ValueError(f"Unexpected minimum iOS version: {minimum_os}")
    if not signature or not initializer:
        raise ValueError("Missing code-signature data or load initializer")
    print("Verified: arm64 iOS dylib, iOS 14.0 minimum, system dependencies only.")
    print("Verified: @rpath install name, load initializer and code-signature data.")
    print("Device loading and playback still require the iPhone test.")
    print(f"SHA256: {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    check(Path(sys.argv[1]))
