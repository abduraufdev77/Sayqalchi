$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$project = Join-Path $PWD 'windows/Sayqalchi.Windows/Sayqalchi.Windows.csproj'
[xml]$props = Get-Content 'windows/Directory.Build.props'
$version = $props.Project.PropertyGroup.Version
python scripts/audit-secrets.py
if ($LASTEXITCODE -ne 0) { throw 'Secret audit failed' }
dotnet run --project windows/Sayqalchi.Core.Tests -c Release
if ($LASTEXITCODE -ne 0) { throw 'Core checks failed' }
dotnet publish $project -c Release -r win-x64 --self-contained true -o dist/windows-x64
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }
python scripts/audit-secrets.py --bundle dist/windows-x64
if ($LASTEXITCODE -ne 0) { throw 'Bundle secret audit failed' }
# Keep dependency and font notices beside the executable, including portable builds.
@'
Sayqalchi Windows preview. Double-press Right Shift to enable or pause.
Type in an editable field, pause, then press Alt+Enter to accept the result.
The Playground is available from the tray icon. Only your default tool runs
automatically. Password fields and protected processes are excluded.
Some custom editors do not expose editable UI Automation ValuePattern;
use the Playground and copy the result in those apps. Elevated apps cannot
be controlled by this normal-user process. No administrator access is needed.
This preview is not Authenticode-signed. See the source and SHA256 checksums
on the official GitHub release. Never disable Windows security protections.
'@ | Set-Content 'dist/windows-x64/Read me.txt' -Encoding utf8
# Bundle the runtime redistribution notices beside the single-file app.
$runtimePackages = Join-Path $env:USERPROFILE '.nuget/packages'
foreach ($package in @('microsoft.netcore.app.runtime.win-x64', 'microsoft.windowsdesktop.app.runtime.win-x64')) {
    $folder = Get-ChildItem (Join-Path $runtimePackages $package) -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($folder) {
        Get-ChildItem $folder.FullName -File | Where-Object { $_.Name -match 'LICENSE|ThirdPartyNotices' } | ForEach-Object {
            Copy-Item $_.FullName (Join-Path 'dist/windows-x64/Licenses' "$package-$($_.Name)")
        }
    }
}
$compiler = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
if (-not (Test-Path $compiler)) { throw 'Install Inno Setup 6 from https://jrsoftware.org/isdl.php, then rerun this script.' }
& $compiler "/DAppVersion=$version" packaging/windows.iss
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
Compress-Archive -Path dist/windows-x64/* -DestinationPath "dist/Sayqalchi-$version-windows-x64.zip" -Force
$names = @("Sayqalchi-$version-windows-x64.exe", "Sayqalchi-$version-windows-x64.zip")
$lines = foreach ($name in $names) { $hash = (Get-FileHash (Join-Path dist $name) -Algorithm SHA256).Hash.ToLowerInvariant(); "$hash  $name" }
$lines | Set-Content 'dist/SHA256SUMS-windows.txt' -Encoding ascii
