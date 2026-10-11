#!/usr/bin/env python3
"""Validate PE metadata, exported C entry point and dependency allowlist; never load DLL."""
import sys,pathlib,struct,re,json,hashlib
image,report=map(pathlib.Path,sys.argv[1:3]);data=image.read_bytes();text=report.read_text()
assert data[:2]==b'MZ','not DOS/PE image'
offset=struct.unpack_from('<I',data,0x3c)[0]
assert data[offset:offset+4]==b'PE\0\0','missing PE signature'
assert struct.unpack_from('<H',data,offset+4)[0]==0xaa64,'not Windows ARM64'
assert struct.unpack_from('<H',data,offset+22)[0]&0x2000,'not a DLL'
assert struct.unpack_from('<H',data,offset+24)[0]==0x20b,'not PE32+'
exports=re.findall(r'Export \{[^}]*?Name: ([^\n]+)',text,re.S)
imports=re.findall(r'Import \{[^}]*?Name: ([^\n]+)',text,re.S)
assert exports==['framelet_overlap'],('unexpected exports',exports)
allowed={'kernel32.dll','ntdll.dll'}
assert imports,'empty import report'
assert all(n.lower() in allowed or re.fullmatch(r'api-ms-win-(?:crt|core)-[a-z0-9-]+\.dll',n.lower()) for n in imports),('non-system/unreviewed imports',imports)
print(json.dumps({'status':'PASS_SCOPED','architecture':'PE32+ ARM64 DLL (0xAA64)','exports':exports,'imports':imports,'sha256':hashlib.sha256(data).hexdigest(),'scope':'PE structure/export/dependency metadata only; Windows loading/execution NOT_TESTED'},indent=2))
