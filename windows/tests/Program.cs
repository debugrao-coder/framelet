using Framelet;
using System.IO;
// Full 1x1 GIF with black/white global palette and one white pixel. Synthetic only.
byte[] first = Convert.FromBase64String("R0lGODlhAQABAIAAAP///wAAACwAAAAAAQABAAACAkQBADs=");
byte[] second = (byte[])first.Clone(); second[13]=0;second[14]=255;second[15]=0;
int assertions=0;
void Check(bool yes,string name){if(!yes)throw new Exception(name);assertions++;}
var output = new MemoryStream(); using(var mux=new GifMuxer(output)){mux.Add(first,10);mux.Add(second,25);}
byte[] result=output.ToArray();
Check(result.AsSpan(0,6).SequenceEqual("GIF89a"u8),"Header");Check(result[^1]==0x3B,"Trailer");
File.WriteAllBytes(Path.Combine(AppContext.BaseDirectory,"mux-test.gif"),result);
for(int n=0;n<first.Length-1;n++){
 using var stream=new MemoryStream();using var mux=new GifMuxer(stream);
 try{mux.Add(first.Take(n).ToArray(),10);if(n<first.Length-1)throw new Exception($"Accepted truncation {n}");}catch(InvalidDataException){assertions++;}
 Check(stream.Length==0,"Invalid input must not write partial header");
}
using(var stream=new MemoryStream()){using var mux=new GifMuxer(stream);mux.Add(first,10);byte[] changed=(byte[])first.Clone();changed[6]=2;try{mux.Add(changed,10);throw new Exception("Accepted inconsistent size");}catch(InvalidDataException){assertions++;}}
using(var stream=new MemoryStream()){using var mux=new GifMuxer(stream);try{mux.Add(first,0);throw new Exception("Accepted zero delay");}catch(ArgumentOutOfRangeException){assertions++;}}
// Local-palette variant: remove the global table and attach the same table to image descriptor.
byte[] local=new byte[first.Length];Array.Copy(first,0,local,0,13);local[10]=0x70;Array.Copy(first,19,local,13,10);local[22]=0x80;Array.Copy(first,13,local,23,6);Array.Copy(first,29,local,29,first.Length-29);
var localOutput=new MemoryStream();using(var mux=new GifMuxer(localOutput)){mux.Add(local,10);mux.Add(second,25);}File.WriteAllBytes(Path.Combine(AppContext.BaseDirectory,"mux-local-test.gif"),localOutput.ToArray());assertions++;

// Exact overlap guard: detect fixed edge content even when the coarse detector
// intentionally treats those edges as irrelevant to finding the translation.
const int width=37,height=96,stride=width*4+8,delta=23;
byte[] Frame(int offset)
{
 var data=new byte[stride*height];
 for(int y=0;y<height;y++)for(int x=0;x<width;x++){
  int at=y*stride+x*4;uint v=unchecked((uint)((y+offset)*1664525 ^ x*1013904223));
  data[at]=(byte)v;data[at+1]=(byte)(v>>8);data[at+2]=(byte)(v>>16);data[at+3]=255;
 }
 return data;
}
byte[] prev=Frame(0),next=Frame(delta);
ScrollGuard.RequireExactOverlap(prev,next,width,height,stride,delta);assertions++;
// Padding bytes do not represent pixels and must not cause a rejection.
next[width*4]=123;ScrollGuard.RequireExactOverlap(prev,next,width,height,stride,delta);assertions++;
void Reject(byte[] a,byte[] b,string name){try{ScrollGuard.RequireExactOverlap(a,b,width,height,stride,delta);throw new Exception("Accepted "+name);}catch(InvalidDataException){assertions++;}}
var header=(byte[])next.Clone();Array.Copy(prev,0,header,0,8*stride);Reject(prev,header,"fixed header");
var footer=(byte[])prev.Clone();Array.Copy(next,(height-8)*stride,footer,(height-8)*stride,8*stride);Reject(footer,next,"fixed footer");
var caret=(byte[])next.Clone();caret[31*stride+12]^=1;Reject(prev,caret,"one changed overlap byte");
try{ScrollGuard.RequireExactOverlap(prev,next.Take(10).ToArray(),width,height,stride,delta);throw new Exception("Accepted short buffer");}catch(ArgumentException){assertions++;}
foreach(int invalid in new[]{0,-1,height,height+1}){try{ScrollGuard.RequireExactOverlap(prev,next,width,height,stride,invalid);throw new Exception("Accepted invalid delta");}catch(ArgumentException){assertions++;}}


