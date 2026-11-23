# Optional host SSH integration for PowerShell 5.1/7.
function Read-SshPublicKey {
    param([string]$Path)
    if ($Path -match '^~[/\\]') { $Path = Join-Path ([Environment]::GetFolderPath('UserProfile')) $Path.Substring(2) }
    $script:sshClient = (Get-Command ssh -CommandType Application | Select-Object -First 1).Source
    $keygen = (Get-Command ssh-keygen -CommandType Application | Select-Object -First 1).Source
    $file = Get-Item -LiteralPath $Path
    if ($file.PSIsContainer -or $file.Length -gt 16384) { throw 'Choose one SSH public key of at most 16 KiB.' }
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { throw 'Public key must not contain NUL bytes.' }
    $key = ([Text.UTF8Encoding]::new($false, $true)).GetString($bytes)
    if ($key.EndsWith(([char]10).ToString())) { $key = $key.Substring(0, $key.Length - 1) }
    if ($key.EndsWith(([char]13).ToString())) { $key = $key.Substring(0, $key.Length - 1) }
    if ($key -cnotmatch '\A([A-Za-z0-9@._+-]+)[ \t]+([A-Za-z0-9+/]+={0,3})(?:[ \t]+[^\r\n]*)?\z') { throw 'Choose a single OpenSSH public key, without authorized_keys options.' }
    $script:sshPublicKey = $Matches[1] + ' ' + $Matches[2]
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $keygen -l -f $file.FullName >$null 2>$null
    } finally { $ErrorActionPreference = $savedErrorActionPreference }
    if ($LASTEXITCODE -ne 0) { throw 'Invalid SSH public key.' }
    $script:sshIdentity = $file.FullName
    if ($file.FullName.EndsWith('.pub') -and (Test-Path -LiteralPath $file.FullName.Substring(0, $file.FullName.Length - 4) -PathType Leaf)) { $script:sshIdentity = $file.FullName.Substring(0, $file.FullName.Length - 4) }
}

function Offer-SshKey {
    $answer = Read-Host 'Install your SSH public key and configure ssh <board-name>? [y/N]'
    if ($answer -notin @('y', 'yes')) { return $false }
    $defaultKey = ''
    foreach ($name in @('id_ed25519.pub', 'id_rsa.pub')) {
        $candidate = Join-Path ([Environment]::GetFolderPath('UserProfile')) ('.ssh/' + $name)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $defaultKey = $candidate; break }
    }
    $script:SshKey = Read-Host "Public-key file [$defaultKey]"
    if (-not $SshKey) { $script:SshKey = $defaultKey }
    $script:SshHost = Read-Host 'SSH address (blank uses the board hostname with .local)'
    return $true
}

