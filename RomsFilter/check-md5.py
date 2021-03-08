#!/usr/bin/env python3

import sys, os, glob, shutil, hashlib

def get_md5_from_file(file):
    md5_hash = hashlib.md5()
    a_file = open(file, "rb")
    content = a_file.read()
    md5_hash.update(content)

    digest = md5_hash.hexdigest()
    return digest

directory = sys.argv[1] if len(sys.argv) == 2 else os.path.dirname(os.path.realpath(__file__))
os.chdir(directory)
files = []
files_to_hashes = {}
hashes_to_files = {}
hashes_to_count = {}

for file in glob.glob("*.nes"):
    file_hash = get_md5_from_file(file)
    files_to_hashes[file] = file_hash

    if not file_hash in hashes_to_files:
        hashes_to_files[file_hash] = []
    hashes_to_files[file_hash].append(file)
    
    if file_hash in hashes_to_count:
        hashes_to_count[file_hash] += 1
    else:
        hashes_to_count[file_hash] = 1

for key, value in hashes_to_count.items():
    if value > 1:
        print(hashes_to_files[key])
