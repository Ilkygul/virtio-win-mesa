# Fixed 30-second demo: private frame copy and an owned classic titlebar.
# Only the bundled immutable demo is launched; other application windows are untouched.
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root=$PSScriptRoot
$runs=Join-Path $root 'runs'
foreach($directory in @($root,$runs)){
 if(-not[IO.Directory]::Exists($directory)-or(([IO.File]::GetAttributes($directory)-band[IO.FileAttributes]::ReparsePoint)-ne0)){throw 'Existing package directories required'}
}
$name='3d-classic-titlebar-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')+'-'+[Guid]::NewGuid().ToString('N')
$run=Join-Path $runs $name
if(Test-Path -LiteralPath $run){throw 'Fresh demo run already exists'}
function Read-SharedJson([string]$Path){
 try{$f=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]7)}catch [IO.FileNotFoundException]{return $null}
 $r=New-Object IO.StreamReader($f);try{$text=$r.ReadToEnd()}finally{$r.Dispose();$f.Dispose()}
 if($text){return($text|ConvertFrom-Json)};return $null
}
function Save-New($Value){
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 8)+"`r`n")
 $f=[IO.File]::Open((Join-Path $run 'nonclient-result.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
}
# Compile before starting either supervisor or workload. No benchmark DLL injection.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class C27OwnedNc {
 [StructLayout(LayoutKind.Sequential)] struct RECT { public int L,T,R,B; }
 [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr h,StringBuilder name,int count);
 [DllImport("user32.dll",SetLastError=true)] static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
 [DllImport("user32.dll",SetLastError=true)] static extern bool RedrawWindow(IntPtr h,IntPtr rect,IntPtr region,uint flags);
 [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h,uint attr,ref int value,uint size);
 [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h,uint attr,out int value,uint size);
 public static bool Exists(IntPtr h){return IsWindow(h);}
 public static void Own(IntPtr h,uint expected){uint pid;var c=new StringBuilder(128);if(h==IntPtr.Zero||!IsWindow(h)||GetWindowThreadProcessId(h,out pid)==0||pid!=expected||GetClassNameW(h,c,c.Capacity)==0||c.ToString()!="CodexNativePresentCopyProbe")throw new InvalidOperationException("HWND owner/class mismatch");}
 public static int[] Client(IntPtr h,uint pid){Own(h,pid);RECT r;if(!GetClientRect(h,out r))throw new Win32Exception();return new[]{r.R-r.L,r.B-r.T};}
 public static int Enabled(IntPtr h,uint pid){Own(h,pid);int value;int hr=DwmGetWindowAttribute(h,1,out value,4);if(hr<0)Marshal.ThrowExceptionForHR(hr);return value;}
 public static int Policy(IntPtr h,uint pid,int policy){Own(h,pid);return DwmSetWindowAttribute(h,2,ref policy,4);}
 public static void RefreshFrame(IntPtr h,uint pid){Own(h,pid);if(!SetWindowPos(h,IntPtr.Zero,0,0,0,0,0x37))throw new Win32Exception();Own(h,pid);if(!RedrawWindow(h,IntPtr.Zero,IntPtr.Zero,0x501))throw new Win32Exception();}
}
'@
$exe=Join-Path $root 'native-present-copy-probe.exe';$sup=Join-Path $root 'supervise-app-probe-r2.ps1'
$exeSha='6BEF5EAC5D4BB30E6D49DB6EE1612802EF6CE71C956D6132A639D2CC9BFA1C59';$supSha='DEFA9B78D92538772E829C6A2F8656F96473A23A06408E55121E506E036F07D4'
$argsExpected='--warmup 1 --duration 30 --width 960 --height 640 --vsync 1 --private-copy 1 --output "'+$run+'\benchmark.json"'
if((Get-FileHash -LiteralPath $exe).Hash-cne$exeSha-or(Get-FileHash -LiteralPath $sup).Hash-cne$supSha){throw 'Immutable EXE/supervisor differs'}
[void][IO.Directory]::CreateDirectory($run)
$planPath=Join-Path $run 'plan.json'
$newPlan=[ordered]@{runName=$name;wrapperSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;executable=$exe;executableSha256=$exeSha;output=($run+'\benchmark.json');arguments=$argsExpected;scope='Fixed 30s 3D demo with classic owned titlebar; no general application workaround or benchmark acceptance claim.'}
$planBytes=[Text.UTF8Encoding]::new($false).GetBytes(($newPlan|ConvertTo-Json -Depth 6)+"`r`n")
$planFile=[IO.File]::Open($planPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$planFile.Write($planBytes,0,$planBytes.Length);$planFile.Flush($true)}finally{$planFile.Dispose()}
$planSha256=(Get-FileHash -LiteralPath $planPath).Hash
$plan=Read-SharedJson $planPath
if($plan.runName-cne$name-or$plan.executable-ine$exe-or$plan.arguments-cne$argsExpected-or$plan.output-ine($run+'\benchmark.json')-or$plan.executableSha256-cne$exeSha-or$plan.wrapperSha256-cne(Get-FileHash -LiteralPath $PSCommandPath).Hash){throw 'Owned plan mismatch'}
if((Get-FileHash -LiteralPath $exe).Hash-cne$exeSha-or(Get-FileHash -LiteralPath $sup).Hash-cne$supSha){throw 'Immutable EXE/supervisor differs'}
foreach($file in @('supervisor.json','benchmark.json','nonclient-result.json')){if(Test-Path -LiteralPath (Join-Path $run $file)){throw 'Run already used'}}
foreach($m in @('triton-presentwritesync','triton-dwmwritesync')){if(-not[IO.File]::Exists('C:\Users\Public\'+$m)-or([IO.FileInfo]::new('C:\Users\Public\'+$m)).Length-ne0){throw 'Strict marker must remain empty ON'}}
$result=[ordered]@{runName=$name;planSha256=$planSha256;startedUtc=[DateTime]::UtcNow.ToString('o');valid=$false;scope='Owned HWND policy only; no pixel/readability claim';applied=$false;policyAttempted=$false;restoreAttempted=$false;restored=$false;error=$null;supervisorExit=$null;supervisorStderr=$null;child=$null;childNaturalExitObserved=$false;childExit=$null}
$supervisor=$null;$held=$null;$hwnd=[IntPtr]::Zero;$exit=1;$birth=$null
function Still-Owned {
 if(-not$held){return $false};$held.Refresh()
 if(-not[C27OwnedNc]::Exists($hwnd)-or$held.HasExited-or$held.StartTime.ToUniversalTime().ToString('o')-cne$birth){return $false}
 [C27OwnedNc]::Own($hwnd,[uint32]$held.Id);return $true
}
function Restore-Owned {
 if($result.policyAttempted-and-not$result.restoreAttempted){
  $result.restoreAttempted=$true
  if(Still-Owned){$result.restoreHr=[C27OwnedNc]::Policy($hwnd,[uint32]$held.Id,0);if($result.restoreHr-lt0){throw 'Restore policy failed'};[C27OwnedNc]::RefreshFrame($hwnd,[uint32]$held.Id);$result.restored=([C27OwnedNc]::Enabled($hwnd,[uint32]$held.Id)-eq$result.beforeEnabled)}
  else{$result.restoreScope='Owned window/process ended; per-window setting destroyed, no other HWND touched';$result.restored=$true}
 }
}
try{
 if((Get-FileHash -LiteralPath $planPath).Hash-cne$planSha256){throw 'Fresh plan changed before supervisor launch'}
 $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName="$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe";$si.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$sup+'" -RunDirectory "'+$run+'"';$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 $supervisor=New-Object Diagnostics.Process;$supervisor.StartInfo=$si;$launchUtc=[DateTime]::UtcNow
 if(-not$supervisor.Start()){throw 'Supervisor did not start'};$supHandle=$supervisor.Handle;$out=$supervisor.StandardOutput.ReadToEndAsync();$err=$supervisor.StandardError.ReadToEndAsync();$result.supervisorPid=$supervisor.Id
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while($clock.Elapsed.TotalSeconds-lt30){
  $record=Read-SharedJson (Join-Path $run 'supervisor.json')
  if($record-and$record.child_pid){
   if($record.runName-cne$name-or$record.status-ne'running'-or$record.executableSha256-cne$exeSha-or$record.arguments-cne$argsExpected){throw 'Fresh running supervisor identity differs'}
   if(-not$held){$held=Get-Process -Id ([int]$record.child_pid) -ErrorAction Stop;$ownedHandle=$held.Handle;$birth=$held.StartTime.ToUniversalTime().ToString('o');$info=Get-CimInstance Win32_Process -Filter ('ProcessId='+$held.Id);if($held.ProcessName-cne'native-present-copy-probe'-or$held.MainModule.FileName-ine$exe-or(Get-FileHash -LiteralPath $held.MainModule.FileName).Hash-cne$exeSha-or$held.StartTime.ToUniversalTime()-lt$launchUtc.AddSeconds(-1)-or$held.SessionId-ne([Diagnostics.Process]::GetCurrentProcess().SessionId)-or$info.ParentProcessId-ne$supervisor.Id){throw 'Actual child path/hash/birth/session/parent mismatch'};$result.child=[ordered]@{id=$held.Id;startUtc=$birth;path=$exe;sha256=$exeSha;parentPid=$info.ParentProcessId}}
   $held.Refresh();if($held.HasExited){throw 'Child exited before policy could be applied'};$hwnd=$held.MainWindowHandle
   if($hwnd-ne[IntPtr]::Zero){break}
  }
  Start-Sleep -Milliseconds 50
 }
 if($hwnd-eq[IntPtr]::Zero-or-not(Still-Owned)){throw 'Owned window not observed before bounded deadline'}
 $result.hwnd=$hwnd.ToInt64();$result.beforeClient=@([C27OwnedNc]::Client($hwnd,[uint32]$held.Id));$result.beforeEnabled=[C27OwnedNc]::Enabled($hwnd,[uint32]$held.Id)
 if($result.beforeClient[0]-ne960-or$result.beforeClient[1]-ne640-or$result.beforeEnabled-ne1){throw 'Client must be960x640 and nonclient initially enabled'}
 $result.policyAttempted=$true;$result.setHr=[C27OwnedNc]::Policy($hwnd,[uint32]$held.Id,1);if($result.setHr-lt0){throw 'Set policy failed'};$result.applied=$true;$result.appliedUtc=[DateTime]::UtcNow.ToString('o');[C27OwnedNc]::RefreshFrame($hwnd,[uint32]$held.Id)
 $result.afterEnabled=[C27OwnedNc]::Enabled($hwnd,[uint32]$held.Id);$result.afterClient=@([C27OwnedNc]::Client($hwnd,[uint32]$held.Id))
 if($result.afterEnabled-ne0-or$result.afterClient[0]-ne960-or$result.afterClient[1]-ne640){throw 'Policy ignored or client geometry changed; invalid trial'}
 $result.valid=$true
}catch{$result.error=$_.Exception.Message;$result.valid=$false;try{Restore-Owned}catch{$result.restoreError=$_.Exception.Message}}
finally{
 try{if($supervisor){if($supervisor.WaitForExit(95000)){$supervisor.WaitForExit();$result.supervisorExit=$supervisor.ExitCode;$result.supervisorStdout=$out.Result;$result.supervisorStderr=$err.Result}else{$result.valid=$false;$result.error='Supervisor not proven stopped; retain child/VM, no kill'}}}catch{$result.valid=$false;$result.waitError=$_.Exception.Message}
 try{Restore-Owned}catch{$result.valid=$false;$result.restoreError=$_.Exception.Message}
 if($held){$held.Refresh();$result.childNaturalExitObserved=$held.HasExited;if($held.HasExited){$held.WaitForExit();$result.childExit=$held.ExitCode};$held.Dispose()}
 if($supervisor){$supervisor.Dispose()}
 $result.finishedUtc=[DateTime]::UtcNow.ToString('o');Save-New $result
}
if($result.valid-and$result.restored-and$result.supervisorExit-eq0-and$result.supervisorStderr-eq''-and$result.childNaturalExitObserved-and$result.childExit-eq0){$exit=0}
exit $exit
