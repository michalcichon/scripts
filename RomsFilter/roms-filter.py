#!/usr/bin/env python3

import sys, os, glob, re, shutil

FILTERED_DIR_NAME = "Filtered roms"

pattern = re.compile("\[(.*?)\]")
directory = sys.argv[1] if len(sys.argv) == 2 else os.path.dirname(os.path.realpath(__file__))
os.chdir(directory)
files = []

# Copy files that are from US region and filter out everythig that has notes in squer brackets
# as they usualy are hacked or unstabile roms. But keep everything with [!] which are 
# stabile and tested.
#
# For example:
# * 8 Eyes (U).nes - normal dump from US region
# * 8 Eyes (J).nes - normal dump from Japan region
# * 6-in-1 (SuperGK-L02A) [p1][!] - some extra variant but fully verified
# * Mario MI41 (SMB1 Hack) [a2] - hack, it should be filter out
# * Marvel's X-Men (U) [o3] - some extra variant, it should be filter out
for file in glob.glob("*.nes"):
    if "(U)" in file:
        if not pattern.search(file) or "[!]" in file:
            if not re.search('Hack', file, flags=re.IGNORECASE):
                files.append(file)

if len(files) > 0:
    if not os.path.isdir(FILTERED_DIR_NAME):
        os.makedirs(FILTERED_DIR_NAME)
    for file in files:
        shutil.copyfile(file, os.path.join(directory, FILTERED_DIR_NAME, file))

print("Copied %s files." % len(files))
