#!/usr/bin/env python3
"""
Robust MyTaxa Database Downloader
Handles interruptions, resume capability, and proper progress tracking
"""

import os
import sys
import tarfile
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

MYTAXA_URL = "http://enve-omics.ce.gatech.edu/data/public_mytaxa/db.latest.tar.gz"
CHUNK_SIZE = 1024 * 1024  # 1 MB chunks

def download_with_resume(url, output_path, expected_size=None):
    """Download file with resume capability"""
    output_path = Path(output_path)
    temp_path = output_path.with_suffix(output_path.suffix + '.partial')
    
    start_byte = 0
    if temp_path.exists():
        start_byte = temp_path.stat().st_size
        print(f"Resuming download from {start_byte:,} bytes...")
    
    headers = {}
    if start_byte > 0:
        headers['Range'] = f'bytes={start_byte}-'
    
    try:
        req = Request(url, headers=headers)
        response = urlopen(req, timeout=60)
        
        if 'Content-Length' in response.headers:
            total_size = int(response.headers['Content-Length'])
            if start_byte > 0:
                total_size += start_byte
        elif expected_size:
            total_size = expected_size
        else:
            total_size = None
        
        mode = 'ab' if start_byte > 0 else 'wb'
        downloaded = start_byte
        
        with open(temp_path, mode) as f:
            print(f"Downloading MyTaxa database...")
            if total_size:
                print(f"Total size: {total_size / (1024**3):.2f} GB")
            
            while True:
                chunk = response.read(CHUNK_SIZE)
                if not chunk:
                    break
                
                f.write(chunk)
                downloaded += len(chunk)
                
                if total_size:
                    percent = (downloaded / total_size) * 100
                    gb_downloaded = downloaded / (1024**3)
                    gb_total = total_size / (1024**3)
                    print(f"\rProgress: {gb_downloaded:.2f}/{gb_total:.2f} GB ({percent:.1f}%)", end='', flush=True)
                else:
                    gb_downloaded = downloaded / (1024**3)
                    print(f"\rDownloaded: {gb_downloaded:.2f} GB", end='', flush=True)
        
        print()
        
        if output_path.exists():
            output_path.unlink()
        temp_path.rename(output_path)
        
        print(f"✓ Download complete: {output_path}")
        return True
        
    except (URLError, HTTPError, OSError) as e:
        print(f"\n✗ Download error: {e}")
        print(f"Partial download saved. Re-run to resume.")
        return False

def extract_tarball(tar_path, extract_to):
    """Extract tar.gz file"""
    print(f"\nExtracting archive...")
    
    try:
        with tarfile.open(tar_path, 'r:gz') as tar:
            members = tar.getmembers()
            total = len(members)
            
            for i, member in enumerate(members, 1):
                tar.extract(member, extract_to)
                if i % 100 == 0 or i == total:
                    print(f"\rExtracting: {i}/{total} files ({(i/total)*100:.1f}%)", end='', flush=True)
        
        print()
        print(f"✓ Extraction complete")
        return True
        
    except Exception as e:
        print(f"\n✗ Extraction error: {e}")
        return False

def verify_database(db_path):
    """Verify the database was extracted correctly"""
    db_path = Path(db_path)
    
    required_files = [
        'db/format.pl',
        'db/geneInfo.lib',
        'db/geneTaxon.lib',
        'db/ncbiNodes.lib',
        'db/ncbiSciNames.lib'
    ]
    
    print("\nVerifying database files...")
    all_present = True
    
    for rel_path in required_files:
        full_path = db_path / rel_path
        if full_path.exists():
            size_mb = full_path.stat().st_size / (1024**2)
            print(f"✓ {rel_path} ({size_mb:.1f} MB)")
        else:
            print(f"✗ Missing: {rel_path}")
            all_present = False
    
    return all_present

def main():
    if len(sys.argv) < 2:
        print("Usage: python download_mytaxa_robust.py <output_directory>")
        sys.exit(1)
    
    output_dir = Path(sys.argv[1])
    output_dir.mkdir(parents=True, exist_ok=True)
    
    archive_path = output_dir / "db.latest.tar.gz"
    
    print("=" * 70)
    print("MyTaxa Database Downloader")
    print("=" * 70)
    
    if not archive_path.exists() or archive_path.stat().st_size < 1000000:
        success = download_with_resume(MYTAXA_URL, archive_path, expected_size=15000000000)
        if not success:
            sys.exit(1)
    else:
        print(f"Archive already exists: {archive_path}")
    
    if not (output_dir / 'db').exists():
        success = extract_tarball(archive_path, output_dir)
        if not success:
            sys.exit(1)
    else:
        print("\nDatabase already extracted")
    
    if verify_database(output_dir):
        print("\n✓ MyTaxa database is ready!")
        if archive_path.exists():
            print(f"Removing archive to save space...")
            archive_path.unlink()
            print("✓ Archive removed")
    else:
        print("\n✗ Database verification failed!")
        sys.exit(1)

if __name__ == '__main__':
    main()
