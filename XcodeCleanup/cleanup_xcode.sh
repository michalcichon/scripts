#!/bin/bash

echo "Removing DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/

echo "Removing DeviceSupport..."
rm -rf ~/Library/Developer/Xcode/iOS DeviceSupport/

echo "Removing Archives..."
rm -rf ~/Library/Developer/Xcode/Archives/

echo "Removing unavailable simulators..."
xcrun simctl delete unavailable

echo "Removing logs..."
rm -rf ~/Library/Logs/CoreSimulator