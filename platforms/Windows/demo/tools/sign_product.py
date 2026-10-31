#!/usr/bin/env python3
"""Sign a native product package; this is NOT a vendor license or device identity.

The publisher's Ed25519 private key stays on the build host, outside the package.
The SDK verifies the actual executable and loaded library against this inventory.
"""
import argparse
import hashlib
import json
import os
import re
import stat
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
import tempfile



def package(root,entry,sdk,signer,product,version,includes=(),platform='linux'):
    root=Path(root).resolve();entry=Path(entry).resolve();sdk=Path(sdk).resolve()
    if re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,126}',product)is None:raise ValueError('Invalid productId')
    if re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)",version) is None or any(int(part)>100000 for part in version.split(".")):
        raise ValueError("Version must be canonical x.y.z")
    if not isinstance(signer,Ed25519PrivateKey):raise ValueError('Ed25519 publisher key required')
    with entry.open('rb')as executable:
        header=executable.read(64)
        if platform=='linux':
            if len(header)<20 or header[:6]!=b'\x7fELF\x02\x01':raise ValueError('Only native 64-bit little-endian ELF entry points are qualified')
            architecture={183:'arm64',62:'x86_64'}.get(int.from_bytes(header[18:20],'little'))
            if not architecture:raise ValueError('Unqualified ELF architecture')
        elif platform=='windows':
            if len(header)!=64 or header[:2]!=b'MZ':raise ValueError('Windows entry point must be an x64 PE image')
            offset=int.from_bytes(header[60:64],'little')
            if not 64<=offset<=1048576:raise ValueError('Invalid PE header offset')
            executable.seek(offset);pe=executable.read(6)
            if pe!=b'PE\0\0\x64\x86':raise ValueError('Windows entry point must be x64')
            architecture='x86_64'
        else:raise ValueError('Unsupported package platform')
    depth=len(entry.parent.relative_to(root).parts)
    if depth>4:raise ValueError('Entry point is too deep in the product package')
    files=[];total=0
    for path in sorted({entry,sdk,*(Path(p).resolve() for p in includes)}):
        relative=path.relative_to(root).as_posix()
        if platform=='windows' and (not re.fullmatch(r'[A-Za-z0-9_.\-/]+',relative) or
                any(part in ('.','..') or part.endswith('.') for part in relative.split('/'))):
            raise ValueError('Windows inventory filenames must be portable ASCII paths without aliases')
        parents=[root];current=root
        for name in path.relative_to(root).parts[:-1]:
            current=current/name;parents.append(current)
        for part in [*parents,path]:
            mode=part.lstat().st_mode
            if stat.S_ISLNK(mode) or (os.name!='nt' and mode&0o022):raise ValueError('Package material must not be symlinked or writable by other users')
        size=path.stat().st_size;total+=size
        if not 0<size<=268435456 or total>268435456:raise ValueError('Package exceeds 256 MiB')
        digest=hashlib.blake2b(digest_size=32)
        with path.open('rb')as source:
            for block in iter(lambda:source.read(65536),b''):digest.update(block)
        files.append({'path':relative,'bytes':size,'digest':digest.hexdigest()})
    if len(files)>64:raise ValueError('Too many package files')
    if platform=='windows' and len({file['path'].lower() for file in files})!=len(files):raise ValueError('Windows inventory contains case aliases')
    public=signer.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)
    value={'format':'HF-WINDOWS-PACKAGE1' if platform=='windows' else 'HF-PACKAGE1','productId':product,'publisherKey':public.hex(),'version':version,
           'architecture':architecture,'rootDepth':depth,'entryPoint':entry.relative_to(root).as_posix(),'files':files}
    raw=json.dumps(value,separators=(',',':'),ensure_ascii=False).encode()
    if len(raw)>12000:raise ValueError("Package inventory exceeds 12 KiB")
    b64=lambda b:__import__('base64').urlsafe_b64encode(b).rstrip(b'=')
    domain=b'HiFace-Windows-Package-v1\0' if platform=='windows' else b'HiFace-Package-v1\0'
    return b'HF-PKG1.'+b64(raw)+b'.'+b64(signer.sign(domain+raw))


def main(require_outside_root=None):
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['root','entry','sdk','private-key']:parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--product-id',required=True);parser.add_argument('--version',required=True)
    parser.add_argument('--platform',choices=['linux','windows'],default='linux')
    parser.add_argument('--include',type=Path,action='append',default=[])
    parser.add_argument('--replace',action='store_true',help='Replace an existing build-time sidecar after rebuilding package bytes')
    args=parser.parse_args();key_path=args.private_key.resolve()
    forbidden=[args.root.resolve()]+([Path(require_outside_root).resolve()] if require_outside_root else [])
    if any(key_path==folder or folder in key_path.parents for folder in forbidden) or args.private_key.is_symlink() or (os.name!='nt' and key_path.stat().st_mode&0o077):
        parser.error('Keep the publisher private key outside the package/source checkout with private OS permissions')
    signer=serialization.load_pem_private_key(key_path.read_bytes(),password=None)
    data=package(args.root,args.entry,args.sdk,signer,args.product_id,args.version,args.include,args.platform)
    target=Path(str(args.entry.resolve())+'.hfpackage')
    fd,temporary=tempfile.mkstemp(prefix='.hfpackage-',dir=target.parent)
    try:
        with os.fdopen(fd,'wb')as out:
            out.write(data);out.flush()
            # This signed inventory contains only public identity and digests.
            # A root-owned install must remain readable by the runtime UID.
            # The publisher private key is never copied or chmodded here.
            if os.name!='nt':os.fchmod(out.fileno(),0o644)
            os.fsync(out.fileno())
        if args.replace:os.replace(temporary,target)
        else:os.link(temporary,target)
    finally:
        if os.path.exists(temporary):os.unlink(temporary)
    print(target)


if __name__=='__main__':main()
