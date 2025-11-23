# fleetman-menu.ps1
# Menu principal Fleetman: deploy / destroy / status / dashboard

$ErrorActionPreference = "Stop"
$ClusterName = "fleetman"
$Namespace   = "fleetman"

function Write-Info($msg) {
    Write-Host "[INFO]  $msg" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "[ OK ]  $msg" -ForegroundColor Green
}

function Write-Err($msg) {
    Write-Host "[ERR]  $msg" -ForegroundColor Red
}

function Write-Warn($msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Check-Binary($name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    return -not [string]::IsNullOrEmpty($cmd)
}

function Show-Header {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor DarkCyan
    Write-Host "        FLEETMAN K8S CONTROL CENTER       " -ForegroundColor DarkCyan
    Write-Host "==========================================" -ForegroundColor DarkCyan
    Write-Host ""
}

function Show-MainMenu {
    Show-Header
    Write-Host "Cluster name: $ClusterName"
    Write-Host "Namespace   : $Namespace"
    Write-Host ""
    Write-Host " [1] Deploy (normal)"
    Write-Host " [2] Deploy (force redeploy + show logs)"
    Write-Host " [3] Destroy (fast or advanced)"
    Write-Host " [4] Status (nodes + pods + repartition)"
    Write-Host " [5] Dashboard (auto refresh)"
    Write-Host ""
    Write-Host " [0] Quit"
    Write-Host ""
}

function Run-DeployNormal {
    Show-Header
    Write-Info "Launching deploy-fleetman.ps1 (normal)..."
    try {
        & ".\deploy-fleetman.ps1"
        Write-Ok "Deploy script finished."
    }
    catch {
        Write-Err "Deploy script failed."
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    Pause
}

function Run-DeployFull {
    Show-Header
    Write-Info "Launching deploy-fleetman.ps1 with -ForceRedeploy -ShowLogs..."
    try {
        & ".\deploy-fleetman.ps1" -ForceRedeploy -ShowLogs
        Write-Ok "Deploy script finished."
    }
    catch {
        Write-Err "Deploy script failed."
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    Pause
}

function Run-Destroy {
    Show-Header
    Write-Info "Launching destroy-fleetman.ps1..."
    try {
        & ".\destroy-fleetman.ps1"
        Write-Ok "Destroy script finished."
    }
    catch {
        Write-Err "Destroy script failed."
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    Pause
}

function Show-Status {
    Show-Header
    Write-Info "Cluster info:"
    try {
        kubectl cluster-info
    }
    catch {
        Write-Err "Cannot reach cluster with kubectl."
    }

    Write-Host ""
    Write-Info "Nodes:"
    try {
        kubectl get nodes -o wide
    }
    catch {
        Write-Err "Cannot list nodes."
    }

    Write-Host ""
    Write-Info "Pods in namespace '$Namespace':"
    try {
        kubectl get pods -n $Namespace
    }
    catch {
        Write-Warn "Cannot list pods (namespace may not exist)."
    }

    Write-Host ""
    Write-Info "Pod distribution (NAME -> NODE):"
    try {
        kubectl get pods -n $Namespace -o=custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
    }
    catch {
        Write-Warn "Cannot show pod distribution."
    }

    Write-Host ""
    Pause
}

function Show-Dashboard {
    $refreshSeconds = 3
    $quit = $false

    while (-not $quit) {
        Clear-Host
        Write-Host "============ FLEETMAN DASHBOARD ==========" -ForegroundColor DarkCyan
        Write-Host "Press Q to quit dashboard." -ForegroundColor Yellow
        Write-Host ""
        $now = Get-Date
        Write-Host ("Time: {0}" -f $now.ToString("HH:mm:ss"))
        Write-Host ""

        Write-Info "Nodes:"
        try {
            kubectl get nodes -o wide
        }
        catch {
            Write-Err "Cannot list nodes."
        }

        Write-Host ""
        Write-Info "Pods (namespace '$Namespace'):"
        try {
            kubectl get pods -n $Namespace
        }
        catch {
            Write-Warn "Cannot list pods."
        }

        Write-Host ""
        Write-Info "Pod distribution (NAME -> NODE):"
        try {
            kubectl get pods -n $Namespace -o=custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
        }
        catch {
            Write-Warn "Cannot show pod distribution."
        }

        Write-Host ""
        Write-Info "Services (namespace '$Namespace'):"
        try {
            kubectl get svc -n $Namespace
        }
        catch {
            Write-Warn "Cannot list services."
        }

        Write-Host ""
        Write-Host ("Auto refresh in {0} seconds... (press Q to quit)" -f $refreshSeconds) -ForegroundColor Yellow

        # Auto refresh with non-blocking key check
        for ($i = 0; $i -lt $refreshSeconds; $i++) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq "Q") {
                    $quit = $true
                    break
                }
            }
            Start-Sleep -Seconds 1
        }
    }
}

# --- Start ---

if (-not (Check-Binary "kubectl")) {
    Write-Err "kubectl is not installed or not in PATH."
    exit 1
}

if (-not (Check-Binary "kind")) {
    Write-Warn "Kind is not installed or not in PATH. Deploy will fail."
}

if (-not (Check-Binary "docker")) {
    Write-Warn "Docker is not installed or not in PATH. Deploy will fail."
}

while ($true) {
    Show-MainMenu
    $choice = Read-Host "Your choice"

    switch ($choice) {
        "1" { Run-DeployNormal }
        "2" { Run-DeployFull }
        "3" { Run-Destroy }
        "4" { Show-Status }
        "5" { Show-Dashboard }
        "0" { 
            Write-Info "Exiting Fleetman menu..."
            break 
        }
        Default {
            Write-Warn "Invalid choice. Please select 0, 1, 2, 3, 4 or 5."
            Start-Sleep -Seconds 1
        }
    }
}