// WGC readback crop and fallback policy are pure managed code; these tests do not
// create a D3D device or claim an actual Windows capture.
byte[] monitorPixels=Enumerable.Range(0,6*5*4).Select(i=>(byte)i).ToArray();
var cropped=CapturePixels.CropBgra(monitorPixels,6,5,2,1,3,2);
Check(cropped.SequenceEqual(monitorPixels.Skip((1*6+2)*4).Take(12).Concat(monitorPixels.Skip((2*6+2)*4).Take(12))),"physical BGRA row crop");
Check(CapturePixels.CropBgra(monitorPixels,6,5,0,0,6,5).SequenceEqual(monitorPixels),"full monitor crop");
foreach(var invalid in new[]{(-1,0,1,1),(0,-1,1,1),(0,0,0,1),(5,0,2,1),(0,4,1,2),(int.MaxValue,0,1,1)}){
 try{CapturePixels.CropBgra(monitorPixels,6,5,invalid.Item1,invalid.Item2,invalid.Item3,invalid.Item4);throw new Exception("Accepted invalid crop");}catch(ArgumentException){assertions++;}
}
try{CapturePixels.CropBgra(new byte[2],6,5,0,0,1,1);throw new Exception("Accepted short BGRA buffer");}catch(ArgumentException){assertions++;}
Check(CapturePolicy.CanUseGdiFallback(new NotSupportedException()),"unsupported feature fallback");
Check(CapturePolicy.CanUseGdiFallback(new System.Runtime.InteropServices.COMException("DXGI unsupported",unchecked((int)0x887A0004))),"unsupported hardware fallback");
foreach(var denial in new Exception[]{new UnauthorizedAccessException(),new TimeoutException(),new OperationCanceledException(),new IOException(),new System.Runtime.InteropServices.COMException("access denied",unchecked((int)0x80070005)),new System.Runtime.InteropServices.COMException("policy blocked",unchecked((int)0x800704EC)),new System.Runtime.InteropServices.COMException("device lost",unchecked((int)0x887A0005))})
 Check(!CapturePolicy.CanUseGdiFallback(denial),"no restriction bypass for "+denial.GetType().Name);


// Native-frame ownership model: latest-only replacement, transfer, shutdown and late callbacks.
var slot=new LatestFrameSlot<TestFrame>();var f1=new TestFrame();var f2=new TestFrame();slot.Publish(f1);slot.Publish(f2);Check(f1.Disposals==1,"replaced native frame released");Check(f2.Disposals==0,"latest frame retained");Check(ReferenceEquals(slot.Take(),f2),"latest frame transferred");slot.Dispose();Check(f2.Disposals==0,"taken frame remains caller owned");f2.Dispose();Check(f2.Disposals==1,"consumer frame release");var late=new TestFrame();slot.Publish(late);Check(late.Disposals==1,"late callback released after dispose");Check(slot.Take()==null,"closed slot empty");
var live=new LatestFrameSlot<TestFrame>();var many=Enumerable.Range(0,2000).Select(_=>new TestFrame()).ToArray();
Parallel.ForEach(many,frame=>{live.Publish(frame);live.Take()?.Dispose();});live.Dispose();Check(many.All(frame=>frame.Disposals==1),"concurrent transfer releases every frame exactly once");

