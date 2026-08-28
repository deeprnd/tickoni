import argparse
import csv
import gzip
import json
import struct
import subprocess
import tempfile
import urllib.request
from pathlib import Path
from typing import Callable, Dict, List, Optional, Set, Tuple

import netaddr
import zstandard

# The following constants much be matching in the C source code.
FD_GUI_GEOIP_ZSTD_COMPRESSION_LEVEL = 19
FD_GUI_GEOIP_ZSTD_WINDOW_LOG = 23
FD_GUI_GEOIP_MAX_CITY_NAME_SZ = 80
FD_GUI_GEOIP_MAX_CITY_CNT = 160000
FD_GUI_GEOIP_MAX_COUNTRY_CNT = 254
FD_GUI_GEOIP_DBIP_MAX_NODES = 2**24

VERSION_MK_PATH = Path("src/app/firedancer/version.mk")

assert zstandard.ZstdCompressionParameters.from_level(
    FD_GUI_GEOIP_ZSTD_COMPRESSION_LEVEL
).window_log == FD_GUI_GEOIP_ZSTD_WINDOW_LOG


def convert_dbip(input_path: Path, output_path: Path) -> None:
    country_codes = set()
    city_to_country = {}
    city_names = {}  # city to cidrs
    with open(input_path, "r", encoding="utf-8") as r:
        reader = csv.DictReader(
            r,
            fieldnames=[
                "ip_range_start",
                "ip_range_end",
                "country_code",
                "state1",
                "state2",
                "city",
                "postcode",
                "latitude",
                "longitude",
                "timezone",
            ],
        )
        for row in reader:
            try:
                netaddr.IPAddress(row["ip_range_start"], version=4)
                netaddr.IPAddress(row["ip_range_end"], version=4)
            except netaddr.AddrFormatError:
                continue
            assert len(row["country_code"]) == 2
            country_codes.add(row["country_code"])

            city_cstr = row["city"].encode("ascii", "replace").decode("ascii") + "\0"
            assert len(city_cstr) <= FD_GUI_GEOIP_MAX_CITY_NAME_SZ
            city_to_country[city_cstr] = row["country_code"]

            city_names.setdefault(city_cstr, [])
            city_names[city_cstr].extend(
                netaddr.iprange_to_cidrs(row["ip_range_start"], row["ip_range_end"])
            )

    assert len(country_codes) <= FD_GUI_GEOIP_MAX_COUNTRY_CNT, (
        f"Too many country codes ({len(country_codes)}) to fit in a byte (max 254)"
    )
    country_to_index = {cc: idx for idx, cc in enumerate(sorted(country_codes))}

    assert len(city_names) <= FD_GUI_GEOIP_MAX_CITY_CNT, f"Too many city names ({len(city_names)})"
    city_names_coalesced = {cy: list(netaddr.cidr_merge(ips)) for cy, ips in city_names.items()}
    city_to_index = {cy: idx for idx, cy in enumerate(sorted(city_names.keys()))}

    with open(output_path, "wb") as f:
        f.write(struct.pack("<Q", len(country_codes)))
        for cc in sorted(country_codes):
            f.write(cc.encode("ascii"))

        f.write(struct.pack("<Q", len(city_names)))
        for cy in sorted(city_names.keys()):
            f.write(cy.encode("ascii"))

        records = sum(len(ips) for _, ips in city_names_coalesced.items())
        assert records <= FD_GUI_GEOIP_DBIP_MAX_NODES
        f.write(struct.pack("<Q", records))

        for cy, ips in city_names_coalesced.items():
            for ip in ips:
                f.write(struct.pack(">I", ip.network))
                f.write(struct.pack("<B", ip.prefixlen))
                f.write(struct.pack("<B", country_to_index[city_to_country[cy]]))
                f.write(struct.pack("<I", city_to_index[cy]))

    print(f"Converted {records} records with {len(country_codes)} country codes")


def update_db(url: str, output_path: Path, processor: Callable[[Path, Path], None]) -> None:
    req = urllib.request.Request(
        url=url,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"
        },
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)
        with urllib.request.urlopen(req) as f:
            with gzip.open(f, "rb") as f_in:
                (tmpdir_path / "db.csv").write_bytes(f_in.read())

        processor(tmpdir_path / "db.csv", tmpdir_path / "db.bin")
        compressor = zstandard.ZstdCompressor(level=FD_GUI_GEOIP_ZSTD_COMPRESSION_LEVEL)
        output_path.write_bytes(compressor.compress((tmpdir_path / "db.bin").read_bytes()))

