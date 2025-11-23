param(
    [switch]$ForceRedeploy,
    [switch]$ShowLogs
)

# deploy-fleetman.ps1
# Script d'auto-deploiement du projet Fleetman sur Kubernetes (Kind)

$ErrorActionPreference = "Stop"
$scriptStart = Get-Date

# --- CONFIG ---
$ClusterName = "fleetman"
$Namespace   = "fleetman"
$KindConfig  = "kind-config.yaml"
$K8sFolder   = "k8s"

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

function Test-Binary($name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    return -not [string]::IsNullOrEmpty($cmd)
}

function Wait-ForNodesReady {
    Write-Info "Waiting for cluster nodes to be READY..."

    $maxSeconds = 120
    $elapsed = 0

    while ($elapsed -lt $maxSeconds) {
        $notReady = (kubectl get nodes --no-headers 2>$null | Select-String -NotMatch " Ready ")

        if (-not $notReady) {
            Write-Ok "All nodes are READY. (after $elapsed seconds)"
            return
        }

        Start-Sleep -Seconds 3
        $elapsed += 3

        if ($elapsed % 15 -eq 0) {
            Write-Warn "Nodes are still not ready after $elapsed seconds..."
        }
    }

    Write-Err "Timeout: some nodes are still not READY after $maxSeconds seconds."
}

function Wait-ForPodsReady {
    param([string]$Namespace)

    Write-Info "Waiting for pods in namespace '$Namespace' to be RUNNING..."

    $maxSeconds = 240
    $elapsed = 0

    while ($elapsed -lt $maxSeconds) {
        $pods = kubectl get pods -n $Namespace --no-headers 2>$null

        if (-not $pods) {
            Start-Sleep -Seconds 3
            $elapsed += 3
            continue
        }

        $notRunning = $pods | Where-Object {
            ($_ -notmatch " Running ") -and ($_ -notmatch " Completed ")
        }

        if (-not $notRunning) {
            Write-Ok "All pods in '$Namespace' are RUNNING. (after $elapsed seconds)"
            return
        }

        Start-Sleep -Seconds 3
        $elapsed += 3

        if ($elapsed % 15 -eq 0) {
            Write-Warn "Pods are still not all RUNNING after $elapsed seconds..."
            kubectl get pods -n $Namespace
        }
    }

    Write-Err "Timeout: some pods are still not RUNNING after $maxSeconds seconds."
}

function Show-DebugLogs {
    param([string]$Namespace)

    Write-Warn "Debug mode enabled, showing last logs of main deployments..."

    $deployments = @(
        "fleetman-queue",
        "fleetman-position-simulator",
        "fleetman-position-tracker",
        "fleetman-api-gateway",
        "fleetman-web-app"
    )

    foreach ($dep in $deployments) {
        Write-Info "===== Logs for deployment '$dep' (tail -n 20) ====="
        try {
            kubectl logs deploy/$dep -n $Namespace --tail=20
        }
        catch {
            Write-Warn "Cannot get logs for deployment '$dep'. It may not exist."
        }
    }
}

# --- 0) Verifications prealables ---
Write-Info "Checking prerequisites..."

if (-not (Test-Binary "docker")) {
    Write-Err "Docker is not installed or not in PATH."
    exit 1
}

if (-not (Test-Binary "kind")) {
    Write-Err "Kind is not installed."
    exit 1
}

if (-not (Test-Binary "kubectl")) {
    Write-Err "kubectl is not installed."
    exit 1
}

# Test Docker daemon
Write-Info "Checking Docker daemon..."
try {
    docker version | Out-Null
    Write-Ok "Docker is up and running."
}
catch {
    Write-Err "Docker is not responding. Start Docker Desktop and rerun this script."
    exit 1
}

# Afficher options
if ($ForceRedeploy) {
    Write-Warn "Option -ForceRedeploy enabled: existing cluster will be deleted if found."
}
if ($ShowLogs) {
    Write-Warn "Option -ShowLogs enabled: debug logs will be displayed after deployment."
}

