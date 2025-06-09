# Localstack con menú interactivo Powershell

Este repositorio contiene un script de PowerShell para gestionar un entorno LocalStack con un menú interactivo. Permite iniciar LocalStack, crear colas SQS (estándar o FIFO), enviar mensajes JSON, listar colas existentes y realizar limpieza. El script incluye gestión de contenedores Docker, verificación de puertos y pruebas de conectividad.

## Características
- Iniciar y limpiar contenedores LocalStack
- Crear colas SQS estándar o FIFO
- Enviar mensajes JSON a las colas
- Listar todas las colas creadas y existentes
- Limpieza automática al salir

## Uso
1. Asegúrate de tener instalados Docker y awslocal (awscli-local)
2. Ejecuta el script: `.\LocalStackMenu.ps1`
3. Sigue las indicaciones del menú interactivo

## Requisitos
- PowerShell
- Docker
- awslocal (instalable vía `pip install awscli-local` si no está presente)

## Contribuciones
Haz un fork del repositorio, realiza cambios y envía un pull request.

## Licencia
[Licencia MIT](LICENSE)