// Optional real host-native core ABI integration; never presented as Windows DLL execution.
if(args.Length==2 && args[0]=="--core"){
 IntPtr library=System.Runtime.InteropServices.NativeLibrary.Load(Path.GetFullPath(args[1]));
 try{
  var overlap=System.Runtime.InteropServices.Marshal.GetDelegateForFunctionPointer<NativeOverlap>(System.Runtime.InteropServices.NativeLibrary.GetExport(library,"framelet_overlap"));
  Check(overlap(prev,next,width,height,stride)==delta,"host core detects downward translation");
  int headerDelta=overlap(prev,header,width,height,stride);Check(headerDelta>0,"host core intentionally ignores fixed header");
  try{ScrollGuard.RequireExactOverlap(prev,header,width,height,stride,headerDelta);throw new Exception("Guard accepted real core fixed header offset");}catch(InvalidDataException){assertions++;}
  int footerDelta=overlap(footer,next,width,height,stride);Check(footerDelta>0,"host core intentionally ignores fixed footer");
  try{ScrollGuard.RequireExactOverlap(footer,next,width,height,stride,footerDelta);throw new Exception("Guard accepted real core fixed footer offset");}catch(InvalidDataException){assertions++;}
 }finally{System.Runtime.InteropServices.NativeLibrary.Free(library);}
}

