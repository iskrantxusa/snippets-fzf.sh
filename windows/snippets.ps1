[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Command = '',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]] $CommandArguments
)

$script:SnippetsFile = if ($env:SNIPPETS_FILE) {
    $env:SNIPPETS_FILE
} else {
    Join-Path $HOME '_snippets.txt'
}

$localData = [Environment]::GetFolderPath('LocalApplicationData')
$script:InstallDir = if ($env:SNIPPETS_INSTALL_DIR) {
    $env:SNIPPETS_INSTALL_DIR
} else {
    Join-Path $localData 'snippets-fzf'
}
$script:InstallFile = Join-Path $script:InstallDir 'snippets.ps1'
$script:InstallAhkFile = Join-Path $script:InstallDir 'snippets.ahk'
$script:BinDir = if ($env:SNIPPETS_BIN_DIR) {
    $env:SNIPPETS_BIN_DIR
} else {
    Join-Path $HOME '.local\bin'
}
$script:BinFile = Join-Path $script:BinDir 'snippets.ps1'

function Initialize-SnippetsFile {
    if (-not (Test-Path -LiteralPath $script:SnippetsFile)) {
        New-Item -ItemType File -Path $script:SnippetsFile -Force | Out-Null
    }
}

function Get-SnippetLines {
    Initialize-SnippetsFile
    Get-Content -LiteralPath $script:SnippetsFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -notmatch '^\s*$' -and $_ -notmatch '^\s*#' }
}

function Get-SnippetsHistoryLines {
    if (-not (Get-Module -ListAvailable -Name PSReadLine)) {
        return
    }

    Import-Module PSReadLine -ErrorAction SilentlyContinue
    if (-not (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue)) {
        return
    }

    $historyPath = (Get-PSReadLineOption).HistorySavePath
    if (Test-Path -LiteralPath $historyPath) {
        Get-Content -LiteralPath $historyPath -ErrorAction SilentlyContinue
    }
}

function Select-UniqueLines {
    param([string[]] $Lines)

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($line in $Lines) {
        if (-not [string]::IsNullOrWhiteSpace($line) -and $seen.Add($line)) {
            $line
        }
    }
}

function Invoke-SnippetsFzf {
    param(
        [string[]] $Lines,
        [string] $Query = ''
    )

    $fzf = Get-Command fzf.exe -ErrorAction SilentlyContinue
    if (-not $fzf) {
        $fzf = Get-Command fzf -ErrorAction SilentlyContinue
    }
    if (-not $fzf) {
        Write-Error 'snippets: fzf is not installed or is not in PATH.'
        return
    }

    $arguments = @('--tac', '--tiebreak=index', '--no-multi', '--bind=ctrl-r:toggle-sort')
    if ($Query) {
        $arguments += "--query=$Query"
    }

    $Lines | & $fzf.Source @arguments
}

function Get-SnippetsCandidates {
    Select-UniqueLines @((Get-SnippetsHistoryLines) + (Get-SnippetLines))
}

function Add-Snippet {
    param([Parameter(Mandatory = $true)][string] $Text)

    Initialize-SnippetsFile
    if (Get-Content -LiteralPath $script:SnippetsFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -ceq $Text } |
        Select-Object -First 1) {
        Write-Host "snippets: already saved: $Text"
        return
    }

    Add-Content -LiteralPath $script:SnippetsFile -Value $Text
    Write-Host '[OK]' -ForegroundColor Green -NoNewline
    Write-Host " snippets: saved: $Text"
}

function Set-SnippetsBindings {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    if (-not (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
        Write-Warning 'snippets: PSReadLine is not available; no key bindings installed.'
        return
    }

    Set-PSReadLineKeyHandler -Key 'Ctrl+r' -BriefDescription SnippetsSearch -ScriptBlock {
        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor)
        $selected = Invoke-SnippetsFzf -Lines (Get-SnippetsCandidates) -Query $line
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, [string] $selected)
        }
    }

    Set-PSReadLineKeyHandler -Key 'Alt+s' -BriefDescription SnippetsSave -ScriptBlock {
        $selected = Invoke-SnippetsFzf -Lines (Select-UniqueLines @(Get-SnippetsHistoryLines))
        if ($selected) {
            Add-Snippet -Text ([string] $selected)
        }
    }
}

