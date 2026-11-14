# Run from an extracted release directory as the Windows desktop user.
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root=$PSScriptRoot
$expected=@{
 'launch-3d-demo-classic-titlebar.ps1'='E6709AD8F5DB213584DEF9D8AB513A20FA89E5DE14B3151AD63DC65FCC0E27EB'
 'native-present-copy-probe.exe'='6BEF5EAC5D4BB30E6D49DB6EE1612802EF6CE71C956D6132A639D2CC9BFA1C59'
 'supervise-app-probe-r2.ps1'='DEFA9B78D92538772E829C6A2F8656F96473A23A06408E55121E506E036F07D4'
}
foreach($name in $expected.Keys){
 $file=Join-Path $root $name
 if(-not[IO.File]::Exists($file)-or(Get-FileHash -LiteralPath $file).Hash-cne$expected[$name]){throw ('Package file differs: '+$name)}
}
$launcher=Join-Path $root 'launch-3d-demo-classic-titlebar.ps1'
$parseFiles=@($launcher,(Join-Path $root 'supervise-app-probe-r2.ps1'),$PSCommandPath)
foreach($file in $parseFiles){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ('PowerShell parse failed: '+$file)}
}
foreach($directory in @($root,(Join-Path $root 'runs'))){
 if(Test-Path -LiteralPath $directory){if(([IO.File]::GetAttributes($directory)-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'Package path must not be a reparse point'}}
 else{[void][IO.Directory]::CreateDirectory($directory)}
}
$desktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
if(-not[IO.Directory]::Exists($desktop)){throw 'Desktop directory missing'}
$destination=Join-Path $desktop 'DroidVM 3D-demo - klassieke titelbalk.lnk'
if(Test-Path -LiteralPath $destination){throw 'Shortcut already exists; no overwrite'}
$temp=Join-Path $desktop ('droidvm-demo-'+[Guid]::NewGuid().ToString('N')+'.lnk')
$shell=New-Object -ComObject WScript.Shell;$shortcut=$null
try{
 $shortcut=$shell.CreateShortcut($temp)
 $shortcut.TargetPath="$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
 $shortcut.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$launcher+'"'
 $shortcut.WorkingDirectory=$root;$shortcut.WindowStyle=7
 $shortcut.Description='30-second private-copy 3D demo with a classic titlebar; limited application workaround.'
 $shortcut.Save();[IO.File]::Move($temp,$destination)
 [ordered]@{shortcut=$destination;launcher=$launcher;autoStarted=$false;driverChanges=$false}|ConvertTo-Json
}finally{
 if($shortcut){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)}
 if($shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
 if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}
}
