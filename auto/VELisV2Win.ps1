$ServiceName = "Velociraptor"
$CurrentDir  = $PSScriptRoot
if (-not $CurrentDir) { $CurrentDir = (Get-Location).Path }

$VeloExe    = Join-Path $CurrentDir "velociraptor.exe"
$VeloConfig = Join-Path $CurrentDir "client.config.yaml"

# 1. Проверка конфига
if (-not (Test-Path $VeloConfig)) {
    Write-Host "[!] Ошибка: client.config.yaml не найден в $CurrentDir" -ForegroundColor Red
    exit 1
}

# 2. Проверка наличия exe (скачиваем только если нет)
if (-not (Test-Path $VeloExe)) {
    Write-Host "[*] Скачивание velociraptor.exe..."
    $Url = (Invoke-RestMethod "https://api.github.com/repos/Velocidex/velociraptor/releases/latest").assets |
           Where-Object { $_.name -like "*windows-amd64.exe" } | Select-Object -First 1 -ExpandProperty browser_download_url
    Invoke-WebRequest -Uri $Url -OutFile $VeloExe -UseBasicParsing
    Write-Host "[+] Скачано: $VeloExe" -ForegroundColor Green
}

# 3. Проверка службы (Идемпотентность)
$Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if (-not $Service) {
    Write-Host "[*] Служба не найдена. Установка из текущей папки..." -ForegroundColor Yellow
    
    # Устанавливаем службу, но сразу говорим, что исполняемый файл лежит тут
    # (Velociraptor по умолчанию скопирует его в Program Files, если не указать service run)
    & $VeloExe --config $VeloConfig service install
    
    # Ждем регистрации
    Start-Sleep -Seconds 3
    $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    if ($Service) {
        # Меняем путь на наш, если Velociraptor скопировал его в Program Files
        $ExpectedPath = "`"$VeloExe`" --config `"$VeloConfig`" service run"
        $CurrentPath = (Get-CimInstance Win32_Service -Filter "Name='$ServiceName'").PathName
        
        if ($CurrentPath -notlike "*$CurrentDir*") {
            Write-Host "[*] Исправление пути к службе..."
            sc.exe config $ServiceName binPath= $ExpectedPath | Out-Null
        }
        Write-Host "[+] Служба установлена." -ForegroundColor Green
    } else {
        Write-Host "[!] Ошибка установки службы." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[*] Служба уже установлена." -ForegroundColor Cyan
}

# 4. Запуск службы (если не запущена)
if ($Service.Status -ne 'Running') {
    Write-Host "[*] Запуск службы..." -ForegroundColor Yellow
    Start-Service -Name $ServiceName
    Write-Host "[+] Служба запущена." -ForegroundColor Green
} else {
    Write-Host "[+] Служба уже работает." -ForegroundColor Green
}