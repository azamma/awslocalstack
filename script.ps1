# Script LocalStack con Menu Interactivo
# Este script inicia LocalStack y ofrece un menu para gestionar colas SQS

$ContainerName = "localstack-test"
$Global:CreatedQueues = @()  # Array para almacenar colas creadas

Write-Host "=== LocalStack con Menu Interactivo ===" -ForegroundColor Cyan

# 1. Limpiar containers existentes
Write-Host "1. Limpiando containers existentes..." -ForegroundColor Yellow
docker stop $ContainerName 2>$null | Out-Null
docker rm $ContainerName 2>$null | Out-Null
docker stop localstack-container 2>$null | Out-Null
docker rm localstack-container 2>$null | Out-Null

# 2. Verificar Docker
Write-Host "2. Verificando Docker..." -ForegroundColor Yellow
try {
    $dockerVersion = docker --version
    Write-Host "Docker: $dockerVersion" -ForegroundColor Green
}
catch {
    Write-Host "Error con Docker: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 3. Verificar puertos
Write-Host "3. Verificando puerto 4566..." -ForegroundColor Yellow
$portCheck = netstat -an | Select-String "4566"
if ($portCheck) {
    Write-Host "Puerto 4566 en uso:" -ForegroundColor Yellow
    $portCheck | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
}
else {
    Write-Host "Puerto 4566 disponible" -ForegroundColor Green
}

# 4. Descargar imagen
Write-Host "4. Descargando imagen LocalStack..." -ForegroundColor Yellow
docker pull localstack/localstack:latest

# 5. Iniciar LocalStack con logs en background
Write-Host "5. Iniciando LocalStack..." -ForegroundColor Yellow
$job = Start-Job -Name "LocalStackJob" -ScriptBlock {
    param($name)
    docker run --rm --name $name -p 4566:4566 -e SERVICES=sqs -e DEBUG=1 localstack/localstack:latest
} -ArgumentList $ContainerName

# Esperar un poco para que inicie
Start-Sleep -Seconds 10

# 6. Verificar estado
Write-Host "6. Verificando estado..." -ForegroundColor Yellow
$containerInfo = docker ps --filter "name=$ContainerName" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
if ($containerInfo -match $ContainerName) {
    Write-Host "Container corriendo:" -ForegroundColor Green
    Write-Host $containerInfo -ForegroundColor White
}
else {
    Write-Host "Container no encontrado" -ForegroundColor Red
    Write-Host "Containers actuales:" -ForegroundColor Yellow
    docker ps -a
    Write-Host "Logs del container:" -ForegroundColor Yellow
    docker logs $ContainerName 2>$null
    exit 1
}

# 7. Probar conectividad
Write-Host "7. Probando conectividad..." -ForegroundColor Yellow
$maxAttempts = 20
for ($i = 1; $i -le $maxAttempts; $i++) {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -TimeoutSec 3 -ErrorAction Stop
        Write-Host "LocalStack respondio en intento $i" -ForegroundColor Green
        Write-Host "Estado de servicios:" -ForegroundColor Cyan
        $response.services | ConvertTo-Json -Depth 2
        break
    }
    catch {
        Write-Host "Intento $i/$maxAttempts - Error: $($_.Exception.Message)" -ForegroundColor Yellow
        if ($i -eq $maxAttempts) {
            Write-Host "LocalStack no respondio despues de $maxAttempts intentos" -ForegroundColor Red
            Write-Host "Logs actuales:" -ForegroundColor Yellow
            docker logs $ContainerName --tail 10
            Stop-Job $job -Force
            exit 1
        }
        Start-Sleep -Seconds 3
    }
}

