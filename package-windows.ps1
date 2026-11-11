param(
    [Parameter(Mandatory=$true)][string]$SourceIPA,
    [Parameter(Mandatory=$true)][string]$FrameworkDirectory,
    [Parameter(Mandatory=$true)][string]$OutputIPA
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$source=(Resolve-Path -LiteralPath $SourceIPA).Path
$framework=(Resolve-Path -LiteralPath $FrameworkDirectory).Path
$output=[IO.Path]::GetFullPath($OutputIPA)
if($source -eq $output){throw 'Output must differ from original IPA'}
if(Test-Path -LiteralPath $output){throw 'Output already exists; choose a new filename'}
if(!(Test-Path -LiteralPath (Join-Path $framework 'GlowESP')) -or !(Test-Path -LiteralPath (Join-Path $framework 'Info.plist'))){throw 'A compiled GlowESP.framework is required; source files alone cannot be packaged'}
$frameworkBytes=[IO.File]::ReadAllBytes((Join-Path $framework 'GlowESP'))
if($frameworkBytes.Length -lt 32 -or [BitConverter]::ToUInt32($frameworkBytes,0) -ne 4277009103 -or [BitConverter]::ToUInt32($frameworkBytes,4) -ne 16777228 -or [BitConverter]::ToUInt32($frameworkBytes,12) -ne 6){throw 'Framework executable must be a thin arm64 Mach-O dylib'}

function Add-GlowLoadCommand([byte[]]$binary){
    if([BitConverter]::ToUInt32($binary,0) -ne 4277009103 -or [BitConverter]::ToUInt32($binary,4) -ne 16777228){throw 'Expected a thin arm64 Mach-O main executable'}
    $count=[BitConverter]::ToUInt32($binary,16)
    $commandBytes=[BitConverter]::ToUInt32($binary,20)
    $end=32+[int]$commandBytes
    $cursor=32
    $firstData=$binary.Length
    $installName='@rpath/GlowESP.framework/GlowESP'
    for($i=0;$i -lt $count;$i++){
        if($cursor+8 -gt $end){throw 'Malformed Mach-O commands'}
        $cmd=[BitConverter]::ToUInt32($binary,$cursor)
        $size=[BitConverter]::ToUInt32($binary,$cursor+4)
        if($size -lt 8 -or $cursor+$size -gt $end){throw 'Malformed Mach-O command size'}
        if($cmd -eq 44 -and [BitConverter]::ToUInt32($binary,$cursor+16) -ne 0){throw 'Main executable remains encrypted'}
        if($cmd -eq 12){
            $offset=[BitConverter]::ToUInt32($binary,$cursor+8)
            $name=[Text.Encoding]::UTF8.GetString($binary,$cursor+$offset,$size-$offset).TrimEnd([char]0)
            if($name -eq $installName){throw 'GlowESP load command already present'}
        }
        if($cmd -eq 25){
            $sections=[BitConverter]::ToUInt32($binary,$cursor+64)
            if(72+80*$sections -gt $size){throw 'Malformed section table'}
            for($j=0;$j -lt $sections;$j++){
                $dataOffset=[BitConverter]::ToUInt32($binary,$cursor+72+80*$j+48)
                if($dataOffset -gt 0){$firstData=[Math]::Min($firstData,$dataOffset)}
            }
        }
        $cursor+=$size
    }
    if($cursor -ne $end){throw 'Mach-O command count and size disagree'}
    $nameBytes=[Text.Encoding]::UTF8.GetBytes($installName+[char]0)
    $newSize=[int]([Math]::Ceiling((24+$nameBytes.Length)/8)*8)
    if($end+$newSize -gt $firstData){throw 'Insufficient load-command padding; no IPA was modified'}
    for($i=$end;$i -lt $end+$newSize;$i++){if($binary[$i] -ne 0){throw 'Nonzero bytes in header padding; refusing to overwrite'}}
    [BitConverter]::GetBytes([uint32]12).CopyTo($binary,$end)
    [BitConverter]::GetBytes([uint32]$newSize).CopyTo($binary,$end+4)
    [BitConverter]::GetBytes([uint32]24).CopyTo($binary,$end+8)
    $nameBytes.CopyTo($binary,$end+24)
    [BitConverter]::GetBytes([uint32]($count+1)).CopyTo($binary,16)
    [BitConverter]::GetBytes([uint32]($commandBytes+$newSize)).CopyTo($binary,20)
    return ,$binary
}

# Validate and prepare the small executable in memory before copying the IPA.
$zip=[IO.Compression.ZipFile]::OpenRead($source)
try{
    $apps=@($zip.Entries | Where-Object {$_.FullName -match '^Payload/[^/]+\.app/Standoff2$'})
    if($apps.Count -ne 1){throw 'Expected exactly one Standoff2 executable'}
    $exePath=$apps[0].FullName
    $appRoot=$exePath.Substring(0,$exePath.LastIndexOf('/')+1)
    $stream=$apps[0].Open();$memory=[IO.MemoryStream]::new()
    try{$stream.CopyTo($memory);$patched=Add-GlowLoadCommand $memory.ToArray()}finally{$stream.Dispose();$memory.Dispose()}
    if($zip.Entries.FullName -contains ($appRoot+'Frameworks/GlowESP.framework/GlowESP')){throw 'Framework already embedded'}
}finally{$zip.Dispose()}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::Copy($source,$output,$false)
$zip=[IO.Compression.ZipFile]::Open($output,[IO.Compression.ZipArchiveMode]::Update)
try{
    $zip.GetEntry($exePath).Delete()
    $entry=$zip.CreateEntry($exePath,[IO.Compression.CompressionLevel]::Optimal)
    $stream=$entry.Open();try{$stream.Write($patched,0,$patched.Length)}finally{$stream.Dispose()}
    foreach($file in Get-ChildItem -LiteralPath $framework -File -Recurse){
        $relative=$file.FullName.Substring($framework.TrimEnd('\','/').Length+1).Replace('\','/')
        if($relative -match '(^|/)\.\.(/|$)'){throw 'Unexpected framework path'}
        $target=$appRoot+'Frameworks/GlowESP.framework/'+$relative
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$target,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
}finally{$zip.Dispose()}
Write-Output "Created unsigned IPA: $output"
Write-Output 'All executable code must be re-signed, including GlowESP.framework. Installation and runtime behavior have not been verified.'
