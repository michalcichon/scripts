#!/usr/bin/env python3

import sys, os, glob, re

pattern = re.compile("(\w+)\s?(?:\[([^\]]+)\])?")
directory = sys.argv[1] if len(sys.argv) == 2 else os.path.dirname(os.path.realpath(__file__))
os.chdir(directory)
files = []
for file in glob.glob("*.nes"):
    if "(U)" in file:
        if pattern.search(file):
            print ("matching " +file)
        else:
            files.append(file)

print(files)
