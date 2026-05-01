@echo off
REM SafeRoute Production DB Backup Script
REM Usage: backup_db.bat <container_name> <db_name> <user>

SET CONTAINER=%~1
SET DBNAME=%~2
SET DBUSER=%~3
SET TIMESTAMP=%DATE:~10,4%%DATE:~4,2%%DATE:~7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%
SET TIMESTAMP=%TIMESTAMP: =0%
SET FILENAME=backups/saferoute_backup_%TIMESTAMP%.sql

IF "%CONTAINER%"=="" SET CONTAINER=saferoute-db
IF "%DBNAME%"=="" SET DBNAME=saferoute
IF "%DBUSER%"=="" SET DBUSER=postgres

echo 💾 Starting backup for %DBNAME%...
if not exist "backups" mkdir backups

docker exec %CONTAINER% pg_dump -U %DBUSER% %DBNAME% > %FILENAME%

if %ERRORLEVEL% EQU 0 (
    echo ✅ Backup successful: %FILENAME%
) else (
    echo ❌ Backup FAILED!
)
