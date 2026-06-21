<#
.SYNOPSIS
    Create a local Windows user account (interactive).
.DESCRIPTION
    Prompts for a username and password, with options to set the password to
    never expire and to add the account to the Administrators group.

    Prefers the PowerShell LocalAccounts cmdlets (New-LocalUser). If those are
    unavailable -- or if you choose it -- it falls back to the classic `net`
    commands. The cmd path uses `net user <name> * /add`, which prompts for the
    password with hidden input so the plaintext is never placed on a command line.
.NOTES
    Requires Administrator.
#>

function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $false)
    $suffix = if ($Default) { '(Y/n)' } else { '(y/N)' }
    $ans = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
    return ($ans -match '^(y|yes)$')
}

Write-Host "=== Create a local user account ===" -ForegroundColor Cyan

# --- Username (validated) ---
$username = $null
do {
    $candidate = (Read-Host "New username").Trim()
    if (-not $candidate) {
        Write-Warning "Username cannot be empty."
    } elseif ($candidate.Length -gt 20) {
        Write-Warning "Username must be 20 characters or fewer."
    } elseif ($candidate -match '[\\/"\[\]:;|=,+*?<>@]') {
        Write-Warning "Username contains invalid characters."
    } else {
        $username = $candidate
    }
} while (-not $username)

# --- Already exists? ---
$exists = $false
if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
    if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) { $exists = $true }
} else {
    net user $username 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $exists = $true }
}
if ($exists) {
    Write-Warning "A user named '$username' already exists. Nothing to do."
    return
}

# --- Options ---
$neverExpires = Read-YesNo "Set password to never expire?" $true
$makeAdmin    = Read-YesNo "Add this user to the Administrators group?" $false

# --- Method (PowerShell preferred; cmd fallback) ---
$haveCmdlet = [bool](Get-Command New-LocalUser -ErrorAction SilentlyContinue)
$method = 'powershell'
if ($haveCmdlet) {
    $pick = (Read-Host "Create via [P]owerShell (default) or [C]md?").Trim()
    if ($pick -match '^(c|cmd)$') { $method = 'cmd' }
} else {
    Write-Warning "New-LocalUser cmdlet is not available; using cmd (net) instead."
    $method = 'cmd'
}

try {
    if ($method -eq 'powershell') {
        $pw = Read-Host "Password for $username" -AsSecureString
        $params = @{
            Name                = $username
            Password            = $pw
            AccountNeverExpires = $true
        }
        if ($neverExpires) { $params['PasswordNeverExpires'] = $true }

        New-LocalUser @params -ErrorAction Stop | Out-Null
        # New-LocalUser doesn't add the account to any group; put it in Users.
        try { Add-LocalGroupMember -Group 'Users' -Member $username -ErrorAction Stop } catch { }
        if ($makeAdmin) {
            try { Add-LocalGroupMember -Group 'Administrators' -Member $username -ErrorAction Stop }
            catch { Write-Warning "Could not add '$username' to Administrators: $_" }
        }
        Write-Host "User '$username' created via PowerShell." -ForegroundColor Green
    }
    else {
        # cmd / net path. The * makes net prompt for the password with hidden
        # input, so the plaintext is never placed on the command line.
        Write-Host "You'll be prompted to type the password (input is hidden)." -ForegroundColor DarkGray
        net user $username * /add /expires:never
        if ($LASTEXITCODE -ne 0) { throw "net user failed (exit code $LASTEXITCODE)." }
        # `net user /add` already adds the account to the Users group.
        if ($makeAdmin) {
            net localgroup administrators $username /add | Out-Null
        }
        if ($neverExpires) {
            # `net` has no password-never-expires switch; set it via CIM/WMI
            # (the modern replacement for the deprecated `wmic`).
            try {
                $acct = Get-CimInstance Win32_UserAccount `
                    -Filter "Name='$username' AND LocalAccount=True" -ErrorAction Stop
                Set-CimInstance -InputObject $acct -Property @{ PasswordExpires = $false } -ErrorAction Stop
            } catch {
                Write-Warning "Created the user, but could not set password-never-expires: $_"
            }
        }
        Write-Host "User '$username' created via net." -ForegroundColor Green
    }
} catch {
    Write-Warning "Failed to create user '$username': $_"
}
