"""Create an allowlisted source archive and local release assets. Does not publish."""

import hashlib
import re
import shutil
import sys
import zipfile
from pathlib import Path

from verify_binary import check


def setting(makefile: str, name: str) -> str:
    match = re.search(rf"^{name}\s*:=\s*(\S+)\s*$", makefile, re.MULTILINE)
    if not match:
        raise ValueError(f"Missing {name}")
    return match.group(1)


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    makefile = (root / "Makefile").read_text(encoding="utf-8")
    name = setting(makefile, "TWEAK_NAME")
    version = setting(makefile, "PACKAGE_VERSION")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Unexpected release name or version")
    required = ["README.md", "README.zh-CN.md", "LICENSE", "ACKNOWLEDGMENTS.md",
                "Makefile", f"{name}.plist", "build.ps1", ".gitignore", ".gitattributes"]
    files = [root / item for item in required]
    for folder in ["Sources", "Tests", "scripts", "docs", ".github"]:
        files.extend(p for p in (root / folder).rglob("*")
                     if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc")
    files = sorted(set(files))
    secret_pattern = re.compile(r"\bsk-[A-Za-z0-9_-]{20,}|\bgh[pousr]_[A-Za-z0-9_]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")
    for path in files:
        if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root):
            raise ValueError(f"Missing or external source path: {path.name}")
        if path.suffix.lower() in {".dylib", ".ipa", ".p12", ".pem", ".mobileprovision", ".log"}:
            raise ValueError(f"Unexpected source artifact: {path.name}")
        text = path.read_text(encoding="utf-8")
        unexpected = [hit for hit in secret_pattern.finditer(text) if not (
            path.relative_to(root).as_posix() == "Tests/SettingsStoreTests.m" and
            hit.group() == "sk-" + "TEST-fixture-only-123")]
        if unexpected:
            # Identify the file, never echo any matched credential.
            raise ValueError(f"Credential-shaped value in {path.relative_to(root)}")
    license_text = (root / "LICENSE").read_text(encoding="utf-8")
    if "MIT License" not in license_text and "GNU GENERAL PUBLIC LICENSE" not in license_text:
        raise ValueError("Select and finalize LICENSE before making a release")
    binary = root / "dist" / f"{name}.dylib"
    check(binary)
    output = root / "release" / f"v{version}"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{name}-{version}-source.zip"
    prefix = f"{name}-{version}"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
        for path in files:
            entry = zipfile.ZipInfo(f"{prefix}/{path.relative_to(root).as_posix()}", date_time=(2026, 10, 22, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (0o100644 << 16)
            entry.compress_type = zipfile.ZIP_DEFLATED
            package.writestr(entry, path.read_bytes())
    with zipfile.ZipFile(archive) as package:
        if package.testzip() is not None or len(package.namelist()) != len(files):
            raise ValueError("Source archive verification failed")
        for path in files:
            if package.read(f"{prefix}/{path.relative_to(root).as_posix()}") != path.read_bytes():
                raise ValueError(f"Source archive mismatch: {path.name}")
    release_binary = output / f"{name}-{version}.dylib"
    shutil.copyfile(binary, release_binary)
    sums = "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
                   for path in [archive, release_binary])
    (output / "SHA256SUMS.txt").write_text(sums, encoding="utf-8", newline="\n")
    print(f"Prepared {len(files)} source files and release assets: {output}")
    print("Nothing was uploaded. Device-test status is recorded separately in docs/TESTING.md.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"Release preparation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