# Se placer dans le dossier du script
Set-Location $PSScriptRoot
Write-Info ("Current directory : {0}" -f (Get-Location))

if (-not (Test-Path $KindConfig)) {
    Write-Err "File kind-config.yaml not found at project root."
    exit 1
}

if (-not (Test-Path $K8sFolder)) {
    Write-Err "Folder 'k8s' not found."
    exit 1
}

# --- 1) Creation / gestion du cluster ---
Write-Info "Checking Kind clusters..."

$existingClusters = ""
try {
    $existingClusters = kind get clusters 2>$null
}
catch {
    $existingClusters = ""
}

$clusterList = @()
if ($existingClusters) {
    $clusterList = $existingClusters -split "\r?\n"
}

if ($clusterList -contains $ClusterName) {
    if ($ForceRedeploy) {
        Write-Warn ("Cluster '{0}' already exists and will be deleted due to -ForceRedeploy." -f $ClusterName)
        kind delete cluster --name $ClusterName
        Write-Ok ("Cluster '{0}' deleted." -f $ClusterName)

        Write-Info ("Creating cluster '{0}'..." -f $ClusterName)
        kind create cluster --name $ClusterName --config $KindConfig
        Write-Ok "Cluster created."
    } else {
        Write-Ok ("Cluster '{0}' found, reusing it." -f $ClusterName)
    }
} else {
    Write-Info ("Creating cluster '{0}'..." -f $ClusterName)
    kind create cluster --name $ClusterName --config $KindConfig
    Write-Ok "Cluster created."
}

# --- 2) Attendre que les noeuds soient READY ---
Wait-ForNodesReady

Write-Info "Cluster nodes status:"
kubectl get nodes -o wide

# --- 3) Appliquer les manifests ---
Write-Info "Deploying Kubernetes manifests..."

# 3.1 Namespace d'abord (si present)
$nsFile = Join-Path $K8sFolder "namespace.yaml"
if (Test-Path $nsFile) {
    Write-Info ("Applying namespace manifest ({0})..." -f $nsFile)
    kubectl apply -f $nsFile
} else {
    Write-Err "namespace.yaml not found in k8s folder."
}

# 3.2 Puis tous les autres fichiers YAML du dossier, tries par nom
Write-Info ("Applying each manifest in folder '{0}'..." -f $K8sFolder)

$files = Get-ChildItem $K8sFolder -Filter *.yaml | Sort-Object Name

foreach ($file in $files) {
    if ($file.Name -eq "namespace.yaml") {
        continue
    }
    Write-Info ("kubectl apply -f {0}" -f $file.FullName)
    kubectl apply -f $file.FullName
}

Write-Ok "All manifests applied."

# --- 4) Attendre que les pods soient RUNNING ---
Wait-ForPodsReady -Namespace $Namespace

# --- 5) Etat final des pods et repartition ---
Write-Info ("Final pod state in namespace '{0}':" -f $Namespace)
kubectl get pods -n $Namespace

Write-Info "Pod distribution across nodes:"
kubectl get pods -n $Namespace -o=custom-columns=NAME:.metadata.name,NODE:.spec.nodeName

# --- 6) Mode debug: logs des deployments ---
if ($ShowLogs) {
    Show-DebugLogs -Namespace $Namespace
}

# --- 7) Ouvrir la Web App ---
$webUrl = "http://localhost:30080"
Write-Info ("Opening Web App : {0}" -f $webUrl)

try {
    Start-Process $webUrl
    Write-Ok "Browser started."
}
catch {
    Write-Err ("Cannot open browser automatically. Open manually: {0}" -f $webUrl)
}

# --- 8) Timer global ---
$scriptEnd = Get-Date
$duration = New-TimeSpan -Start $scriptStart -End $scriptEnd
Write-Ok ("Deployment finished in {0} seconds." -f [int]$duration.TotalSeconds)

Write-Host ""
Write-Warn "Tip:"
Write-Warn "  If vehicles do not appear on the map:"
Write-Warn "    kubectl rollout restart deploy/fleetman-queue -n fleetman"