function Register-SnippetsCompleters {
    if (-not (Get-Command Register-ArgumentCompleter -ErrorAction SilentlyContinue)) {
        return
    }

    $getCandidates = {
        param($wordToComplete, $commandAst)
        $words = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text.Trim('"', "'") })
        $firstArg = if ($words.Count -ge 2) { $words[1] } else { '' }
        if ($firstArg -eq 'sync') {
            @(Get-SnippetsSshHosts)
        } else {
            @('sync', 'help', 'install', '--help', '-h')
        }
    }

    $emitResults = {
        param($candidates, $wordToComplete)

        foreach ($candidate in $candidates) {
            if ($candidate -like "$wordToComplete*") {
                [System.Management.Automation.CompletionResult]::new(
                    $candidate,
                    $candidate,
                    [System.Management.Automation.CompletionResultType]::ParameterValue,
                    $candidate
                )
            }
        }
    }

    $completer = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $candidates = & $getCandidates $wordToComplete $commandAst
        & $emitResults $candidates $wordToComplete
    }.GetNewClosure()

    $nativeCompleter = {
        param($wordToComplete, $commandAst, $cursorPosition)
        $candidates = & $getCandidates $wordToComplete $commandAst
        & $emitResults $candidates $wordToComplete
    }.GetNewClosure()

    Register-ArgumentCompleter -CommandName snippets, snippets.ps1 -ScriptBlock $completer
    Register-ArgumentCompleter -Native -CommandName snippets, snippets.ps1 -ScriptBlock $nativeCompleter
}

function Install-Snippets {
    if (-not $PSCommandPath) {
        throw 'snippets: install must be run from windows/snippets.ps1 on disk.'
    }

    New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:BinDir -Force | Out-Null

    if ((Resolve-Path -LiteralPath $PSCommandPath).Path -ne $script:InstallFile) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $script:InstallFile -Force
    }

    $sourceAhk = Join-Path $PSScriptRoot 'snippets.ahk'
    if (Test-Path -LiteralPath $sourceAhk) {
        Copy-Item -LiteralPath $sourceAhk -Destination $script:InstallAhkFile -Force
    }

    @(
        '$installedScript = ' + "'$($script:InstallFile.Replace("'", "''"))'"
        '& $installedScript @args'
    ) | Set-Content -LiteralPath $script:BinFile -Encoding UTF8

    $profilePath = $PROFILE.CurrentUserAllHosts
    New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
    if (-not (Test-Path -LiteralPath $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $begin = '# snippets-fzf.ps1 begin'
    $end = '# snippets-fzf.ps1 end'
    $profileText = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
    if ($profileText -notmatch [regex]::Escape($begin)) {
        @(
            ''
            $begin
            ". '$($script:InstallFile.Replace("'", "''"))'"
            $end
        ) | Add-Content -LiteralPath $profilePath
    }

    Write-Host "snippets: installed script at $script:InstallFile"
    Write-Host "snippets: installed CLI at $script:BinFile"
    Write-Host "snippets: PowerShell profile updated at $profilePath"
    if (Test-Path -LiteralPath $script:InstallAhkFile) {
        Write-Host "snippets: AutoHotkey script installed at $script:InstallAhkFile"
        Write-Host 'snippets: run snippets.ahk with AutoHotkey v2 to enable global Ctrl+I.'
    }
    Write-Host "snippets: add $script:BinDir to PATH to invoke 'snippets' directly."
}

function Get-SnippetsSshHosts {
    if ($env:SNIPPETS_SYNC_SERVERS) {
        $env:SNIPPETS_SYNC_SERVERS -split '\s+' | Where-Object { $_ }
        return
    }

    $sshConfig = Join-Path $HOME '.ssh\config'
    if (-not (Test-Path -LiteralPath $sshConfig)) {
        return
    }

    $hosts = foreach ($line in (Get-Content -LiteralPath $sshConfig)) {
        if ($line -match '^\s*Host\s+(.+)$') {
            foreach ($hostName in ($Matches[1] -split '\s+')) {
                if ($hostName -and $hostName -notmatch '[*?!]' -and $hostName -notmatch '^#') {
                    $hostName
                }
            }
        }
    }
    $hosts | Select-Object -Unique
}

function Sync-SnippetsOne {
    param([Parameter(Mandatory = $true)][string] $Server)

    Initialize-SnippetsFile
    if ($Server -notmatch '^[A-Za-z0-9_.:@%+\[\]-]+$') {
        throw "snippets: invalid SSH server name '$Server'."
    }
    if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue) -and
        -not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        throw 'snippets: ssh is not installed or is not in PATH.'
    }

    Write-Host "snippets: merging $script:SnippetsFile with ${Server}:~/_snippets.txt"
    $remoteText = Invoke-SnippetsSsh -Server $Server -RemoteCommand 'cat "$HOME/_snippets.txt" 2>/dev/null || true' -CaptureOutput
    $localLines = Get-Content -LiteralPath $script:SnippetsFile -ErrorAction SilentlyContinue
    $remoteLines = if ($remoteText) { $remoteText -split "`r?`n" } else { @() }
    $mergedLines = Select-UniqueLines @($localLines + $remoteLines)
    Set-Content -LiteralPath $script:SnippetsFile -Value $mergedLines -Encoding UTF8
    $mergedText = if ($mergedLines.Count -gt 0) {
        ($mergedLines -join [Environment]::NewLine) + [Environment]::NewLine
    } else {
        ''
    }
    Push-SnippetsOne -Server $Server -Text $mergedText
}

