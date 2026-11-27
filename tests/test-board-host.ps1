# SPDX-License-Identifier: MPL-2.0
# Run with Windows PowerShell 5.1; its compiler produces a runnable fake adb.exe.
param([string]$HostShell = 'powershell.exe')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$work = Join-Path ([IO.Path]::GetTempPath()) ('board-host-test-' + [guid]::NewGuid().ToString('N'))
$savedPath = $env:PATH
$savedInputEncoding = [Console]::InputEncoding
try {
    [Console]::InputEncoding = [Text.Encoding]::UTF8
    [void](New-Item -ItemType Directory -Path $work)
    $acl = Get-Acl -LiteralPath $work
    $acl.SetAccessRuleProtection($true, $false)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $work -AclObject $acl
    $env:BOARD_HOST_TEST_DIR = $work
    $repo = Join-Path $work 'repo with spaces'
    [void](New-Item -ItemType Directory -Path $repo)
    $boardDir = Join-Path $repo 'board'
    [void](New-Item -ItemType Directory -Path $boardDir)
    $launcher = Join-Path $repo 'board-host.ps1'
    $launcherText = [IO.File]::ReadAllText((Join-Path $repoRoot 'board-host.ps1')).Replace("(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh')", '(Join-Path $env:BOARD_HOST_TEST_DIR ''ssh'')')
    [IO.File]::WriteAllText($launcher, $launcherText, [Text.UTF8Encoding]::new($false))
    $hostDir = Join-Path $repo 'host'
    [void](New-Item -ItemType Directory -Path $hostDir)
    Copy-Item -LiteralPath (Join-Path $repoRoot 'host/board-ssh.ps1') -Destination $hostDir
    foreach ($name in @('board-common.sh', 'board-request.sh', 'setup-arduino-board.sh', 'reset-arduino-board.sh')) { Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'board') $name) -Destination $boardDir }
    $source = @'
