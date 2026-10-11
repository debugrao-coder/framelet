#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/artifacts" "$ROOT/macos/.build/preview-validation"
(cd "$ROOT/core" && cargo build --release)
SOURCE_HASHES="$(shasum -a 256 "$ROOT/macos/Sources/Framelet/Imaging.swift" "$ROOT/macos/Sources/Framelet/Capture.swift" "$ROOT/scripts/test-mac-preview.swift")"
swiftc -O -parse-as-library \
  "$ROOT/macos/Sources/Framelet/Imaging.swift" \
  "$ROOT/macos/Sources/Framelet/Capture.swift" \
  "$ROOT/scripts/test-mac-preview.swift" \
  -L "$ROOT/core/target/release" -lframelet_core \
  -Xlinker -rpath -Xlinker "$ROOT/core/target/release" \
  -o "$ROOT/macos/.build/preview-validation/test-mac-preview"
FRAMELET_BUILD_SOURCE_HASHES="$SOURCE_HASHES" python3 - "$ROOT" <<'PY'
import sys,subprocess,json,hashlib,datetime,pathlib,os
root=pathlib.Path(sys.argv[1]);exe=root/'macos/.build/preview-validation/test-mac-preview'
r={'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Synthetic native preview correctness and isolated-process microbenchmark; not live capture/app or Windows acceptance','source_sha256':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in ['macos/Sources/Framelet/Imaging.swift','macos/Sources/Framelet/Capture.swift','scripts/test-mac-preview.swift']}}
before={line.split(None,1)[1]:line.split(None,1)[0] for line in os.environ['FRAMELET_BUILD_SOURCE_HASHES'].splitlines()}
r['sources_unchanged_during_build']=all(hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()==sha for path,sha in before.items())
for mode in ['correctness','new','old']:
    try:
        p=subprocess.run([str(exe),mode],capture_output=True,text=True,timeout=120)
        r[mode]=json.loads(p.stdout);r[mode]['exit_code']=p.returncode
        if p.stderr:r[mode]['stderr']=p.stderr
    except Exception as e:r[mode]={'status':'FAIL','error':str(e)}
r['status']='PASS' if r['sources_unchanged_during_build'] and all(r[m].get('status')=='PASS' for m in ['correctness','new','old']) else 'FAIL'
if r['new'].get('status')=='PASS' and r['old'].get('status')=='PASS':
    r['comparison']={'new_faster_p50':r['new']['p50_ms']<r['old']['p50_ms'],'new_faster_p95':r['new']['nearest_rank_p95_ms']<r['old']['nearest_rank_p95_ms'],'new_lower_process_peak_rss':r['new']['process_peak_rss_bytes']<r['old']['process_peak_rss_bytes'],'p50_speedup_ratio':r['old']['p50_ms']/r['new']['p50_ms'],'note':'Measured conclusions only. Correctness PASS does not require performance superiority.'}
(root/'artifacts/mac-preview-validation.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(r,ensure_ascii=False,indent=2))
sys.exit(0 if r['status']=='PASS' else 1)
PY
