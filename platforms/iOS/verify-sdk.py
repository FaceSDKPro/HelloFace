#!/usr/bin/env python3
"""Compare Xcode's selected local SDK slices with its actual build products."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess


def uuids(binary):
    text=subprocess.check_output(['xcrun','dwarfdump','--uuid',str(binary)],text=True)
    result={arch:uuid.upper() for uuid,arch in re.findall(r'UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)',text)}
    if not result: raise ValueError('SDK binary has no UUID: '+binary.name)
    return result


def contents(path):
    return {p.relative_to(path).as_posix():p.read_bytes() for p in path.rglob('*') if p.is_file()}


def verify(products,package,platform,read_uuids=uuids):
    simulator=platform=='iphonesimulator'
    if platform not in {'iphoneos','iphonesimulator'}: raise ValueError('Unknown iOS SDK platform')
    # Remote binary targets are authenticated by SwiftPM's pinned ZIP checksums.
    # Compare bytes here when the package actually includes local XCFrameworks.
    local=[(package/(name+'.xcframework')).is_dir() for name in ('HiFace','HiFaceNative')]
    if local==[False,False]:
        manifest=package/'Package.swift'
        text=manifest.read_text() if manifest.is_file() else ''
        if text.count('.binaryTarget(')==2 and text.count('url:')==2 and text.count('checksum:')==2:
            return {'result':'remote-checksums-managed-by-swiftpm'}
        raise ValueError('Selected SDK package is incomplete; replace it before building')
    if not all(local): raise ValueError('Selected SDK package mixes missing/local Frameworks')
    for name in ('HiFace','HiFaceNative'):
        archive=package/(name+'.xcframework')
        metadata=plistlib.loads((archive/'Info.plist').read_bytes())
        slices=[row for row in metadata['AvailableLibraries'] if row.get('SupportedPlatform')=='ios'
                and (row.get('SupportedPlatformVariant')=='simulator')==simulator]
        if len(slices)!=1: raise ValueError('SDK must select one supported arm64 slice: '+name)
        row=slices[0]
        expected=archive/row['LibraryIdentifier']/row['LibraryPath']
        actual=products/(name+'.framework')
        source=plistlib.loads((expected/'Info.plist').read_bytes())
        built=plistlib.loads((actual/'Info.plist').read_bytes())
        for field in ('CFBundleShortVersionString','CFBundleVersion'):
            if built.get(field)!=source.get(field):
                raise ValueError('Xcode cached SDK differs from selected package version/build: '+name)
        expected_uuids=read_uuids(expected/name);actual_uuids=read_uuids(actual/name)
        if not actual_uuids or any(expected_uuids.get(arch)!=uuid for arch,uuid in actual_uuids.items()):
            raise ValueError('Xcode cached SDK binary differs from selected package UUID: '+name)
        for folder in ('Headers','HiFaceModels'):
            if contents(expected/folder)!=contents(actual/folder):
                raise ValueError('Xcode cached SDK headers/models differ from selected package: '+name+'/'+folder)
        for filename in ('PrivacyInfo.xcprivacy',):
            a,b=expected/filename,actual/filename
            if a.exists()!=b.exists() or a.exists() and a.read_bytes()!=b.read_bytes():
                raise ValueError('Xcode cached SDK resources differ from selected package: '+name)
    return {'result':'passed','platform':platform}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('products',type=Path);parser.add_argument('package',type=Path)
    parser.add_argument('platform',choices=('iphoneos','iphonesimulator'))
    args=parser.parse_args()
    try: print(verify(args.products,args.package,args.platform))
    except (OSError,ValueError,KeyError,subprocess.CalledProcessError) as error:
        raise SystemExit('error: Stale/mixed iOS SDK build products: '+str(error))
