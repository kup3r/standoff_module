$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=Split-Path $PSScriptRoot -Parent
$scratch=Join-Path $root ('build/package-test-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$framework=Join-Path $scratch 'GlowESP.framework'
[IO.Directory]::CreateDirectory($framework) | Out-Null
$fixture=[byte[]]::new(32)
[BitConverter]::GetBytes([uint32]4277009103).CopyTo($fixture,0)
[BitConverter]::GetBytes([uint32]16777228).CopyTo($fixture,4)
[BitConverter]::GetBytes([uint32]6).CopyTo($fixture,12)
[IO.File]::WriteAllBytes((Join-Path $framework 'GlowESP'),$fixture)
[IO.File]::WriteAllText((Join-Path $framework 'Info.plist'),'<plist version="1.0"><dict/></plist>')
function New-TestIPA([string]$name,[bool]$encrypted,[bool]$nonzeroPadding){
    $b=[byte[]]::new(8192)
    [BitConverter]::GetBytes([uint32]4277009103).CopyTo($b,0)
    [BitConverter]::GetBytes([uint32]16777228).CopyTo($b,4)
    [BitConverter]::GetBytes([uint32]2).CopyTo($b,12)
    [BitConverter]::GetBytes([uint32]2).CopyTo($b,16)
    [BitConverter]::GetBytes([uint32]176).CopyTo($b,20)
    [BitConverter]::GetBytes([uint32]25).CopyTo($b,32)
    [BitConverter]::GetBytes([uint32]152).CopyTo($b,36)
    [BitConverter]::GetBytes([uint32]1).CopyTo($b,96)
    [BitConverter]::GetBytes([uint32]4096).CopyTo($b,152)
    [BitConverter]::GetBytes([uint32]44).CopyTo($b,184)
    [BitConverter]::GetBytes([uint32]24).CopyTo($b,188)
    [BitConverter]::GetBytes([uint32][int]$encrypted).CopyTo($b,200)
    if($nonzeroPadding){$b[208]=123}
    $path=Join-Path $scratch ($name+'.ipa')
    $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try{
        $e=$zip.CreateEntry('Payload/Test.app/Standoff2');$s=$e.Open();try{$s.Write($b,0,$b.Length)}finally{$s.Dispose()}
        $info=$zip.CreateEntry('Payload/Test.app/Info.plist');$writer=[IO.StreamWriter]::new($info.Open())
        try{$writer.Write('<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Standoff2</string><key>CFBundleIdentifier</key><string>test.invalid</string><key>UIFileSharingEnabled</key><false/></dict></plist>')}finally{$writer.Dispose()}
    }finally{$zip.Dispose()}
    return $path
}
$source=New-TestIPA 'source' $false $false
$hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$output=Join-Path $scratch 'output.ipa'
& (Join-Path $root 'package-windows.ps1') -SourceIPA $source -FrameworkDirectory $framework -OutputIPA $output
if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash){throw 'Source was modified'}
$zip=[IO.Compression.ZipFile]::OpenRead($output)
try{
    if(!$zip.GetEntry('Payload/Test.app/Frameworks/GlowESP.framework/GlowESP')){throw 'Missing embedded framework'}
    $s=$zip.GetEntry('Payload/Test.app/Standoff2').Open();$m=[IO.MemoryStream]::new()
    try{$s.CopyTo($m);$b=$m.ToArray()}finally{$s.Dispose();$m.Dispose()}
    if([BitConverter]::ToUInt32($b,16) -ne 3){throw 'Load command count incorrect'}
    if([BitConverter]::ToUInt32($b,208) -ne 12){throw 'Missing LC_LOAD_DYLIB'}
    $name=[Text.Encoding]::UTF8.GetString($b,232,32).TrimEnd([char]0)
    if($name -ne '@rpath/GlowESP.framework/GlowESP'){throw "Wrong library name: $name"}
}finally{$zip.Dispose()}
$devPlist=Join-Path $scratch 'development.plist'
[IO.File]::WriteAllText($devPlist,'<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Standoff2</string><key>CFBundleIdentifier</key><string>test.invalid</string><key>UIFileSharingEnabled</key><true/><key>LSSupportsOpeningDocumentsInPlace</key><true/></dict></plist>')
$devOutput=Join-Path $scratch 'development.ipa'
& (Join-Path $root 'package-windows.ps1') -SourceIPA $source -FrameworkDirectory $framework -OutputIPA $devOutput -DevelopmentInfoPlist $devPlist
$zip=[IO.Compression.ZipFile]::OpenRead($devOutput)
try{
    $reader=[IO.StreamReader]::new($zip.GetEntry('Payload/Test.app/Info.plist').Open())
    try{$info=[xml]$reader.ReadToEnd()}finally{$reader.Dispose()}
    if($info.SelectSingleNode('/plist/dict/key[text()="UIFileSharingEnabled"]/following-sibling::*[1]').Name -ne 'true'){throw 'Development document access not enabled'}
    if($info.SelectSingleNode('/plist/dict/key[text()="CFBundleIdentifier"]/following-sibling::*[1]').InnerText -ne 'test.invalid'){throw 'Application identity changed'}
}finally{$zip.Dispose()}
if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash){throw 'Development packaging modified the source'}
foreach($case in @('encrypted','padding')){
    $bad=New-TestIPA $case ($case -eq 'encrypted') ($case -eq 'padding')
    $target=Join-Path $scratch ($case+'-output.ipa')
    $rejected=$false
    try{& (Join-Path $root 'package-windows.ps1') -SourceIPA $bad -FrameworkDirectory $framework -OutputIPA $target}catch{$rejected=$true}
    if(!$rejected -or (Test-Path -LiteralPath $target)){throw "Unsafe input was not rejected before output creation: $case"}
}
Write-Output 'PASS: load command, embedded framework, unchanged source, development document access, preserved app identity, encrypted input rejection, nonzero padding rejection.'