function Push-SnippetsOne {
    param(
        [Parameter(Mandatory = $true)][string] $Server,
        [AllowNull()][string] $Text = $null
    )

    if ($null -eq $Text) {
        $lines = Get-Content -LiteralPath $script:SnippetsFile -ErrorAction SilentlyContinue
        $Text = if ($lines.Count -gt 0) {
            ($lines -join [Environment]::NewLine) + [Environment]::NewLine
        } else {
            ''
        }
    }

    Invoke-SnippetsSsh -Server $Server -RemoteCommand 'cat > "$HOME/_snippets.txt"' -InputText $Text | Out-Null
}

function Invoke-SnippetsSsh {
    param(
        [Parameter(Mandatory = $true)][string] $Server,
        [Parameter(Mandatory = $true)][string] $RemoteCommand,
        [string] $InputText,
        [switch] $CaptureOutput
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'ssh'
    $startInfo.Arguments = ('"{0}" "{1}"' -f $Server, ($RemoteCommand.Replace('"', '\"')))
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $null -ne $InputText
    $startInfo.RedirectStandardOutput = [bool] $CaptureOutput
    $startInfo.RedirectStandardError = [bool] $CaptureOutput

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void] $process.Start()
    if ($null -ne $InputText) {
        $process.StandardInput.Write($InputText)
        $process.StandardInput.Close()
    }
    $stdout = if ($CaptureOutput) { $process.StandardOutput.ReadToEnd() } else { $null }
    $stderr = if ($CaptureOutput) { $process.StandardError.ReadToEnd() } else { $null }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        if ($stderr) {
            Write-Error $stderr
        }
        throw "snippets: ssh failed for $Server with exit code $($process.ExitCode)."
    }
    $stdout
}

function Sync-Snippets {
    param([string] $Server)

    if ($Server) {
        Sync-SnippetsOne -Server $Server
        return
    }

    $servers = @(Get-SnippetsSshHosts)
    if ($servers.Count -eq 0) {
        throw 'snippets: no SSH hosts found; set SNIPPETS_SYNC_SERVERS or run snippets sync <server>.'
    }

    $answer = Read-Host 'Are you sure you want to sync your snippets to all SSH hosts available from ~/.ssh/config? [y/N]'
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host 'snippets: sync cancelled.'
        return
    }

    foreach ($item in $servers) {
        Sync-SnippetsOne -Server $item
    }
    $mergedLines = Get-Content -LiteralPath $script:SnippetsFile -ErrorAction SilentlyContinue
    $mergedText = if ($mergedLines.Count -gt 0) {
        ($mergedLines -join [Environment]::NewLine) + [Environment]::NewLine
    } else {
        ''
    }
    foreach ($item in $servers) {
        Push-SnippetsOne -Server $item -Text $mergedText
    }
    Write-Host 'snippets: sync finished.'
}

function Pick-Snippet {
    param([string] $OutputPath)

    $selected = Invoke-SnippetsFzf -Lines (Get-SnippetsCandidates)
    if (-not $selected) {
        return
    }

    if ($OutputPath) {
        Set-Content -LiteralPath $OutputPath -Value ([string] $selected) -Encoding UTF8
    } else {
        [string] $selected
    }
}

function Show-SnippetsHelp {
    @'
snippets.ps1 - plain-text command snippets for PowerShell

Usage:
  .\windows\snippets.ps1 install
  snippets pick [output-file]
  snippets sync [server]
  snippets help

PowerShell bindings after install/profile reload:
  Ctrl+R   search PowerShell history + snippets with fzf
  Alt+S    save a selected PowerShell history command
  TAB      complete snippets CLI commands and sync hosts

Global Windows hotkey:
  Run the installed snippets.ahk with AutoHotkey v2; Ctrl+I opens fzf and
  pastes the selected command into the previously focused window.

Files:
  SNIPPETS_FILE defaults to $HOME\_snippets.txt
  SNIPPETS_AUTO_COMPLETE=0 disables snippets CLI completion
  Installed code is stored in %LOCALAPPDATA%\snippets-fzf
  CLI wrapper is stored in $HOME\.local\bin\snippets.ps1
'@ | Write-Output
}

if ($MyInvocation.InvocationName -eq '.') {
    Set-SnippetsBindings
    if ($env:SNIPPETS_AUTO_COMPLETE -notin @('0', 'false', 'FALSE', 'no', 'NO')) {
        Register-SnippetsCompleters
    }
    return
}

switch ($Command.ToLowerInvariant()) {
    'install' { Install-Snippets }
    'pick' {
        $outputPath = if ($CommandArguments) { $CommandArguments[0] } else { $null }
        Pick-Snippet -OutputPath $outputPath
    }
    'sync' {
        $server = if ($CommandArguments) { $CommandArguments[0] } else { $null }
        Sync-Snippets -Server $server
    }
    { $_ -in @('', 'help', '--help', '-h') } { Show-SnippetsHelp }
    default {
        Show-SnippetsHelp
        throw "snippets: unknown command '$Command'."
    }
}
