param(
    [string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))),
    [switch]$DevelopmentOnly
)
. (Join-Path $PSScriptRoot 'support.ps1')
$workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$directory = Join-Path $workspace '.secrets'
$key = Join-Path $directory 'android-release.p12'
$credentials = Join-Path $directory 'android-signing.json'
if ((Test-Path -LiteralPath $key) -or (Test-Path -LiteralPath $credentials)) {
    if (-not (Test-Path -LiteralPath $key) -or -not (Test-Path -LiteralPath $credentials)) { throw 'Signing identity is incomplete. Restore the backup; do not regenerate it.' }
    $existing = Get-Content -LiteralPath $credentials -Raw | ConvertFrom-Json
    if ((Get-SpyHash $key) -cne $existing.keystoreSha256) { throw 'Signing identity does not match its saved fingerprint' }
    Write-Output 'The preserved Android signing identity is intact.'
    return
}
if (-not $DevelopmentOnly) { throw 'A generated key cannot cover official PiliPlus. Key generation is permitted only for explicitly requested isolated testing.' }
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$password = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$previous = $env:PILIPLUS_SPY_KEY_PASSWORD
try {
    $env:PILIPLUS_SPY_KEY_PASSWORD = $password
    Invoke-SpyNative keytool @('-genkeypair','-keystore',$key,'-storetype','PKCS12','-storepass:env','PILIPLUS_SPY_KEY_PASSWORD','-keypass:env','PILIPLUS_SPY_KEY_PASSWORD','-alias','piliplus-spy','-keyalg','RSA','-keysize','4096','-validity','10000','-dname','CN=PiliPlus-SPY','-noprompt')
    Write-SpyJson @{storeFile='android-release.p12';keyAlias='piliplus-spy';password=$password;keystoreSha256=(Get-SpyHash $key)} $credentials
    $backup = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.piliplus-spy/signing-backup'
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($file in @($key,$credentials)) {
        $copy = Join-Path $backup (Split-Path -Leaf $file)
        if (Test-Path -LiteralPath $copy) { throw 'Signing backup already exists; preserve and inspect it' }
        Copy-Item -LiteralPath $file -Destination $copy
        if ((Get-SpyHash $file) -cne (Get-SpyHash $copy)) { throw 'Signing backup verification failed' }
    }
    if ($IsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        foreach ($path in @($directory,$backup)) {
            Invoke-SpyNative icacls.exe @($path,'/inheritance:r','/grant:r',"${identity}:(OI)(CI)F")
        }
    }
    Write-Output 'Created and verified a persistent Android signing identity and a separate local backup. No secret was published.'
} finally { $env:PILIPLUS_SPY_KEY_PASSWORD = $previous; $password = $null }
