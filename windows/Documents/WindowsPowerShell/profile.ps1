function Fnc-Connect-SSH() {
  python $env:USERPROFILE\Scripts\connect.py
}

Set-Alias -Name Connect-SSH -Value Fnc-Connect-SSH
