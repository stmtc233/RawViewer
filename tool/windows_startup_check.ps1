param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath,
    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$resolvedPath = (Resolve-Path -LiteralPath $ExecutablePath).Path
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $resolvedPath
$startInfo.WorkingDirectory = Split-Path -Parent $resolvedPath
$startInfo.UseShellExecute = $false

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$appProcess = [System.Diagnostics.Process]::Start($startInfo)
try {
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $appProcess.Refresh()
        if ($appProcess.HasExited) {
            throw 'Process exited before showing a window. Close other Raw Viewer instances and retry.'
        }
        # .NET selects a visible, unowned top-level window as MainWindowHandle.
        if ($appProcess.MainWindowHandle -ne [IntPtr]::Zero) {
            $timer.Stop()
            [PSCustomObject]@{
                Executable = $resolvedPath
                ProcessId = $appProcess.Id
                WindowVisibleMs = [Math]::Round($timer.Elapsed.TotalMilliseconds, 1)
            }
            return
        }
        Start-Sleep -Milliseconds 10
    }
    throw "No visible window within $TimeoutSeconds seconds."
}
finally {
    # Leave the application open so its restored geometry can be inspected.
    $appProcess.Dispose()
}
