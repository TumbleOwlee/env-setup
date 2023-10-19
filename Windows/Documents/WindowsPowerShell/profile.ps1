function Fnc-Connect-SSH() {
  python $env:USERPROFILE\Scripts\connect.py
}

Set-Alias -Name Connect-SSH -Value Fnc-Connect-SSH

function prompt {
    $CmdSuccessful = $?
    $ExitCode = 0
    if ($CmdSuccessful) {} 
    else { $ExitCode = $LastExitCode }

    #Assign Windows Title Text
    $host.ui.RawUI.WindowTitle = "Current Folder: $pwd"

    #Configure current user, current folder and date outputs
    $CmdPromptCurrentFolder = Split-Path -Path $pwd -Leaf
    $CmdPromptUser = [Security.Principal.WindowsIdentity]::GetCurrent();

    # Test for Admin / Elevated
    $IsAdmin = (New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

    #Decorate the CMD Prompt
    Write-Host "(" -NoNewline
    if ($IsAdmin) {
        Write-host 'elevated' -ForegroundColor DarkRed -NoNewline
	  Write-host '|' -ForegroundColor White -NoNewline
    }
    Write-Host "$($CmdPromptUser.Name.split("\")[1])" -ForegroundColor Blue -NoNewline    
    Write-Host "|" -ForegroundColor White -NoNewline
    Write-Host "$(Get-Location)"  -ForegroundColor Yellow -NoNewline
    Write-Host ")" -ForegroundColor White -NoNewline
    if ($CmdSuccessful) {
        Write-Host "[$ExitCode]" -ForegroundColor Green -NoNewline
    } else {
        Write-Host "[$ExitCode]" -ForegroundColor Red -NoNewline
    }

    return "> "
}