def main():
    print("Updating dbip.bin (this will take ~2-5 minutes)")
    dbip_url = "https://github.com/sapics/ip-location-db/releases/download/latest/dbip-city-ipv4.csv.gz"
    update_db(dbip_url, Path('src/disco/gui/dbip.bin.zst'), convert_dbip)

def read_tickoni_version() -> Tuple[int, int, int, List[str]]:
    lines = VERSION_MK_PATH.read_text(encoding="utf-8").splitlines()
    parsed: Dict[str, int] = {}
    for line in lines:
        if ":=" not in line:
            continue
        key, raw_val = line.split(":=", 1)
        key = key.strip()
        if key in ("VERSION_MAJOR", "VERSION_MINOR", "VERSION_PATCH"):
            parsed[key] = int(raw_val.strip())

    missing = [k for k in ("VERSION_MAJOR", "VERSION_MINOR", "VERSION_PATCH") if k not in parsed]
    if missing:
        raise RuntimeError(f"version.mk missing required keys: {', '.join(missing)}")

    return parsed["VERSION_MAJOR"], parsed["VERSION_MINOR"], parsed["VERSION_PATCH"], lines


def write_tickoni_version(major: int, minor: int, patch: int, original_lines: List[str]) -> None:
    replacements = {
        "VERSION_MAJOR": str(major),
        "VERSION_MINOR": str(minor),
        "VERSION_PATCH": str(patch),
    }

    seen: Set[str] = set()
    out_lines: List[str] = []
    for line in original_lines:
        if ":=" not in line:
            out_lines.append(line)
            continue
        key, _ = line.split(":=", 1)
        key = key.strip()
        if key in replacements:
            out_lines.append(f"{key} := {replacements[key]}")
            seen.add(key)
        else:
            out_lines.append(line)

    for key in ("VERSION_MAJOR", "VERSION_MINOR", "VERSION_PATCH"):
        if key not in seen:
            out_lines.append(f"{key} := {replacements[key]}")

    VERSION_MK_PATH.write_text("\n".join(out_lines) + "\n", encoding="utf-8")


def maybe_commit_dbip() -> None:
    subprocess.run(["git", "add", "src/disco/gui/dbip.bin.zst"], check=True)
    result = subprocess.run(["git", "diff", "--cached", "--quiet", "--", "src/disco/gui/dbip.bin.zst"])
    if result.returncode != 0:
        print("Creating commit and updating IP database")
        subprocess.run(["git", "commit", "-m", "Update IP databases"], check=True)
    else:
        print("No changes to geoip db. Skipping commit")


def create_release_commit_and_tags(version: str, create_legacy_alias: bool) -> None:
    tickoni_tag = f"tickoni-v{version}"
    legacy_tag = f"v{version}"

    print(f"Creating Tickoni release commit and tags: {tickoni_tag}" + (f", {legacy_tag}" if create_legacy_alias else ""))

    subprocess.run(["git", "add", str(VERSION_MK_PATH)], check=True)
    subprocess.run(["git", "commit", "-m", f"Increment Tickoni version to {tickoni_tag}"], check=True)
    subprocess.run(["git", "tag", tickoni_tag], check=True)
    if create_legacy_alias:
        subprocess.run(["git", "tag", legacy_tag], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Update Tickoni release metadata and optional geoip payload.")
    parser.add_argument(
        "--skip-dbip",
        action="store_true",
        help="Skip dbip.bin.zst refresh and related commit.",
    )
    parser.add_argument(
        "--no-legacy-tag-alias",
        action="store_true",
        help="Do not add legacy v<semver> tag alias alongside tickoni-v<semver>.",
    )
    args = parser.parse_args()

    if not args.skip_dbip:
        print("Updating dbip.bin.zst (this will take ~2-5 minutes)")
        dbip_url = "https://github.com/sapics/ip-location-db/raw/refs/heads/main/dbip-city/dbip-city-ipv4.csv.gz"
        update_db(dbip_url, Path("src/disco/gui/dbip.bin.zst"), convert_dbip)
        maybe_commit_dbip()

    major, minor, patch, original_lines = read_tickoni_version()
    patch += 1
    write_tickoni_version(major, minor, patch, original_lines)

    version = f"{major}.{minor}.{patch}"
    create_release_commit_and_tags(version, create_legacy_alias=not args.no_legacy_tag_alias)

    summary = {
        "version": version,
        "tag": f"tickoni-v{version}",
        "legacy_tag_alias": None if args.no_legacy_tag_alias else f"v{version}",
    }
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
