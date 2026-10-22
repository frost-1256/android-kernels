#!/usr/bin/env python3
"""Build a dtbo.img (Android DTBO partition image) for spacewar.

The stock spacewar dtbo.img contains overlays: each entry is an FDT with
``fragment@N`` nodes and ``__fixups__`` that are applied by ABL on top of a
base tree.  The base tree for this board lives in vendor_boot.img (the
"Yupik SoC" DTB), and entries 28/29 are the Yupik QRD overlays that add the
rm692e5 panel and focaltech touch nodes.

A mainline kernel needs a complete tree, not a vendor overlay, so its DTB is
installed as the vendor_boot base DTB instead.  The dtbo partition then has
to be emptied (``create`` with no ``--dtb``) or ABL would apply the vendor
overlays to a foreign tree.

This tool keeps the exact byte layout of the stock image:

    offset 0        : table header (32 bytes, big endian)
    offset 32       : table entries (32 bytes each)
    offset 1024     : first DTB, entries stored back to back
    ...             : padding up to the partition size

Usage:
    pack_dtbo.py create  OUT [--dtb FILE ...]
    pack_dtbo.py replace OUT --stock STOCK --index N --dtb FILE [--index N ...]
"""

import argparse
import struct
import sys

DTBO_MAGIC = 0xD7B7AB1E
HEADER_SIZE = 32
ENTRY_SIZE = 32
ENTRIES_OFFSET = 32
DATA_OFFSET = 1024
PAGE_SIZE = 4096
PARTITION_SIZE = 25165824  # BOARD_DTBO_PARTITION_SIZE of the stock ROM


def parse_header(blob):
    fields = struct.unpack(">8I", blob[:HEADER_SIZE])
    magic, total, hdr, esz, count, eoff, psize, version = fields
    if magic != DTBO_MAGIC:
        raise ValueError("not a dtbo image (magic %#x)" % magic)
    return {
        "total_size": total,
        "header_size": hdr,
        "entry_size": esz,
        "count": count,
        "entries_offset": eoff,
        "page_size": psize,
        "version": version,
    }


def parse_entries(blob, header):
    entries = []
    for i in range(header["count"]):
        off = header["entries_offset"] + i * header["entry_size"]
        size, offset, dt_id, rev = struct.unpack(">4I", blob[off : off + 16])
        custom = struct.unpack(">4I", blob[off + 16 : off + 32])
        entries.append(
            {
                "size": size,
                "offset": offset,
                "id": dt_id,
                "rev": rev,
                "custom": custom,
                "data": blob[offset : offset + size],
            }
        )
    return entries


def build_image(entries, page_size=PAGE_SIZE, version=0):
    """Serialise entries back to back, starting at DATA_OFFSET."""
    out = bytearray()
    out += b"\0" * DATA_OFFSET
    table = bytearray()
    for entry in entries:
        offset = len(out)
        out += entry["data"]
        table += struct.pack(
            ">4I4I",
            len(entry["data"]),
            offset,
            entry.get("id", 0),
            entry.get("rev", 0),
            *(entry.get("custom", (0, 0, 0, 0))),
        )
    header = struct.pack(
        ">8I",
        DTBO_MAGIC,
        len(out),
        HEADER_SIZE,
        ENTRY_SIZE,
        len(entries),
        ENTRIES_OFFSET,
        page_size,
        version,
    )
    blob = bytearray(header)
    blob += table
    blob += out[DATA_OFFSET:]
    if len(blob) < PARTITION_SIZE:
        blob += b"\0" * (PARTITION_SIZE - len(blob))
    return bytes(blob)


def read_file(path):
    with open(path, "rb") as handle:
        return handle.read()


def cmd_create(args):
    entries = []
    for path in args.dtb:
        entries.append(
            {
                "data": read_file(path),
                "id": 0,
                "rev": 0,
                "custom": (0, 0, 0, 0),
            }
        )
    blob = build_image(entries)
    with open(args.output, "wb") as handle:
        handle.write(blob)
    print("wrote %s (%d entries, %d bytes)" % (args.output, len(entries), len(blob)))
    return 0


def cmd_replace(args):
    stock = read_file(args.stock)
    header = parse_header(stock)
    entries = parse_entries(stock, header)
    for index in args.index:
        if index < 0 or index >= len(entries):
            raise ValueError("index %d out of range (count %d)" % (index, len(entries)))
    dtb = read_file(args.dtb)
    for index in args.index:
        entries[index] = {
            "data": dtb,
            "id": 0,
            "rev": 0,
            "custom": (0, 0, 0, 0),
        }
    blob = build_image(
        entries, page_size=header["page_size"], version=header["version"]
    )
    with open(args.output, "wb") as handle:
        handle.write(blob)
    print(
        "wrote %s (%d entries, replaced %s, %d bytes)"
        % (args.output, len(entries), ",".join(str(i) for i in args.index), len(blob))
    )
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    create = sub.add_parser("create", help="build a dtbo from DTB files")
    create.add_argument("output")
    create.add_argument("--dtb", action="append", default=[])
    create.set_defaults(func=cmd_create)

    replace = sub.add_parser("replace", help="replace entries of a stock dtbo")
    replace.add_argument("output")
    replace.add_argument("--stock", required=True)
    replace.add_argument("--index", action="append", type=int, required=True)
    replace.add_argument("--dtb", required=True)
    replace.set_defaults(func=cmd_replace)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (OSError, ValueError) as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
