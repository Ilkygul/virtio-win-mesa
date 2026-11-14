param([Parameter(Mandatory=$true)][string]$RunDirectory)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$plan=Get-Content (Join-Path $RunDirectory 'plan.json') -Raw|ConvertFrom-Json
$record=Join-Path $RunDirectory 'supervisor.json';$started=[DateTime]::UtcNow.ToString('o')
if(Test-Path $record){throw 'Supervisor record already exists; use a fresh owned run'}
if((Get-FileHash -LiteralPath $plan.executable -Algorithm SHA256).Hash-ne$plan.executableSha256){throw 'Probe executable hash changed'}
if(Test-Path $plan.output){throw 'Benchmark output already exists; refusing to overwrite'}
function Write-Record($Value){
 $tmp=$record+'.tmp';[IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
 if(Test-Path $record){[IO.File]::Replace($tmp,$record,($record+'.previous'))}else{[IO.File]::Move($tmp,$record)}
}
$si=New-Object Diagnostics.ProcessStartInfo
$si.FileName=$plan.executable;$si.Arguments=$plan.arguments;$si.WorkingDirectory=$RunDirectory
$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
$p=New-Object Diagnostics.Process;$p.StartInfo=$si
$childPid=$null;$actualExitCode=$null
try{
 if(!$p.Start()){throw 'Probe child did not start'}
 $childPid=$p.Id
 $ownedHandle=$p.Handle # Keep the actual owned Process handle through exit observation.
 $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync()
 Write-Record ([ordered]@{status='running';runName=$plan.runName;supervisorStartedAt=$started;child_pid=$p.Id;executableSha256=$plan.executableSha256;arguments=$plan.arguments})
 if(!$p.WaitForExit(90000)){
  Write-Record ([ordered]@{status='observation_timeout_child_not_proven_stopped';runName=$plan.runName;supervisorStartedAt=$started;child_pid=$p.Id})
  exit 124 # Do not kill another process or pretend the owned child stopped.
 }
 $p.WaitForExit();$p.Refresh();$exitCode=$p.ExitCode
 if($null-eq$exitCode){throw 'Actual child exit code unavailable'}
 $actualExitCode=[int]$exitCode
 $exitUnsigned=[BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$exitCode),0)
 Write-Record ([ordered]@{status='exited';runName=$plan.runName;supervisorStartedAt=$started;finishedAt=[DateTime]::UtcNow.ToString('o');child_pid=$p.Id;exit_code=[int]$exitCode;exit_hex=('0x{0:X8}' -f $exitUnsigned);stdout=$outTask.Result;stderr=$errTask.Result})
 exit $exitCode
}catch{
 $failure=$_.Exception.Message
 $failed=[ordered]@{status='supervisor_failed';runName=$plan.runName;supervisorStartedAt=$started;finishedAt=[DateTime]::UtcNow.ToString('o');child_pid=$childPid;actualChildExitObserved=($null-ne$actualExitCode);exit_code=$actualExitCode;error=$failure}
 # Independent best-effort CreateNew evidence: never overwrite historical records,
 # and never invent exit0 when the owned Process did not supply an exit code.
 try{
  $fallback=Join-Path $RunDirectory 'exit-evidence.json'
  $bytes=[Text.Encoding]::UTF8.GetBytes(($failed|ConvertTo-Json -Depth 6))
  $file=[IO.File]::Open($fallback,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{$file.Write($bytes,0,$bytes.Length);$file.Flush()}finally{$file.Dispose()}
 }catch{[Console]::Error.WriteLine('Supervisor exit-evidence persistence failed: '+$_.Exception.Message)}
 try{Write-Record $failed}catch{[Console]::Error.WriteLine('Supervisor primary record persistence failed: '+$_.Exception.Message)}
 [Console]::Error.WriteLine('Supervisor failed: '+$failure)
 exit 1
}finally{$p.Dispose()}