// File lifecycle under real OS file operations, with synthetic tiny payloads only.
string tempRoot=Path.Combine(AppContext.BaseDirectory,"recording-tests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(tempRoot);
try {
 var aborted=new RecordingFile(Path.Combine(tempRoot,"abort.gif"));File.WriteAllBytes(aborted.Temporary,new byte[]{1,2});aborted.CleanupIncomplete();Check(!File.Exists(aborted.Temporary),"incomplete cleanup");
 var success=new RecordingFile(Path.Combine(tempRoot,"success.gif"));File.WriteAllBytes(success.Target,new byte[]{9});File.WriteAllBytes(success.Temporary,result);success.MarkComplete();success.Commit();Check(File.ReadAllBytes(success.Target).SequenceEqual(result),"complete atomic replace");Check(!File.Exists(success.Temporary),"rename removes temporary");
 string blockedTarget=Path.Combine(tempRoot,"directory.gif");Directory.CreateDirectory(blockedTarget);var blocked=new RecordingFile(blockedTarget);File.WriteAllBytes(blocked.Temporary,result);blocked.MarkComplete();try{blocked.Commit();throw new Exception("Accepted directory destination");}catch(IOException){assertions++;}blocked.CleanupIncomplete();Check(File.ReadAllBytes(blocked.Temporary).SequenceEqual(result),"complete recording retained after commit failure");
 var early=new RecordingFile(Path.Combine(tempRoot,"early.gif"));try{early.Commit();throw new Exception("Committed incomplete recording");}catch(InvalidOperationException){assertions++;}
}finally{Directory.Delete(tempRoot,true);}
var throwing=new TrailerFailStream();var closeMux=new GifMuxer(throwing);closeMux.Add(first,10);try{closeMux.Dispose();throw new Exception("Trailer write unexpectedly succeeded");}catch(IOException){assertions++;}Check(throwing.WasDisposed,"stream disposed after trailer failure");
// Atomic still-image saving: real synthetic files plus deterministic fault injection.
string saveRoot=Path.Combine(AppContext.BaseDirectory,"atomic-save-tests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(saveRoot);
try {
 byte[] original=Enumerable.Range(0,257).Select(i=>(byte)i).ToArray(), replacement={7,8,9,10};
 string target=Path.Combine(saveRoot,"image.png");
 void Unchanged(string label)=>Check(File.ReadAllBytes(target).SequenceEqual(original),label);
 void Clean(string label)=>Check(!Directory.EnumerateFiles(saveRoot,".framelet-*.tmp").Any(),label);
 AtomicFileSave.Save(target,stream=>stream.Write(original));Unchanged("new target saved");Clean("new target no staging");
 AtomicFileSave.Save(target,stream=>stream.Write(replacement));Check(File.ReadAllBytes(target).SequenceEqual(replacement),"existing target replaced");Clean("overwrite no staging");
 File.WriteAllBytes(target,original);
 var encodeError=new IOException("injected encoder error");
 try{AtomicFileSave.Save(target,stream=>{stream.Write(replacement);throw encodeError;});throw new Exception("Accepted encoder failure");}catch(IOException ex){Check(ReferenceEquals(ex,encodeError),"encoder exception identity retained");}
 Unchanged("partial encoding preserves all original bytes");Clean("encoder failure removes staging");
 string absent=Path.Combine(saveRoot,"absent.png");
 try{AtomicFileSave.Save(absent,stream=>{stream.WriteByte(1);throw encodeError;});throw new Exception("Accepted failed new file");}catch(IOException){assertions++;}
 Check(!File.Exists(absent),"failed new target not created");Clean("failed new target cleanup");
 foreach(string stage in new[]{"open","flush","close","commit"}){
  var fault=new IOException("injected "+stage);var ops=new FaultFileOperations{Failure=stage,Fault=fault};
  try{AtomicFileSave.Save(target,stream=>stream.Write(replacement),ops);throw new Exception("Accepted "+stage+" failure");}catch(IOException ex){Check(ReferenceEquals(ex,fault),stage+" exception retained");}
  Unchanged(stage+" preserves original");Clean(stage+" cleans staging");
  Check(stage=="open"?ops.Deletes==0:ops.Deletes==1,stage+" only owned staging cleaned");
  Check(stage=="commit"?ops.Commits==1:ops.Commits==0,stage+" no premature commit");
 }
 var ordering=new FaultFileOperations();AtomicFileSave.Save(target,stream=>{ordering.Events.Add("encode");stream.Write(original);},ordering);
 Check(string.Join(",",ordering.Events)=="open,encode,flush,close,commit","encode then durable flush then close before commit");
 Check(Path.GetDirectoryName(ordering.Staging)==saveRoot,"staging is sibling");
 var combined=new FaultFileOperations{Failure="close",FailDelete=true};
 try{AtomicFileSave.Save(target,stream=>{stream.WriteByte(1);throw encodeError;},combined);throw new Exception("Lost multiple errors");}
 catch(AggregateException ex){Check(ex.InnerExceptions.Count==3,"encoding close cleanup errors all retained");Check(ReferenceEquals(ex.InnerExceptions[0],encodeError),"primary encoding exception retained in aggregate");Check(ex.InnerExceptions[2].Message.Contains(combined.Staging!),"cleanup failure reports exact orphan path");}
 Unchanged("multiple failures preserve original");Check(File.Exists(combined.Staging),"cleanup failure leaves explicitly reported staging");File.Delete(combined.Staging!);
 var raced=new FaultFileOperations{BeforeCommit=()=>File.WriteAllBytes(absent,original)};
 try{AtomicFileSave.Save(absent,stream=>stream.Write(replacement),raced);throw new Exception("Overwrote new competing target");}catch(IOException){assertions++;}
 Check(File.ReadAllBytes(absent).SequenceEqual(original),"new competing target preserved");Clean("competing target staging cleaned");
 // Real filesystem rejection, not only a fake commit failure.
 string directoryTarget=Path.Combine(saveRoot,"directory.png");Directory.CreateDirectory(directoryTarget);
 try{AtomicFileSave.Save(directoryTarget,stream=>stream.Write(replacement));throw new Exception("Accepted directory target");}catch(IOException){assertions++;}
 Check(Directory.Exists(directoryTarget),"directory destination untouched");Clean("real commit failure staging cleaned");
}finally{Directory.Delete(saveRoot,true);}
// OCR document ownership: platform-neutral state actually used by the WPF editor.
var document=new OcrDocument();
Check(document.Text==""&&!document.HasUncopiedText&&!document.Busy,"OCR starts empty and clean");
var request1=document.Begin()!.Value;Check(document.Busy,"OCR request starts busy");Check(document.Begin()==null,"duplicate OCR refused");
Check(document.Complete(request1,"first result")==OcrDocument.Completion.Applied,"OCR applies current result");Check(document.HasUncopiedText,"recognized text requires copy acknowledgement");
Check(!document.ConfirmCopied("first"),"partial clipboard text does not acknowledge full OCR");Check(document.HasUncopiedText,"partial copy keeps text dirty");
Check(document.ConfirmCopied("first result")&&!document.HasUncopiedText,"successful full copy acknowledges exact text");
document.Edit("human corrected");Check(document.HasManualEdits&&document.HasUncopiedText,"manual correction tracked separately");
Check(document.Begin()==null,"manual overwrite defaults to refusal");Check(document.Text=="human corrected","refusal preserves manual text");
var request2=document.Begin(true)!.Value;document.Fail(request2);Check(document.Text=="human corrected"&&document.HasUncopiedText&&!document.Busy,"OCR failure preserves text and dirty state");
var request3=document.Begin(true)!.Value;Check(document.Complete(request3,"  \n ")==OcrDocument.Completion.Empty,"blank OCR treated as empty");Check(document.Text=="human corrected"&&document.HasManualEdits,"empty OCR preserves manual text");
var request4=document.Begin(true)!.Value;document.Edit("edited while recognizing");Check(document.Complete(request4,"late new OCR")==OcrDocument.Completion.Stale,"inflight OCR cannot overwrite newer edits");Check(document.Text=="edited while recognizing","stale result retains newer text");
var request5=document.Begin(true)!.Value;document.Edit("temporary");document.Edit("edited while recognizing");Check(document.Complete(request5,"late after revert")==OcrDocument.Completion.Stale,"revision protects edit then revert");
var request6=document.Begin(true)!.Value;document.Fail(request6);var request7=document.Begin(true)!.Value;Check(document.Complete(request6,"old request")==OcrDocument.Completion.Inactive&&document.Busy,"old callback cannot end new request");
Check(document.Complete(request7,"new accepted result")==OcrDocument.Completion.Applied&&!document.HasManualEdits,"approved replacement becomes OCR-owned text");
Check(!document.ConfirmCopied("edited while recognizing")&&document.HasUncopiedText,"old clipboard acknowledgement cannot clean current text");
var beforeCopy=document.Text;document.Edit("changed before acknowledgement");Check(!document.ConfirmCopied(beforeCopy),"copy revision content mismatch stays dirty");
Check(document.ConfirmCopied(document.Text)&&!document.HasUncopiedText,"current complete text can be acknowledged");
document.Edit("");Check(!document.HasUncopiedText,"empty text has no content to lose");
var closeRequest=document.Begin(true)!.Value;document.Close();Check(!document.Busy&&document.Closed,"close invalidates request");Check(document.Complete(closeRequest,"late after close")==OcrDocument.Completion.Inactive,"closed document rejects callbacks");document.Edit("after close");Check(document.Text=="","closed document rejects edits");Check(document.Begin(true)==null&&!document.ConfirmCopied("anything"),"closed document rejects operations");
// Real bounded waits around synthetic workers. Native OCR is never invoked here.
using(var deadlineCancellation=new CancellationTokenSource()){
 var pending=new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
 try{await OcrDeadline.Await(pending.Task,deadlineCancellation,TimeSpan.Zero);throw new Exception("OCR timeout ignored");}catch(TimeoutException){assertions++;}
 Check(deadlineCancellation.IsCancellationRequested,"OCR deadline requests native cancellation");Check(!pending.Task.IsCompleted,"timeout does not falsely claim native termination");pending.SetResult("late result");Check(await pending.Task=="late result","worker retains lifetime after UI timeout");
}
using(var cancel=new CancellationTokenSource()){
 var pending=new TaskCompletionSource<string>();cancel.Cancel();try{await OcrDeadline.Await(pending.Task,cancel,TimeSpan.FromSeconds(1));throw new Exception("OCR close cancellation ignored");}catch(OperationCanceledException){assertions++;}pending.SetResult("ignored");
}
using(var cancel=new CancellationTokenSource()){
 Check(await OcrDeadline.Await(Task.FromResult("ok"),cancel,TimeSpan.FromSeconds(1))=="ok","OCR deadline passes success");
 var fault=new IOException("injected OCR failure");try{await OcrDeadline.Await(Task.FromException<string>(fault),cancel,TimeSpan.FromSeconds(1));throw new Exception("OCR fault ignored");}catch(IOException ex){Check(ReferenceEquals(fault,ex),"OCR deadline preserves failure exception");}
}
assertions += ShortcutTests.Run();
Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new{status="PASS_SCOPED",assertions,scope="shared streaming GIF mux bytes, bounds, dimensions, local/global palettes and exact scroll overlap guard and recording file lifecycle, WGC pixel crop, fallback policy and latest-frame ownership, atomic PNG file lifecycle and injected failures, OCR revision/copy/close state and bounded wait, shortcut registration transactions and per-user config; not Windows filesystem/WIC/WGC or screen capture"}));

