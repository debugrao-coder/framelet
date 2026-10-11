param([ValidateSet('x64','arm64')][string]$Architecture='x64',[switch]$Package,[string]$CertificateThumbprint)
$ErrorActionPreference='Stop'
if(-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)){throw 'This build/package script requires Windows. For Mac source validation use dotnet build -p:EnableWindowsTargeting=true.'}
Set-Location $PSScriptRoot
$Architecture=$Architecture.ToLowerInvariant()
if (!(Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'Install .NET 8 SDK from https://dotnet.microsoft.com/download/dotnet/8.0' }
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) { throw 'Install Rust MSVC toolchain from https://rustup.rs and Visual Studio C++ Build Tools.' }
$target=if($Architecture -eq 'arm64'){'aarch64-pc-windows-msvc'}else{'x86_64-pc-windows-msvc'}
cargo build --manifest-path ../core/Cargo.toml --release --target $target
if($LASTEXITCODE -ne 0){throw 'Native core build failed; install the Rust target and matching C++ build tools.'}
$out=Join-Path $PSScriptRoot "bin/publish-$Architecture"
dotnet publish Framelet.csproj -c Release -r "win-$Architecture" --self-contained true -p:Platform=$Architecture -o $out
if($LASTEXITCODE -ne 0){throw 'WPF publish failed'}
Copy-Item "../core/target/$target/release/framelet_core.dll" $out -Force
if(!$Package){Write-Host "Built: $out/Framelet.exe. OCR requires MSIX package identity; use -Package.";exit 0}
$kit=Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/bin/*/x64/makeappx.exe"|Sort-Object FullName -Descending|Select-Object -First 1
if(!$kit){throw 'Windows 10/11 SDK makeappx.exe required.'}
$stage=Join-Path $PSScriptRoot ("package/stage-$Architecture-"+[guid]::NewGuid().ToString("N"));New-Item -ItemType Directory -Force "$stage/Assets"|Out-Null
Copy-Item "$out/*" $stage -Recurse -Force
foreach($size in @(44,150,50)){
 Copy-Item (Join-Path $PSScriptRoot "Assets/Logo$size.png") "$stage/Assets/Logo$size.png"
}
$manifest=@"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10" xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10" xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities" IgnorableNamespaces="uap desktop rescap">
<Identity Name="Framelet.Local" Publisher="CN=Framelet Local Development" Version="0.1.0.0" ProcessorArchitecture="$Architecture"/>
<Properties><DisplayName>瞬帧 Framelet</DisplayName><PublisherDisplayName>Framelet Local</PublisherDisplayName><Logo>Assets\Logo50.png</Logo></Properties>
<Resources><Resource Language="zh-cn"/><Resource Language="en-us"/></Resources>
<Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0"/></Dependencies>
<Applications><Application Id="Framelet" Executable="Framelet.exe" EntryPoint="Windows.FullTrustApplication"><uap:VisualElements DisplayName="瞬帧 Framelet" Description="本地截图、长截图、GIF 录制与文字识别" BackgroundColor="transparent" Square150x150Logo="Assets\Logo150.png" Square44x44Logo="Assets\Logo44.png"/></Application></Applications>
<Capabilities><rescap:Capability Name="runFullTrust"/></Capabilities>
</Package>
"@
$manifest|Set-Content "$stage/AppxManifest.xml" -Encoding utf8
$msix=Join-Path $PSScriptRoot "package/Framelet-$Architecture.msix"
& $kit.FullName pack /d $stage /p $msix /o
if($LASTEXITCODE -ne 0){throw 'MSIX packaging failed'}
if($CertificateThumbprint){$sign=Join-Path $kit.DirectoryName 'signtool.exe';& $sign sign /fd SHA256 /sha1 $CertificateThumbprint $msix;if($LASTEXITCODE -ne 0){throw 'Signing failed; certificate subject must match publisher CN=Framelet Local Development'}}
Write-Host "Package: $msix. No certificate was created/trusted and no package was installed. Install only after explicitly approving signing trust."