using System;
using System.IO;
using System.Security.Cryptography;
class MockAdb {
    static int Main(string[] args) {
        string root = Environment.GetEnvironmentVariable("BOARD_HOST_TEST_DIR");
        string scenario = Environment.GetEnvironmentVariable("BOARD_HOST_TEST_CASE") ?? "";
        File.AppendAllText(Path.Combine(root, "log"), String.Join(" ", args) + "\n");
        if (args[0] == "devices") { Console.WriteLine("List of devices attached\nSERIAL device"); if (scenario == "multiple") Console.WriteLine("SECOND device"); return 0; }
        if (args[0] != "-s" || args[1] != "SERIAL") return 77;
        if (args[2] == "get-state") { Console.WriteLine("device"); return 0; }
        if (args[2] == "push") {
            if (scenario == "upload") return 9;
            string destination = args[args.Length - 1];
            for (int i = 3; i < args.Length - 1; i++) File.Copy(args[i], Path.Combine(root, Path.GetFileName(destination.EndsWith("/") ? args[i] : destination)), true);
            return 0;
        }
        if (args[2] != "shell") return 78;
        if (args[3].StartsWith("tr ")) { Console.WriteLine(scenario == "unsupported" ? "arduino,imola-evil" : "arduino,imola"); return 0; }
        if (args[3] == "mktemp") { Console.WriteLine(scenario == "badtemp" ? "/tmp/untrusted;command" : "/tmp/arduino-board-tools.TEST123"); return 0; }
        if (args[3] == "sha256sum") {
            for (int i = 4; i < args.Length; i++) {
                if (scenario == "hashmissing" && i == args.Length - 1) continue;
                string path = scenario == "hashduplicate" && i == args.Length - 1 ? args[4] : args[i];
                using (var hash = SHA256.Create()) {
                    var bytes = hash.ComputeHash(File.ReadAllBytes(Path.Combine(root, Path.GetFileName(path))));
                    Console.WriteLine((scenario == "hash" ? "broken" : BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant()) + "  " + path + (scenario == "hashpath" ? ".wrong" : "") + (scenario == "hashmalformed" ? " ignored" : ""));
                }
            }
            if (scenario == "hashextra") Console.WriteLine(new string('0', 64) + "  /tmp/arduino-board-tools.TEST123/extra.sh");
            return 0;
        }
        if (args[3] == "hostname") { Console.WriteLine(scenario == "badhostname" ? "bad name" : (scenario == "hostnamehost" ? "host" : "test-board")); return 0; }
        if (args[3] == "arduino-app-cli") { Console.WriteLine(scenario == "sshdisabled" ? "disabled" : "enabled"); return 0; }
        if (args[3] == "-T") {
            if (args[5] == "-c") {
                if (args[6] != "'source \"/tmp/arduino-board-tools.TEST123/board-common.sh\"; install_ssh_key'") return 80;
                File.WriteAllText(Path.Combine(root, "public-received"), Console.In.ReadToEnd());
                return scenario == "sshkeyfail" ? 13 : 0;
            }
            string operation = args[args.Length - 1];
            if (operation != "setup" && operation != "reset") {
                Console.WriteLine("{\"version\":1,\"operation\":\"unknown\",\"status\":\"error\",\"stage\":\"validate\",\"completed\":[],\"skipped\":[]}");
                return 2;
            }
            if (scenario == "earlyreject") {
                Console.WriteLine("{\"version\":1,\"operation\":\"setup\",\"status\":\"error\",\"stage\":\"validate\",\"completed\":[],\"skipped\":[]}");
                return 2;
            }
            File.WriteAllText(Path.Combine(root, "received"), Console.In.ReadToEnd());
            if (scenario == "timeout") System.Threading.Thread.Sleep(10000);
            if (scenario == "empty") return 0;
            if (scenario == "badresult") { Console.WriteLine("{\"version\":1,\"operation\":\"setup\",\"status\":\"unknown\"}"); return 0; }
            if (scenario == "badarray") { Console.WriteLine("{\"version\":1,\"operation\":\"setup\",\"status\":\"ok\",\"stage\":\"complete\",\"completed\":\"hostname\",\"skipped\":[]}"); return 0; }
            if (scenario == "badstage") { Console.WriteLine("{\"version\":1,\"operation\":\"setup\",\"status\":\"ok\",\"stage\":\"credentials\",\"completed\":[],\"skipped\":[]}"); return 0; }
            bool fail = scenario == "workerfail" || scenario == "cleanup";
            Console.WriteLine("{\"version\":1,\"operation\":\"" + operation + "\",\"status\":\"" + (fail ? "error" : "ok") + "\",\"stage\":\"" + (fail ? "credentials" : "complete") + "\",\"completed\":[\"hostname\"],\"skipped\":[]}");
            return fail ? 3 : 0;
        }
        if (args[3] == "-tt") { Console.WriteLine("Interactive wizard"); return 4; }
        if (args[3].StartsWith("rm -f -- ")) {
            if (args.Length != 4 || args[3] != "rm -f -- /tmp/arduino-board-tools.TEST123/board-common.sh /tmp/arduino-board-tools.TEST123/board-request.sh /tmp/arduino-board-tools.TEST123/setup-arduino-board.sh /tmp/arduino-board-tools.TEST123/reset-arduino-board.sh && rmdir -- /tmp/arduino-board-tools.TEST123") return 81;
            return scenario == "cleanup" ? 8 : 0;
        }
        if (args[3] == "rm" || args[3] == "rmdir") return scenario == "cleanup" ? 8 : 0;
        return 79;
    }
}
'@
    Add-Type -TypeDefinition $source -OutputAssembly (Join-Path $work 'adb.exe') -OutputType ConsoleApplication
    $env:PATH = "$work;$savedPath"
    $inputFile = Join-Path $work 'input'
    $inputText = "ARDUINO_BOARD_REQUEST_V1`r`nhostname=`r`npassword=fixture-secret`r`n"
    [IO.File]::WriteAllText($inputFile, $inputText, [Text.UTF8Encoding]::new($false))
    function Run-Launcher {
        param([string]$Scenario, [switch]$Human, [switch]$MissingSerial, [switch]$EmptyRequest, [string]$Operation = 'setup', [string]$Key, [string]$Address)
        $env:BOARD_HOST_TEST_CASE = $Scenario
        [IO.File]::WriteAllText((Join-Path $work 'log'), '')
        $outputFile = Join-Path $work 'output'
        $errorFile = Join-Path $work 'error'
        $limit = if ($Scenario -eq 'timeout') { '1' } else { '10' }
        $arguments = @('-NoProfile', '-File', (Join-Path $repo 'board-host.ps1'), '-Operation', $Operation, '-TimeoutSeconds', $limit)
        if (-not $Human) {
            $arguments += @('-RequestFile', $inputFile)
            if (-not $MissingSerial) { $arguments += @('-Serial', 'SERIAL') }
        }
        if ($Key) { $arguments += @('-SshKey', $Key) }
        if ($Address) { $arguments += @('-SshHost', $Address) }
        if ($EmptyRequest) {
            # Pass the empty value inside PowerShell; 5.1's native invocation drops empty arguments.
            $driver = Join-Path $work 'empty-request.ps1'
            $body = 'param([string]$Launcher)' + [Environment]::NewLine + '& $Launcher -Operation setup -Serial SERIAL -RequestFile ''''; exit $LASTEXITCODE'
            [IO.File]::WriteAllText($driver, $body, [Text.UTF8Encoding]::new($false))
            $arguments = @('-NoProfile', '-File', $driver, '-Launcher', (Join-Path $repo 'board-host.ps1'))
        }
        $ErrorActionPreference = 'Continue'
        & $HostShell @arguments >$outputFile 2>$errorFile
        $ErrorActionPreference = 'Stop'
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = (Get-Content -LiteralPath $outputFile -Raw); Error = (Get-Content -LiteralPath $errorFile -Raw); Log = (Get-Content -LiteralPath (Join-Path $work 'log') -Raw) }
    }
    $launchWatch = [Diagnostics.Stopwatch]::StartNew()
    $answer = Run-Launcher ''
    $launchWatch.Stop()
    Write-Output ('Mock successful PowerShell launch elapsed ({0}): {1:F3} s' -f $HostShell, $launchWatch.Elapsed.TotalSeconds)
    if ($answer.Code -ne 0) { throw ("PowerShell launch failed with code " + $answer.Code + ': ' + $answer.Log + (Get-Content -LiteralPath (Join-Path $work 'error') -Raw)) }
    if ([IO.File]::ReadAllText((Join-Path $work 'received')) -ne $inputText) { throw 'Request bytes changed.' }
    if ($answer.Log -match 'fixture-secret' -or $answer.Output -match 'fixture-secret' -or $answer.Error -match 'fixture-secret') { throw 'Secret leaked.' }
    $regressionFailures = @()
    $names = @('board-common.sh', 'board-request.sh', 'setup-arduino-board.sh', 'reset-arduino-board.sh')
    $expectedPush = '-s SERIAL push ' + (($names | ForEach-Object { Join-Path $boardDir $_ }) -join ' ') + ' /tmp/arduino-board-tools.TEST123/'
    if ([regex]::Matches($answer.Log, '(?m)^-s SERIAL push ').Count -ne 1 -or ($answer.Log -split "`n") -cnotcontains $expectedPush) { $regressionFailures += 'Payload upload was not one four-file push.' }
    $expectedHashes = '-s SERIAL shell sha256sum ' + (($names | ForEach-Object { '/tmp/arduino-board-tools.TEST123/' + $_ }) -join ' ')
    if ([regex]::Matches($answer.Log, '(?m)^-s SERIAL shell sha256sum ').Count -ne 1 -or ($answer.Log -split "`n") -cnotcontains $expectedHashes) { $regressionFailures += 'Payload hashes were not verified in one call.' }
    $expectedCleanup = '-s SERIAL shell rm -f -- ' + (($names | ForEach-Object { '/tmp/arduino-board-tools.TEST123/' + $_ }) -join ' ') + ' && rmdir -- /tmp/arduino-board-tools.TEST123'
    if ([regex]::Matches($answer.Log, '(?m)^-s SERIAL shell rm').Count -ne 1 -or $answer.Log -match 'shell rmdir' -or ($answer.Log -split "`n") -cnotcontains $expectedCleanup) { $regressionFailures += 'Cleanup was not one ordered shell command.' }
    foreach ($scenario in @('hashpath', 'hashmissing', 'hashextra', 'hashduplicate', 'hashmalformed')) {
        $answer = Run-Launcher $scenario
        if ($answer.Code -eq 0 -or ($answer.Output | ConvertFrom-Json).stage -ne 'upload' -or $answer.Log -match 'shell -T') { $regressionFailures += "Invalid hash response accepted: $scenario" }
    }
    if ($regressionFailures.Count) { throw ($regressionFailures -join "`n") }
    $answer = Run-Launcher '' -EmptyRequest
    if ($answer.Code -ne 2 -or $answer.Log -or ($answer.Output | ConvertFrom-Json).stage -ne 'arguments') { throw 'Empty request path did not stop before ADB.' }
    foreach ($operation in @('Setup', 'Reset')) {
        $answer = Run-Launcher '' -Operation $operation
        $result = $answer.Output | ConvertFrom-Json
        if ($answer.Code -ne 0 -or $result.operation -cne $operation.ToLowerInvariant()) { throw 'Capitalized operation was not normalized.' }
    }
    $answer = Run-Launcher '' -Operation Reset -Human
    if ($answer.Code -ne 4 -or $answer.Log -cnotmatch 'shell -tt bash /tmp/arduino-board-tools.TEST123/reset-arduino-board.sh') { throw 'Human reset used the wrong script name.' }
    foreach ($scenario in @('unsupported', 'badtemp', 'upload', 'hash', 'empty', 'badresult', 'badarray', 'badstage', 'timeout')) {
        $answer = Run-Launcher $scenario
        if ($answer.Code -eq 0 -or ($answer.Output | ConvertFrom-Json).status -ne 'error') { throw "Failure ignored: $scenario" }
    }
    foreach ($scenario in @('workerfail', 'cleanup')) {
        $answer = Run-Launcher $scenario
        if ($answer.Code -ne 3 -or ($answer.Output | ConvertFrom-Json).completed[0] -ne 'hostname') { throw 'Worker status or partial result was lost.' }
        if ($scenario -eq 'cleanup' -and $answer.Error -notlike '*Cleanup failed*') { throw 'Cleanup warning missing.' }
    }
    [IO.File]::WriteAllText($inputFile, (New-Object string('x', 65536)), [Text.UTF8Encoding]::new($false))
    $answer = Run-Launcher 'earlyreject'
    if ($answer.Code -ne 2 -or ($answer.Output | ConvertFrom-Json).stage -ne 'validate') { throw 'Early worker rejection was lost.' }
    [IO.File]::WriteAllText($inputFile, $inputText, [Text.UTF8Encoding]::new($false))
    $answer = Run-Launcher '' -MissingSerial
    if ($answer.Code -eq 0 -or $answer.Log) { throw 'Missing unattended serial reached ADB.' }
    $requestAcl = Get-Acl -LiteralPath $inputFile
    $publicRule = New-Object Security.AccessControl.FileSystemAccessRule([Security.Principal.SecurityIdentifier]::new('S-1-1-0'), 'Read', 'Allow')
    $requestAcl.AddAccessRule($publicRule)
    Set-Acl -LiteralPath $inputFile -AclObject $requestAcl
    $answer = Run-Launcher ''
    if ($answer.Code -eq 0 -or $answer.Log) { throw 'Public request file reached ADB.' }
    $requestAcl.RemoveAccessRuleSpecific($publicRule)
    Set-Acl -LiteralPath $inputFile -AclObject $requestAcl
    $answer = Run-Launcher 'multiple' -Human
    if ($answer.Code -eq 0 -or $answer.Log -match 'mktemp') { throw 'Ambiguous board was written.' }
    $answer = Run-Launcher '' -Human
    if ($answer.Code -ne 4 -or $answer.Log -notmatch 'shell -tt') { throw 'Interactive launch failed.' }
    $key = Join-Path $work 'key with spaces'
    $keygenStart = New-Object Diagnostics.ProcessStartInfo
    $keygenStart.FileName = (Get-Command ssh-keygen -CommandType Application | Select-Object -First 1).Source
    $keygenStart.Arguments = '-q -t ed25519 -N "" -f "' + $key + '"'
    $keygenStart.UseShellExecute = $false
    $keygenStart.CreateNoWindow = $true
    $keygenProcess = [Diagnostics.Process]::Start($keygenStart)
    try { $keygenProcess.WaitForExit(); if ($keygenProcess.ExitCode -ne 0) { throw 'Fixture key generation failed.' } }
    finally { $keygenProcess.Dispose() }
    $sshDir = Join-Path $work 'ssh'
    [void][IO.Directory]::CreateDirectory($sshDir)
    $directoryAcl = Get-Acl -LiteralPath $sshDir
    $directoryAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule([Security.Principal.SecurityIdentifier]::new('S-1-1-0'), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $sshDir -AclObject $directoryAcl
    $config = Join-Path $sshDir 'config'
    $existingConfig = "# BEGIN arduino-board-tools test-board-other`r`nHost test-board-other`r`n    HostName other.local`r`nHost *`r`n# END arduino-board-tools test-board-other`r`nCompression yes`r`nPort 2222`r`nPubkeyAuthentication no`r`nHost unrelated`r`n    HostName keep.example`r`n    User someone`r`n"
    [IO.File]::WriteAllText($config, $existingConfig, [Text.UTF8Encoding]::new($false))
    $answer = Run-Launcher '' -Key ($key + '.pub')
    if ($answer.Code -ne 0) { throw ('SSH integration failed: ' + $answer.Error) }
    $directoryAcl = Get-Acl -LiteralPath $sshDir
    if (-not $directoryAcl.AreAccessRulesProtected -or -not $directoryAcl.Access.Count) { throw 'SSH directory ACL is not protected.' }
    foreach ($rule in $directoryAcl.Access) {
        if ($rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ne $identity.Value -or
            $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne 'FullControl' -or
            $rule.InheritanceFlags -ne 'ContainerInherit,ObjectInherit' -or $rule.PropagationFlags -ne 'None') { throw 'SSH directory is not restricted to inheritable current-user access.' }
    }
    foreach ($rule in (Get-Acl -LiteralPath $config).Access) {
        if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ne $identity.Value) { throw 'Replaced SSH config is readable by another account.' }
    }
    $answer = Run-Launcher 'hostnamehost' -Key ($key + '.pub')
    $resolved = & ssh -G -T -F $config host
    if ($answer.Code -ne 0 -or $LASTEXITCODE -ne 0 -or $resolved -cnotcontains 'hostname host.local') { throw 'Board named host could not use a separate alias.' }
    $resolved = & ssh -G -T -F $config test-board
    if ($LASTEXITCODE -ne 0 -or $resolved -cnotcontains 'hostname test-board.local' -or $resolved -cnotcontains 'user arduino' -or $resolved -cnotcontains ('identityfile ' + $key.Replace('\', '/'))) { throw 'Board SSH alias or identity is wrong.' }
    if ($resolved -cnotcontains 'port 22' -or $resolved -cnotcontains 'pubkeyauthentication true') { throw 'Board inherited conflicting SSH defaults.' }
    $resolved = & ssh -G -T -F $config unrelated
    if ($LASTEXITCODE -ne 0 -or $resolved -cnotcontains 'user someone' -or $resolved -cnotcontains 'compression yes') { throw 'Existing SSH config changed scope.' }
    if ($resolved -cnotcontains 'port 2222' -or $resolved -cnotcontains 'pubkeyauthentication false') { throw 'Unrelated host lost SSH defaults.' }
    $normalizedKey = ([IO.File]::ReadAllText($key + '.pub').Trim() -split '\s+', 3)[0..1] -join ' '
    if ([IO.File]::ReadAllText((Join-Path $work 'public-received')) -cne ($normalizedKey + "`n")) { throw 'Wrong public key sent to ADB.' }
    if ($answer.Log -match 'BEGIN OPENSSH PRIVATE KEY') { throw 'Private key reached ADB.' }
    $answer = Run-Launcher '' -Key ($key + '.pub') -Address 192.0.2.1
    if ($answer.Code -ne 0) { throw ('Repeated SSH setup failed: ' + $answer.Error) }
    $goodConfig = [IO.File]::ReadAllText($config)
    if ([regex]::Matches($goodConfig, '(?m)^# BEGIN arduino-board-tools test-board$').Count -ne 1 -or -not $goodConfig.Contains('HostName 192.0.2.1') -or -not $goodConfig.EndsWith($existingConfig)) { throw 'Repeated SSH configuration lost or duplicated entries.' }
    foreach ($scenario in @('sshdisabled', 'badhostname', 'sshkeyfail')) {
        $answer = Run-Launcher $scenario -Key ($key + '.pub')
        $result = $answer.Output | ConvertFrom-Json
        if ($answer.Code -eq 0 -or $result.stage -ne 'ssh' -or $result.completed[0] -ne 'hostname' -or [IO.File]::ReadAllText($config) -cne $goodConfig) { throw "SSH failure lost config or board result: $scenario" }
    }
    [IO.File]::WriteAllText($config, "Host test-board`n    User another`n")
    $answer = Run-Launcher '' -Key ($key + '.pub')
    if ($answer.Code -eq 0 -or [IO.File]::ReadAllText($config) -cne "Host test-board`n    User another`n") { throw 'Unmanaged alias was overwritten.' }
    foreach ($content in @('NotAnSshOption yes', '# BEGIN arduino-board-tools test-board')) {
        [IO.File]::WriteAllText($config, $content + "`n")
        $answer = Run-Launcher '' -Key ($key + '.pub')
        if ($answer.Code -eq 0 -or [IO.File]::ReadAllText($config) -cne ($content + "`n") -or $answer.Log -match 'install_ssh_key') { throw 'Malformed config changed or reached key installation.' }
    }
    $answer = Run-Launcher '' -Key $key
    if ($answer.Code -eq 0 -or $answer.Log) { throw 'Private SSH key reached ADB.' }
    $badKey = Join-Path $work 'bad.pub'
    [IO.File]::WriteAllText($badKey, "ssh-ed25519 invalid`n")
    $answer = Run-Launcher '' -Key $badKey
    if ($answer.Code -ne 2 -or $answer.Log -or ($answer.Output | ConvertFrom-Json).stage -ne 'arguments') { throw 'Malformed SSH key did not fail at arguments.' }
    if ($answer.Error -notlike '*Invalid SSH public key.*') { throw 'Invalid SSH public key diagnostic was lost.' }
    $answer = Run-Launcher '' -Address 192.0.2.1
    if ($answer.Code -eq 0 -or $answer.Log) { throw 'SSH address without key reached ADB.' }
    $answer = Run-Launcher '' -Operation reset -Key ($key + '.pub')
    if ($answer.Code -eq 0 -or $answer.Log) { throw 'Reset accepted SSH installation.' }
    Remove-Item -LiteralPath $config
    $crlfKey = Join-Path $work 'crlf.pub'
    [IO.File]::WriteAllText($crlfKey, $normalizedKey + "`r`n", [Text.UTF8Encoding]::new($false))
    $answer = Run-Launcher '' -Key $crlfKey
    if ($answer.Code -ne 0) { throw ('New SSH config failed: ' + $answer.Error) }
    foreach ($rule in (Get-Acl -LiteralPath $config).Access) {
        if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ne $identity.Value) { throw 'SSH config is readable by another account.' }
    }
    if (@(Get-ChildItem -LiteralPath $sshDir -Filter '*.arduino.*').Count) { throw 'SSH temporary files were left behind.' }
    Write-Output "PowerShell host checks passed ($HostShell)."
} finally {
    [Console]::InputEncoding = $savedInputEncoding
    $env:PATH = $savedPath
    Remove-Item Env:BOARD_HOST_TEST_DIR, Env:BOARD_HOST_TEST_CASE -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($work)
    if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and (Split-Path $resolved -Leaf) -like 'board-host-test-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