sealed class TrailerFailStream : MemoryStream
{
 public bool WasDisposed {get;private set;}
 public override void WriteByte(byte value){if(value==0x3B)throw new IOException("synthetic trailer write failure");base.WriteByte(value);}
 protected override void Dispose(bool disposing){WasDisposed=true;base.Dispose(disposing);}
}

[System.Runtime.InteropServices.UnmanagedFunctionPointer(System.Runtime.InteropServices.CallingConvention.Cdecl)]
delegate int NativeOverlap(byte[] previous,byte[] next,int width,int height,int stride);

sealed class TestFrame : IDisposable
{
 int disposals;
 public int Disposals=>Volatile.Read(ref disposals);
 public void Dispose()=>Interlocked.Increment(ref disposals);
}

sealed class FaultFileOperations : IAtomicFileOperations
{
 public string? Failure,Staging;public bool FailDelete;public IOException Fault=new("injected failure");public int Deletes,Commits;public List<string> Events=new();public Action? BeforeCommit;
 public Stream CreateExclusive(string path){Events.Add("open");Staging=path;if(Failure=="open")throw Fault;return new CloseProbe(PhysicalAtomicFileOperations.Instance.CreateExclusive(path),()=>{Events.Add("close");if(Failure=="close")throw Fault;});}
 public void FlushToDisk(Stream stream){Events.Add("flush");if(Failure=="flush")throw Fault;PhysicalAtomicFileOperations.Instance.FlushToDisk(((CloseProbe)stream).Inner);}
 public void Commit(string staging,string target,bool replaceExisting){Events.Add("commit");Commits++;if(Failure=="commit")throw Fault;BeforeCommit?.Invoke();PhysicalAtomicFileOperations.Instance.Commit(staging,target,replaceExisting);}
 public void Delete(string path){Deletes++;if(FailDelete)throw new IOException("injected cleanup failure");PhysicalAtomicFileOperations.Instance.Delete(path);}
}
sealed class CloseProbe(Stream inner,Action onClose) : Stream
{
 public Stream Inner=>inner;public override bool CanRead=>false;public override bool CanSeek=>inner.CanSeek;public override bool CanWrite=>inner.CanWrite;public override long Length=>inner.Length;public override long Position{get=>inner.Position;set=>inner.Position=value;}
 public override void Flush()=>inner.Flush();public override int Read(byte[] buffer,int offset,int count)=>throw new NotSupportedException();public override long Seek(long offset,SeekOrigin origin)=>inner.Seek(offset,origin);public override void SetLength(long value)=>inner.SetLength(value);public override void Write(byte[] buffer,int offset,int count)=>inner.Write(buffer,offset,count);
 protected override void Dispose(bool disposing){if(disposing){inner.Dispose();onClose();}base.Dispose(disposing);}
}
