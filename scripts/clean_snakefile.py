#!/usr/bin/env python3
"""
Clean a Snakefile (or any Python-like script) of hidden non-UTF8 bytes and
replace non-breaking spaces with normal spaces.

Usage:
    python3 clean_snakefile.py Snakefile_hybrid_SRA_chatgpt
"""
# verifyi after cleaning with:
# grep -nP '[\x80-\xFF]' Snakefile_hybrid_SRA_chatgpt

import sys
import pathlib

def clean_file(filename: str):
    p = pathlib.Path(filename)

    try:
        # Read as raw bytes, ignore bad sequences
        raw = p.read_bytes()
        text = raw.decode("utf-8", errors="ignore")
    except Exception as e:
        print(f"[ERROR] Could not read {filename}: {e}")
        return

    # Replace non-breaking spaces (U+00A0) with normal spaces
    clean_text = text.replace("\u00A0", " ")

    # Write back clean UTF-8
    p.write_text(clean_text, encoding="utf-8")
    print(f"[INFO] Cleaned file saved: {filename}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 clean_snakefile.py <filename>")
        sys.exit(1)

    clean_file(sys.argv[1])