function Configure-BoardSsh {
    param([string]$SshDirectory, [string]$Address)
    $mode = Checked-Adb -AdbArguments @('-s', $Serial, 'shell', 'arduino-app-cli', 'system', 'network-mode', 'status')
    if ($mode -ne 'enabled') { throw 'SSH configuration requires enabled Network Mode; rerun setup to enable it.' }
    $name = Checked-Adb -AdbArguments @('-s', $Serial, 'shell', 'hostname')
    if ($name -cnotmatch '\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z') { throw 'Invalid board hostname.' }
    if (-not $Address) { $Address = $name + '.local' }
    if ($Address -cnotmatch '\A[A-Za-z0-9:][A-Za-z0-9._:-]*\z') { throw 'SSH address must be a hostname or IP address.' }
    $identityPath = $sshIdentity.Replace('\', '/')
    if ($identityPath.Contains(([char]10).ToString()) -or $identityPath.Contains(([char]13).ToString()) -or $identityPath.Contains('${')) { throw 'Unsupported SSH identity path.' }
    $identityPath = $identityPath.Replace('"', '\"').Replace('%', '%%')
    $config = Join-Path $SshDirectory 'config'
    foreach ($path in @($SshDirectory, $config)) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'SSH config and directory must not be symlinks.' }
    }
    $oldText = ''
    if (Test-Path -LiteralPath $config) {
        if ((Get-Item -LiteralPath $config).PSIsContainer) { throw 'SSH config must be a regular file.' }
        $oldText = [IO.File]::ReadAllText($config, [Text.UTF8Encoding]::new($false, $true))
    }
    $begin = '# BEGIN arduino-board-tools ' + $name
    $end = '# END arduino-board-tools ' + $name
    $pattern = '(?ms)^' + [regex]::Escape($begin) + '\r?\n.*?^' + [regex]::Escape($end) + '(?:\r?\n|$)'
    $blocks = [regex]::Matches($oldText, $pattern)
    $body = [regex]::Replace($oldText, $pattern, '')
    $markerPattern = '(?m)^(?:' + [regex]::Escape($begin) + '|' + [regex]::Escape($end) + ')\r?$'
    if ($blocks.Count -gt 1 -or [regex]::IsMatch($body, $markerPattern)) { throw 'Malformed managed SSH config block.' }
    foreach ($line in ($body -split '\r?\n')) {
        $words = (($line -split '#', 2)[0].Replace('=', ' ').Replace('"', '')).Trim() -split '\s+'
        if ($words[0] -ieq 'Host' -and @($words | Select-Object -Skip 1) -icontains $name) { throw 'An unmanaged SSH alias already uses this board name.' }
    }
    $newline = ([char]10).ToString()
    $block = @($begin, "Host $name", "    HostName $Address", '    Port 22', '    User arduino', '    PubkeyAuthentication yes', ('    IdentityFile "' + $identityPath + '"'), '    IdentitiesOnly yes', 'Host *', $end) -join $newline
    [void][IO.Directory]::CreateDirectory($SshDirectory)
    # Protect the directory before creating files; directory rights can bypass file ACLs.
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $directoryAcl = Get-Acl -LiteralPath $SshDirectory
    $protect = -not $directoryAcl.AreAccessRulesProtected -or $directoryAcl.Access.Count -eq 0
    foreach ($rule in $directoryAcl.Access) {
        if ($rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ne $owner.Value -or
            $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne 'FullControl' -or
            $rule.InheritanceFlags -ne 'ContainerInherit,ObjectInherit' -or $rule.PropagationFlags -ne 'None') { $protect = $true }
    }
    if ($protect) {
        $directoryAcl.SetAccessRuleProtection($true, $false)
        foreach ($rule in $directoryAcl.Access) { $directoryAcl.RemoveAccessRuleSpecific($rule) }
        $directoryAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($owner, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Acl -LiteralPath $SshDirectory -AclObject $directoryAcl
    }
    $temp = Join-Path $SshDirectory ('config.arduino.' + [guid]::NewGuid().ToString('N'))
    $publicTemp = Join-Path $SshDirectory ('public.arduino.' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temp, $block + $newline + $body, [Text.UTF8Encoding]::new($false))
        $acl = Get-Acl -LiteralPath $temp
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($owner, 'FullControl', 'Allow')))
        Set-Acl -LiteralPath $temp -AclObject $acl
        & $sshClient -G -T -F $temp $name >$null
        if ($LASTEXITCODE -ne 0) { throw 'SSH rejected the proposed config; existing config was preserved.' }
        [IO.File]::WriteAllText($publicTemp, $sshPublicKey + $newline, [Text.UTF8Encoding]::new($false))
        $command = "'source " + '"' + $boardTemp + '/board-common.sh"; install_ssh_key' + "'"
        $answer = Invoke-Adb -AdbArguments @('-s', $Serial, 'shell', '-T', 'bash', '-c', $command) -InputFile $publicTemp
        if ($answer.Code -ne 0 -or $answer.InputFailed) { throw 'SSH public-key installation failed; host config was preserved.' }
        try {
            if (Test-Path -LiteralPath $config) {
                # Replace preserves the destination ACL; restrict it only when needed.
                $configAcl = Get-Acl -LiteralPath $config
                $protect = -not $configAcl.AreAccessRulesProtected
                foreach ($rule in $configAcl.Access) { if ($rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ne $owner.Value) { $protect = $true } }
                if ($protect) {
                    $configAcl.SetAccessRuleProtection($true, $false)
                    foreach ($rule in $configAcl.Access) { $configAcl.RemoveAccessRuleSpecific($rule) }
                    $configAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($owner, 'FullControl', 'Allow')))
                    Set-Acl -LiteralPath $config -AclObject $configAcl
                }
                [IO.File]::Replace($temp, $config, [NullString]::Value)
            } else { [IO.File]::Move($temp, $config) }
        } catch { throw "Public key was installed, but saving or protecting the host SSH config failed: $($_.Exception.Message)" }
        [Console]::Error.WriteLine("SSH configured: ssh $name (requires network access to $Address).")
    } finally {
        foreach ($path in @($temp, $publicTemp)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path } }
    }
}
