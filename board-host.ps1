# Windows launcher, supporting Windows PowerShell 5.1 and PowerShell 7.
[CmdletBinding()]
param(
    [ValidateSet('setup', 'reset')][string]$Operation = 'setup',
    [string]$Serial,
    [string]$RequestFile,
    [string]$SshKey,
    [string]$SshHost,
    [ValidateRange(1, 9999)][int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$stage = 'arguments'
$boardTemp = $null
$exitCode = 2
$machine = $PSBoundParameters.ContainsKey('RequestFile')
$sshRequested = $PSBoundParameters.ContainsKey('SshKey')
$result = $null
$Operation = $Operation.ToLowerInvariant()

function Invoke-Adb {
    param([string[]]$AdbArguments, [string]$InputFile)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $adbPath
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    if ($null -ne $start.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $AdbArguments) { $start.ArgumentList.Add($argument) }
    } else {
        # Windows native argument quoting, including trailing backslashes.
        $quoted = foreach ($argument in $AdbArguments) {
            '"' + [regex]::Replace([regex]::Replace($argument, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
        }
        $start.Arguments = $quoted -join ' '
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $inputStream = $null
    $started = $false
    try {
        $savedInputEncoding = $null
        try {
            if ($start.PSObject.Properties['StandardInputEncoding']) {
                $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
            } else {
                # .NET Framework creates the stdin writer from the console input encoding.
                try {
                    $savedInputEncoding = [Console]::InputEncoding
                    [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
                } catch {
                    if ($InputFile -and $savedInputEncoding -and $savedInputEncoding.GetPreamble().Length -gt 0) {
                        throw 'Cannot configure BOM-free ADB stdin encoding.'
                    }
                }
            }
            [void]$process.Start()
        } finally {
            if ($savedInputEncoding) { try { [Console]::InputEncoding = $savedInputEncoding } catch {} }
        }
        $started = $true
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $inputFailed = $false
        $timedOut = $false
        if ($InputFile) {
            $inputStream = [IO.File]::OpenRead($InputFile)
            # An early validation rejection may close stdin; still collect the worker result.
            try {
                $copyTask = $inputStream.CopyToAsync($process.StandardInput.BaseStream)
                $timedOut = -not $copyTask.Wait($TimeoutSeconds * 1000)
            } catch { $inputFailed = $true }
        }
        try { $process.StandardInput.Close() } catch { $inputFailed = $true }
        $remaining = [Math]::Max(1, $TimeoutSeconds * 1000 - [int]$watch.ElapsedMilliseconds)
        if ($timedOut -or -not $process.WaitForExit($remaining)) {
            $process.Kill()
            $process.WaitForExit()
            return [pscustomobject]@{ Code = 124; Output = ''; Error = 'ADB operation timed out.'; InputFailed = $inputFailed }
        }
        $output = $outputTask.Result
        $errors = $errorTask.Result
        if ($errors) { [Console]::Error.Write($errors) }
        return [pscustomobject]@{ Code = $process.ExitCode; Output = $output; Error = $errors; InputFailed = $inputFailed }
    } finally {
        if ($inputStream) { $inputStream.Dispose() }
        if ($started -and -not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
function Checked-Adb {
    param([string[]]$AdbArguments)
    $answer = Invoke-Adb -AdbArguments $AdbArguments
    if ($answer.Code -ne 0) { $script:exitCode = $answer.Code; throw 'ADB command failed.' }
    return $answer.Output.TrimEnd("`r", "`n")
}

try {
    if ($Serial -and $Serial -notmatch '^[A-Za-z0-9._:-]+$') { throw 'Invalid ADB serial.' }
    if ($SshHost -and -not $sshRequested) { throw '-SshHost requires -SshKey.' }
    if ($SshHost -and $SshHost -cnotmatch '\A[A-Za-z0-9:][A-Za-z0-9._:-]*\z') { throw 'Invalid SSH hostname or IP address.' }
    if ($sshRequested -and ($Operation -ne 'setup' -or [string]::IsNullOrEmpty($SshKey))) { throw '-SshKey requires setup and a public-key file path.' }
    . (Join-Path $PSScriptRoot 'host/board-ssh.ps1')
    if ($sshRequested) { Read-SshPublicKey -Path $SshKey }
    if ($machine) {
        if ([string]::IsNullOrEmpty($RequestFile)) { throw 'A request file path is required.' }
        if (-not $Serial) { throw 'Unattended runs require an explicit -Serial.' }
        $file = Get-Item -LiteralPath $RequestFile
        if ($file.PSIsContainer -or $file.Length -gt 65536 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Request must be a regular file of at most 64 KiB.' }
        $RequestFile = $file.FullName
        $acl = Get-Acl -LiteralPath $RequestFile
        $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        foreach ($rule in $acl.Access) {
            $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadData) -and $sid -notin @($owner, 'S-1-5-18', 'S-1-5-32-544')) { throw 'Request file is readable by another account; restrict its ACL first.' }
        }
    }
    $adbPath = (Get-Command adb -CommandType Application | Select-Object -First 1).Source
    $stage = 'device'
    if (-not $Serial) {
        $devices = @(foreach ($line in ((Checked-Adb -AdbArguments @('devices', '-l')) -split "`n")) {
            if ($line -match '^([^\s]+)\s+device(?:\s|$)') { $Matches[1] }
        })
        if ($devices.Count -ne 1) { throw 'Connect exactly one device, or select it with -Serial.' }
        $Serial = $devices[0]
    }
    if ($Serial -notmatch '^[A-Za-z0-9._:-]+$') { throw 'Invalid device serial.' }
    if ((Checked-Adb -AdbArguments @('-s', $Serial, 'get-state')) -ne 'device') { throw 'Selected device is not ready.' }
    $identity = Checked-Adb -AdbArguments @('-s', $Serial, 'shell', 'tr "\000" "\n" < /proc/device-tree/compatible')
    if ($identity -notmatch '(?m)^arduino,(imola|monza)\r?$') { throw 'Selected device is not an official Uno Q or Ventuno Q.' }
    $stage = 'upload'
    $candidate = Checked-Adb -AdbArguments @('-s', $Serial, 'shell', 'mktemp', '-d', '/tmp/arduino-board-tools.XXXXXX')
    if ($candidate -notmatch '^/tmp/arduino-board-tools\.[A-Za-z0-9]+$') { throw 'Unexpected board temporary directory.' }
    $boardTemp = $candidate
    $localFiles = @(); $remoteFiles = @(); $hashes = @()
    foreach ($name in @('board-common.sh', 'board-request.sh', 'setup-arduino-board.sh', 'reset-arduino-board.sh')) {
        $localFile = Join-Path (Join-Path $PSScriptRoot 'board') $name
        $localFiles += $localFile
        $remoteFiles += "$boardTemp/$name"
        $hashes += (Get-FileHash -LiteralPath $localFile -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    [void](Checked-Adb -AdbArguments (@('-s', $Serial, 'push') + $localFiles + @("$boardTemp/")))
    $remoteHashes = (Checked-Adb -AdbArguments (@('-s', $Serial, 'shell', 'sha256sum') + $remoteFiles)) -split '\r?\n'
    if ($remoteHashes.Count -ne $remoteFiles.Count) { throw 'Unexpected uploaded script hash results.' }
    for ($index = 0; $index -lt $remoteFiles.Count; $index++) {
        if ($remoteHashes[$index] -cne "$($hashes[$index])  $($remoteFiles[$index])") { throw 'Uploaded script hash or path mismatch.' }
    }
    $stage = 'transport'
    if ($machine) {
        $answer = Invoke-Adb -AdbArguments @('-s', $Serial, 'shell', '-T', 'bash', "$boardTemp/board-request.sh", $Operation) -InputFile $RequestFile
        $exitCode = $answer.Code
        $text = $answer.Output.TrimEnd("`r", "`n")
        $item = '"(hostname|keyboard|wifi|credentials|network|flags|verify)"'
        $list = '\[(' + $item + '(,' + $item + ')*)?\]'
        $pattern = '\A\{"version":1,"operation":"' + $Operation + '","status":"(ok|error)","stage":"(validate|preflight|hostname|keyboard|wifi|credentials|network|flags|verify|complete)","completed":' + $list + ',"skipped":' + $list + '\}\z'
        if ($text -cnotmatch $pattern) { throw 'No valid board result was received.' }
        $result = $text | ConvertFrom-Json
        if ($result.status -eq 'ok' -and $result.stage -ne 'complete') { throw 'No valid board result was received.' }
        if (($exitCode -ne 0 -or $answer.InputFailed) -and $result.status -eq 'ok') { throw 'Transport failed after a board result.' }
        if ($exitCode -eq 0 -and $result.status -eq 'error') { $exitCode = 1 }
    } else {
        & $adbPath -s $Serial shell -tt bash "$boardTemp/$Operation-arduino-board.sh"
        $exitCode = $LASTEXITCODE
    }
    if ($exitCode -eq 0 -and $Operation -eq 'setup') {
        if (-not $sshRequested -and -not $machine -and -not [Console]::IsInputRedirected) { $sshRequested = Offer-SshKey }
        if ($sshRequested) {
            $stage = 'ssh'
            Read-SshPublicKey -Path $SshKey
            Configure-BoardSsh -SshDirectory (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh') -Address $SshHost
        }
    }
    if ($machine) { [Console]::Out.WriteLine($text) }
} catch {
    if ($exitCode -eq 0) { $exitCode = 2 }
    [Console]::Error.WriteLine("Launcher failed at ${stage}: $($_.Exception.Message) Inspect board state before retrying.")
    if ($machine) {
        if ($stage -eq 'ssh' -and $result) {
            $result.status = 'error'; $result.stage = 'ssh'
            [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
        } else {
            [Console]::Out.WriteLine(([ordered]@{ version = 1; operation = $Operation; status = 'error'; stage = $stage; completed = @(); skipped = @() } | ConvertTo-Json -Compress))
        }
    }
} finally {
    $operationExitCode = $exitCode
    if ($boardTemp) {
        try {
            [void](Checked-Adb -AdbArguments @('-s', $Serial, 'shell', "rm -f -- $boardTemp/board-common.sh $boardTemp/board-request.sh $boardTemp/setup-arduino-board.sh $boardTemp/reset-arduino-board.sh && rmdir -- $boardTemp"))
        } catch { [Console]::Error.WriteLine("Cleanup failed; board temporary directory: $boardTemp. Configuration was not rolled back.") }
    }
    $exitCode = $operationExitCode
}
exit $exitCode
