Write-Host "========================================"
Write-Host " Starting Sinapse Frappe v16"
Write-Host "========================================"

# Go to project
Set-Location "F:\Sinapse\sinapse-frappe-v16"

# Check Podman machine
$machine = podman machine list --format "{{.Name}} {{.Running}}"

if ($machine -notmatch "true") {
    Write-Host "Starting Podman machine..."
    podman machine start
}

Write-Host ""
Write-Host "Starting Sinapse containers..."
podman compose up -d

Write-Host ""
Write-Host "Waiting for containers..."
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "Container status:"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Host ""
Write-Host "========================================"
Write-Host " Sinapse is starting"
Write-Host "========================================"
Write-Host ""
Write-Host "Open: http://localhost:8080"
Write-Host ""