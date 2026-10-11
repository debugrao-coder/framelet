#!/usr/bin/env python3
"""WPF wiring checks only, not Windows runtime/clipboard/OCR evidence."""
import pathlib,json,hashlib
r=pathlib.Path(__file__).resolve().parents[1]
e=(r/'Editor.cs').read_text();s=(r/'OcrService.cs').read_text();checks=[]
def check(ok,name):
 assert ok,name
 checks.append(name)
check('readonly OcrDocument ocrDocument = new()' in e,'tested OCR state owned by editor')
check('ocr.TextChanged +=' in e and 'ocrDocument.Edit(ocr.Text)' in e,'manual changes enter revision state')
check('ocrDocument.Begin(approved)' in e and 'ocrDocument.Complete(request.Value, text)' in e,'request tokens guard result application')
check('MessageBoxResult.No' in e and 'ocrDocument.HasManualEdits || MessageBox.Show' in e,'manual overwrite confirmation defaults No')
check('ocr.Text = ""' not in e and 'ocr.Text = "正在' not in e,'no progress/error text overwrite')
check(e.index('Clipboard.SetText(fullText)')<e.index('ocrDocument.ConfirmCopied(fullText)'),'full clipboard success precedes acknowledgement')
check('ocr.SelectionLength == ocr.Text.Length' in e,'only full keyboard selection acknowledges OCR')
check('ocrDocument.HasUncopiedText' in e and '保存 PNG 不会保存文字' in e,'close separately protects OCR text')
check('ocrDocument.Close(); ocrCancellation?.Cancel()' in e,'close invalidates document and cancels wait')
check('OcrDeadline.Await(worker, cancellation, TimeSpan.FromSeconds(30))' in e,'bounded UI wait wired')
check('if (recognizing || saving || closed || ocrWorker is { IsCompleted: false }) return;' in e,'pending native worker prevents another OCR')
check('if (!closed && ReferenceEquals(ocrWorker, worker))' in e and 'if (closed) return;' in e,'late completion avoids closed UI')
check('operation.Cancel()' in s and 'await operation.AsTask()' in s,'native cancellation request separate from resource-owning await')
check('using var bitmap = SoftwareBitmap.CreateCopyFromBuffer' in s,'native bitmap retained until native await completes')
check(e.index('string text = await OcrDeadline.Await')<e.index('_ = ObserveOcrWorker(requestWorker, requestCancellation)'),'CTS disposal observation starts after bounded wait finishes')
check('ocrDocument' not in e[e.index('async void Save()'):e.index('void Copy()')],'PNG save never clears OCR dirty state')
print(json.dumps({'status':'PASS_SCOPED','assertions':len(checks),'scope':'OCR WPF source wiring; not Windows OCR/clipboard/native cancellation execution','checks':checks,'source_sha256':{n:hashlib.sha256((r/n).read_bytes()).hexdigest() for n in ['Editor.cs','OcrService.cs','OcrDocument.cs']}},indent=2))
