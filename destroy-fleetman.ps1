# destroy-fleetman.ps1
# Script interactif pour detruire le cluster Kind et nettoyer l'environnement

param(
    [switch]$SkipConfirm
)

$ClusterName = "fleetman"
$ErrorActionPreference = "Stop"
$scriptStart = Get-Date

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

# --- Check Docker ---
Write-Info "Checking Docker daemon..."
try {
    docker version | Out-Null
    Write-Ok "Docker is running."
}
catch {
    Write-Err "Docker is not running. Start Docker Desktop."
    exit 1
}

Write-Host ""
Write-Host "========== FLEETMAN DESTROY TOOL ==========" -ForegroundColor Red
Write-Host ""
Write-Host "Choose cleanup level:" -ForegroundColor Yellow
Write-Host "  [1] Fast cleanup  (delete Kind cluster only)"
Write-Host "  [2] Advanced cleanup (cluster + docker networks + volumes + kubectl context)"
Write-Host ""

if (-not $SkipConfirm) {
    $choice = Read-Host "Select 1 or 2"
} else {
    $choice = "1"
}

if ($choice -eq "1") {
    Write-Warn "Fast cleanup selected."
    Write-Info "Deleting Kind cluster '$ClusterName'..."
    kind delete cluster --name $ClusterName
    Write-Ok "Cluster deleted."

} elseif ($choice -eq "2") {

    Write-Warn "Advanced cleanup selected."
    Write-Info "Deleting Kind cluster '$ClusterName'..."
    kind delete cluster --name $ClusterName
    Write-Ok "Cluster deleted."

    Write-Info "Removing kubectl context..."
    try {
        kubectl config delete-context "kind-$ClusterName" 2>$null
        kubectl config delete-cluster "kind-$ClusterName" 2>$null
    } catch {}
    Write-Ok "kubectl context cleaned."

    Write-Info "Cleaning Docker networks created by Kind..."
    docker network prune -f | Out-Null
    Write-Ok "Docker networks cleaned."

    Write-Info "Cleaning Docker volumes (Fleetman MongoDB PVC)..."
    $fleetmanVolumes = docker volume ls -q --filter name=fleetman
    if ($fleetmanVolumes) {
        docker volume rm $fleetmanVolumes 2>$null
        Write-Ok "Fleetman-related Docker volumes removed."
    } else {
        Write-Warn "No Fleetman-related Docker volumes found."
    }

    Write-Info "Cleaning orphan Docker images..."
    docker image prune -f | Out-Null
    Write-Ok "Unused Docker images cleaned."

} else {
    Write-Err "Invalid selection. Aborting."
    exit 1
}

# Timer
$scriptEnd = Get-Date
$duration = New-TimeSpan -Start $scriptStart -End $scriptEnd

Write-Host ""
Write-Ok ("Cleanup finished in {0} seconds." -f [int]$duration.TotalSeconds)
Write-Host ""
Write-Warn "Your environment is clean and ready for a fresh deploy."
Write-Host ""