# 8. Verificar awslocal
Write-Host "8. Verificando awslocal..." -ForegroundColor Yellow
try {
    $awsVersion = awslocal --version 2>$null
    Write-Host "awslocal disponible" -ForegroundColor Green
}
catch {
    Write-Host "awslocal no encontrado - instalando..." -ForegroundColor Yellow
    pip install awscli-local
    Write-Host "awslocal instalado" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== LocalStack iniciado y listo para usar ===" -ForegroundColor Green
Write-Host ""

# Funcion para mostrar menu
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "========= MENU LOCALSTACK ==========" -ForegroundColor Cyan
    Write-Host "============= by Zamma =============" -ForegroundColor Cyan
    Write-Host "1. Crear una cola" -ForegroundColor White
    Write-Host "2. Enviar un mensaje a una cola" -ForegroundColor White
    Write-Host "3. Listar colas existentes" -ForegroundColor White
    Write-Host "4. Salir" -ForegroundColor White
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host ""
}

# Funcion para crear cola
function New-SQSQueue {
    Write-Host ""
    Write-Host "=== CREAR COLA ===" -ForegroundColor Yellow
    
    $queueName = Read-Host "Ingresa el nombre de la cola"
    
    if ([string]::IsNullOrWhiteSpace($queueName)) {
        Write-Host "Nombre de cola no puede estar vacio" -ForegroundColor Red
        return
    }
    
    $isFifo = Read-Host "Es una cola FIFO? (s/n) [n]"
    
    if ($isFifo -eq "s" -or $isFifo -eq "S") {
        if (-not $queueName.EndsWith(".fifo")) {
            $queueName += ".fifo"
        }
        
        try {
            $result = awslocal sqs create-queue --queue-name $queueName --attributes FifoQueue=true | ConvertFrom-Json
            $queueUrl = $result.QueueUrl
            $Global:CreatedQueues += @{Name = $queueName; Url = $queueUrl; Type = "FIFO"}
            Write-Host "Cola FIFO creada exitosamente:" -ForegroundColor Green
            Write-Host "  Nombre: $queueName" -ForegroundColor White
            Write-Host "  URL: $queueUrl" -ForegroundColor White
        }
        catch {
            Write-Host "Error creando cola FIFO: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        try {
            $result = awslocal sqs create-queue --queue-name $queueName | ConvertFrom-Json
            $queueUrl = $result.QueueUrl
            $Global:CreatedQueues += @{Name = $queueName; Url = $queueUrl; Type = "Standard"}
            Write-Host "Cola Standard creada exitosamente:" -ForegroundColor Green
            Write-Host "  Nombre: $queueName" -ForegroundColor White
            Write-Host "  URL: $queueUrl" -ForegroundColor White
        }
        catch {
            Write-Host "Error creando cola Standard: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Funcion para enviar mensaje
function Send-SQSMessage {
    Write-Host ""
    Write-Host "=== ENVIAR MENSAJE ===" -ForegroundColor Yellow
    
    if ($Global:CreatedQueues.Count -eq 0) {
        Write-Host "No hay colas disponibles. Crea una cola primero." -ForegroundColor Red
        return
    }
    
    # Mostrar colas disponibles
    Write-Host "Colas disponibles:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Global:CreatedQueues.Count; $i++) {
        $queue = $Global:CreatedQueues[$i]
        Write-Host "  $($i + 1). $($queue.Name) ($($queue.Type))" -ForegroundColor White
    }
    
    $selection = Read-Host "Selecciona el numero de cola (1-$($Global:CreatedQueues.Count))"
    
    try {
        $queueIndex = [int]$selection - 1
        if ($queueIndex -lt 0 -or $queueIndex -ge $Global:CreatedQueues.Count) {
            Write-Host "Seleccion invalida" -ForegroundColor Red
            return
        }
        
        $selectedQueue = $Global:CreatedQueues[$queueIndex]
        Write-Host "Ingresa el mensaje JSON:" -ForegroundColor Yellow
        $message = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($message)) {
            Write-Host "El mensaje no puede estar vacio" -ForegroundColor Red
            return
        }
        
        # Validar que el mensaje sea un JSON válido
        try {
            $null = $message | ConvertFrom-Json -ErrorAction Stop
            Write-Host "Mensaje JSON valido" -ForegroundColor Green
        }
        catch {
            Write-Host "El mensaje no es un JSON valido: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
        
        # Escapar el mensaje JSON para asegurar que se envíe como cadena literal
        $escapedMessage = $message -replace '"', '\"'
        $quotedMessage = "`"$escapedMessage`""
        
        # Definir los atributos del mensaje en una variable
        $messageAttributes = '{"ContentType":{"DataType":"String","StringValue":"application/json"}}'
        $escapedMessageAttributes = $messageAttributes -replace '"', '\"'
        $quotedMessageAttributes = "`"$escapedMessageAttributes`""
        
        if ($selectedQueue.Type -eq "FIFO") {
            $groupId = Read-Host "Ingresa el Message Group ID [default-group]"
            if ([string]::IsNullOrWhiteSpace($groupId)) { $groupId = "default-group" }
            
            $dedupId = "msg-$(Get-Date -Format 'yyyyMMddHHmmss')-$((Get-Random -Maximum 9999))"
            
            # Enviar el mensaje JSON con comillas adicionales y atributo ContentType
            awslocal sqs send-message --queue-url $selectedQueue.Url --message-body $quotedMessage --message-group-id $groupId --message-deduplication-id $dedupId --message-attributes $quotedMessageAttributes | Out-Null
            
            # Agregar un pequeno retraso para asegurar que el mensaje este disponible
            Start-Sleep -Seconds 2
            
            # Verificar el mensaje enviado
            Write-Host "Verificando mensaje enviado..." -ForegroundColor Yellow
            $receivedMessage = awslocal sqs receive-message --queue-url $selectedQueue.Url --max-number-of-messages 1 --wait-time-seconds 5 --attribute-names All --message-attribute-names All | ConvertFrom-Json
            if ($receivedMessage.Messages) {
                $body = $receivedMessage.Messages[0].Body
                Write-Host "Mensaje recibido de la cola: $body" -ForegroundColor White
                try {
                    $null = $body | ConvertFrom-Json -ErrorAction Stop
                    Write-Host "El mensaje en la cola es un JSON valido" -ForegroundColor Green
                }
                catch {
                    Write-Host "El mensaje en la cola NO es un JSON valido: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            else {
                Write-Host "No se recibio ningun mensaje de la cola despues de esperar" -ForegroundColor Red
                Write-Host "Intenta leer el mensaje manualmente con este comando:" -ForegroundColor Yellow
                Write-Host "awslocal sqs receive-message --queue-url $selectedQueue.Url --max-number-of-messages 1 --wait-time-seconds 10" -ForegroundColor White
            }
            
            Write-Host "Mensaje enviado exitosamente a cola FIFO:" -ForegroundColor Green
            Write-Host "  Cola: $($selectedQueue.Name)" -ForegroundColor White
            Write-Host "  Grupo: $groupId" -ForegroundColor White
            Write-Host "  ID Dedup: $dedupId" -ForegroundColor White
            Write-Host "  Mensaje: $message" -ForegroundColor White
        }
        else {
            # Enviar el mensaje JSON con comillas adicionales y atributo ContentType
            awslocal sqs send-message --queue-url $selectedQueue.Url --message-body $quotedMessage --message-attributes $quotedMessageAttributes | Out-Null
            
            # Agregar un pequeno retraso para asegurar que el mensaje este disponible
            Start-Sleep -Seconds 2
            
            # Verificar el mensaje enviado
            Write-Host "Verificando mensaje enviado..." -ForegroundColor Yellow
            $receivedMessage = awslocal sqs receive-message --queue-url $selectedQueue.Url --max-number-of-messages 1 --wait-time-seconds 5 --attribute-names All --message-attribute-names All | ConvertFrom-Json
            if ($receivedMessage.Messages) {
                $body = $receivedMessage.Messages[0].Body
                Write-Host "Mensaje recibido de la cola: $body" -ForegroundColor White
                try {
                    $null = $body | ConvertFrom-Json -ErrorAction Stop
                    Write-Host "El mensaje en la cola es un JSON valido" -ForegroundColor Green
                }
                catch {
                    Write-Host "El mensaje en la cola NO es un JSON valido: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            else {
                Write-Host "No se recibio ningun mensaje de la cola despues de esperar" -ForegroundColor Red
                Write-Host "Si aun no se consumio, intenta leer el mensaje manualmente con este comando:" -ForegroundColor Yellow
                Write-Host "awslocal sqs receive-message --queue-url $selectedQueue.Url --max-number-of-messages 1 --wait-time-seconds 10" -ForegroundColor White
            }
            
            Write-Host "Mensaje enviado exitosamente a cola Standard:" -ForegroundColor Green
            Write-Host "  Cola: $($selectedQueue.Name)" -ForegroundColor White
            Write-Host "  Mensaje: $message" -ForegroundColor White
        }
    }
    catch {
        Write-Host "Error enviando mensaje: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Funcion para listar colas
function Show-ExistingQueues {
    Write-Host ""
    Write-Host "=== COLAS EXISTENTES ===" -ForegroundColor Yellow
    
    if ($Global:CreatedQueues.Count -eq 0) {
        Write-Host "No hay colas creadas en esta sesion" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Colas creadas en esta sesion:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Global:CreatedQueues.Count; $i++) {
        $queue = $Global:CreatedQueues[$i]
        Write-Host "  $($i + 1). $($queue.Name) - Tipo: $($queue.Type)" -ForegroundColor White
        Write-Host "     URL: $($queue.Url)" -ForegroundColor Gray
    }
    
    # Tambien mostrar todas las colas en LocalStack
    try {
        Write-Host ""
        Write-Host "Todas las colas en LocalStack:" -ForegroundColor Cyan
        $allQueues = awslocal sqs list-queues | ConvertFrom-Json
        if ($allQueues.QueueUrls) {
            $allQueues.QueueUrls | ForEach-Object {
                $queueName = ($_ -split '/')[-1]
                Write-Host "  - $queueName" -ForegroundColor White
                Write-Host "    $_" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "  No hay colas en LocalStack" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error listando colas: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Funcion de limpieza mejorada
function Cleanup-LocalStack {
    Write-Host ""
    Write-Host "=== LIMPIEZA ===" -ForegroundColor Yellow
    
    # Eliminar colas creadas
    if ($Global:CreatedQueues.Count -gt 0) {
        Write-Host "Eliminando colas creadas..." -ForegroundColor Yellow
        foreach ($queue in $Global:CreatedQueues) {
            try {
                awslocal sqs delete-queue --queue-url $queue.Url 2>$null | Out-Null
                Write-Host "  Cola eliminada: $($queue.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "  Error eliminando cola: $($queue.Name)" -ForegroundColor Red
            }
        }
    }
    
    # Detener container
    Write-Host "Deteniendo LocalStack..." -ForegroundColor Yellow
    if (Get-Job -Name "LocalStackJob" -ErrorAction SilentlyContinue) {
        Stop-Job -Name "LocalStackJob"
        Remove-Job -Name "LocalStackJob" -Force
    }
    docker stop $ContainerName 2>$null | Out-Null
    docker rm $ContainerName 2>$null | Out-Null
    Write-Host "LocalStack detenido y limpiado" -ForegroundColor Green
}

# Loop principal del menu
do {
    Show-Menu
    $choice = Read-Host "Selecciona una opcion (1-4)"
    
    switch ($choice) {
        "1" { New-SQSQueue }
        "2" { Send-SQSMessage }
        "3" { Show-ExistingQueues }
        "4" { 
            Write-Host "Saliendo..." -ForegroundColor Yellow
            Cleanup-LocalStack
            break 
        }
        default { 
            Write-Host "Opcion invalida. Por favor selecciona 1, 2, 3 o 4." -ForegroundColor Red 
        }
    }
    
    if ($choice -ne "4") {
        Write-Host ""
        Write-Host "Presiona cualquier tecla para continuar..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    
} while ($choice -ne "4")

Write-Host ""
Write-Host "LocalStack ha sido detenido. Gracias por usar el script!" -ForegroundColor Green