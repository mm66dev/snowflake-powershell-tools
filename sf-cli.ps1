[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Action,
    [Parameter()][Alias("c")][string]$SFID,
    [Parameter()][Alias("w")][string]$Warehouse,
    [Parameter()][Alias("r")][string]$Role,
    [Parameter()][Alias("d")][string]$Database,
    [Parameter()][Alias("s")][string]$Schema,
    [Parameter()][Alias("v")][switch]$VerboseMode,
    [Parameter(ValueFromRemainingArguments)][string[]]$ExtraArgs
)
$script_name = $MyInvocation.MyCommand.Name -replace "\.ps1", ""
#Reject unknown switches in ExtraArgs
$invalidSwitch = $ExtraArgs | Where-Object { $_ -match '^-'} | Select-Object -First 1
if ($invalidSwitch) {
    Write-Host "Invalid switch: $invalidSwitch" -ForegroundColor Red
    Write-Host "`nUsage: "
    Write-Host "`t$script_name \help"    
    exit 1
}
if ($VerboseMode) { 
    Write-Host "Action: $Action,$SFID,$Warehouse,$Role,$Database,$Schema,$VerboseMode,$ExtraArgs" -ForegroundColor Cyan
}
function LoadPSDFile([string]$PSDFile) {
    return Import-PowerShellDataFile $PSDFile
}
# Display $env_dict one by one for debugging
function Show-Dict([hashtable]$dict, [bool]$show_first_line=$false) {
    foreach ($key in $dict.Keys) {
        if ($show_first_line) {
            # Split the value and take index 0
            $displayValue = ($dict[$key] -split '(\r?\n)')[0]
        } else {
            $displayValue = $dict[$key]
        }
         Write-Host " $key : $displayValue" -ForegroundColor Yellow
    }
}


$conn_file_name = "${PSScriptRoot}\${script_name}-conn.pds1"
$meta_file_name = "${PSScriptRoot}\${script_name}-meta.pds1"
if ($VerboseMode) { 
    Write-Host "conn_file_name: $conn_file_name" -ForegroundColor Cyan
    Write-Host "meta_file_name: $meta_file_name" -ForegroundColor Cyan
    Write-Host "Reading them into dictionaries" -ForegroundColor Cyan
}
$conn_dict = if (Test-Path $conn_file_name) { LoadPSDFile -PSDFile $conn_file_name } else { @{} }
$meta_dict = if (Test-Path $meta_file_name) { LoadPSDFile -PSDFile $meta_file_name } else { @{} }

function Show-Help {    
    Write-Host "Usage: "
    Write-Host "`t$script_name \help"    
    Write-Host "`t$script_name \connections"
    Write-Host "`t$script_name \connect <SFID>"
    Write-Host "`t$script_name \set-vars [-c <SFID>] [-w <warehouse>] [-d <database>] [-s <schema>] [-r <role>]"
    Write-Host "`t$script_name \get-vars"
    Write-Host "`t$script_name <SQL Command in quotes>"
    Write-Host "`t$script_name meta-commands:"
    Write-Host "`t$script_name `t\help meta"
    Write-Host "`t$script_name `t\<meta-command>"
    Write-Host "`t$script_name Compare schema:"
    Write-Host "`t$script_name \compare <source-db.schema> <target-db.schema>"
}

function Show-MetaCommandsHelp {
    Write-Host "Meta-commands: "
    $filter = if ($ExtraArgs) { $ExtraArgs -join '|' } else { '.' }
    foreach ($key in $Actions.Keys | Where-Object { $_ -match $filter }) {
        Write-Host " $key : $($Actions[$key])"
    }
}
function Get-vars {
    Write-Host "`nCurrent environment vars:" -ForegroundColor Cyan
    Write-Host " SFID        -a  $env:SFID"
    Write-Host " Warehouse   -w  $env:Warehouse"
    Write-Host " Database    -d  $env:Database"
    Write-Host " Schema      -s  $env:Schema"
    Write-Host " Role        -r  $env:Role"
}

function Set-vars {
    Write-Host "coming here..."
    if ($SFID) { $env:SFID = $SFID}
    if ($Warehouse) { $env:Warehouse = $Warehouse.ToUpper()}
    if ($Database) { $env:Database = $Database.ToUpper() }
    if ($Schema) { $env:Schema = $Schema.ToUpper() }
    if ($Role) { $env:Role = $Role.ToUpper() }
    Get-vars
}

# Load from env if not provided
if (-not $SFID) { $SFID = $env:SFID }
if (-not $Warehouse) { $Warehouse = $env:Warehouse }
if (-not $Database) { $Database = $env:Database } else { $Database = $Database.ToUpper() }
if (-not $Schema) { $Schema = $env:Schema } else { $Schema = $Schema.ToUpper() }
if (-not $Role) { $Role = $env:Role } else { $Role = $Role.ToUpper() }

function New-SFConnection {
    $connString = $conn_dict[$SFID] #"Driver={SnowflakeDSIIDriver};Server=$($ACID).snowflakecomputing.com;UID=$env:UserName;Authenticator=externalbrowser;tracing=0;ChangedSession-OriginalPool;MinPoolSize=1;MaxPoolSize=2"
    if ($Warehouse) { $connString += ";Warehouse=$Warehouse" }
    if ($Database) { $connString += ";Database=$Database" }
    if ($Schema) { $connString += ";Schema=$Schema" }
    if ($Role) { $connString += ";Role=$Role" }
    #Write-Host "Connection String: $connString"
    $conn = New-Object System.Data.Odbc.OdbcConnection
    $conn.ConnectionString = $connString
    $conn.Open()
    return $conn
}

function Compare-Schema([string]$source_db_schema, [string]$target_db_schema) {
    Write-Host "Comparing schema between $source_db_schema and $target_db_schema" -ForegroundColor Green
    $sdb,$sschema = $source_db_schema.ToUpper().Split(".")
    $tdb,$tschema = $target_db_schema.ToUpper().Split(".")
    #Tables/Columns comparison
    $query = "SELECT 
        '$source_db_schema' as source,s.table_name, s.column_name, s.data_type, 
        '$target_db_schema' as target,t.table_name, t.column_name, t.data_type
        FROM $sdb.information_schema.columns s FULL OUTER JOIN $tdb.information_schema.columns t
        ON s.table_name = t.table_name AND s.column_name = t.column_name
        WHERE s.table_schema='$sschema' AND t.table_schema='$tschema' 
        AND s.table_name != t.table_name OR s.column_name != t.column_name 
        AND s.data_type != t.data_type OR s.data_type IS NULL OR t.data_type IS NULL"
    Write-Host "Comparing tables/columns between $source_db_schema and $target_db_schema" -ForegroundColor Green
    exec_sql $query
    $query = "SELECT * FROM $sdb.information_schema.tables s where table_schema='$sschema' and (table_name,table_schema) 
    not in (select table_name,table_schema from $tdb.information_schema.tables where table_schema='$tschema')"
    Write-Host "Comparing tables that are exist in $source_db_schema but not in $target_db_schema" -ForegroundColor Green
    exec_sql $query
    $query = "SELECT * FROM $tdb.information_schema.columns s where table_schema='$tschema' and (table_name,column_name) 
    not in (select table_name,column_name from $sdb.information_schema.columns where table_schema='$sschema')"
    Write-Host "Comparing columns that are exist in $target_db_schema but not in $source_db_schema" -ForegroundColor Green
    exec_sql $query
    #Views comparison
    $query = "select * from $sdb.information_schema.views s where table_schema='$sschema' and 
    (table_name,table_schema) not in 
    (select table_name,table_schema from $tdb.information_schema.views where table_schema='$tschema')"
    Write-Host "Comparing views that are exist in $source_db_schema but not in $target_db_schema" -ForegroundColor Green
    exec_sql $query
    $query = "select * from $tdb.information_schema.views s where table_schema='$tschema' and 
    (table_name,table_schema) not in    
    (select table_name,table_schema from $sdb.information_schema.views where table_schema='$sschema')"
    Write-Host "Comparing views that are exist in $target_db_schema but not in $source_db_schema" -ForegroundColor Green
    exec_sql $query
    #Sequences comparison
    $query = "select * from $sdb.information_schema.sequences s where sequence_schema='$sschema' and 
    (sequence_name,sequence_schema) not in 
    (select sequence_name,sequence_schema from $tdb.information_schema.sequences where sequence_schema='$tschema')"
    Write-Host "Comparing sequences that are exist in $source_db_schema but not in $target_db_schema" -ForegroundColor Green    
    exec_sql $query
    $query = "select * from $tdb.information_schema.sequences s where sequence_schema='$tschema' and 
    (sequence_name,sequence_schema) not in 
    (select sequence_name,sequence_schema from $sdb.information_schema.sequences where sequence_schema='$sschema')"
    Write-Host "Comparing sequences that are exist in $target_db_schema but not in $source_db_schema" -ForegroundColor Green 
    exec_sql $query
    #Functions comparison
    $query = "select * from $sdb.information_schema.functions s where function_schema='$sschema' and 
    (function_name,function_schema) not in  
    (select function_name,function_schema from $tdb.information_schema.functions where function_schema='$tschema')"
    Write-Host "Comparing functions that are exist in $source_db_schema but not in $target_db_schema" -ForegroundColor Green
    exec_sql $query
    $query = "select * from $tdb.information_schema.functions s where function_schema='$tschema' and 
    (function_name,function_schema) not in  
    (select function_name,function_schema from $sdb.information_schema.functions where function_schema='$sschema')"
    Write-Host "Comparing functions that are exist in $target_db_schema but not in $source_db_schema" -ForegroundColor Green
    exec_sql $query 
    #Procedures comparison
    $query = "select * from $sdb.information_schema.procedures s where procedure_schema='$sschema' and 
    (procedure_name,procedure_schema) not in    
    (select procedure_name,procedure_schema from $tdb.information_schema.procedures where procedure_schema='$tschema')"
    Write-Host "Comparing procedures that are exist in $source_db_schema but not in $target_db_schema" -ForegroundColor Green
    exec_sql $query
    $query = "select * from $tdb.information_schema.procedures s where procedure_schema='$tschema' and 
    (procedure_name,procedure_schema) not in    
    (select procedure_name,procedure_schema from $sdb.information_schema.procedures where procedure_schema='$sschema')"
    Write-Host "Comparing procedures that are exist in $target_db_schema but not in $source_db_schema" -ForegroundColor Green
    exec_sql $query
}
function exec_sql([string]$Sql) {
    $conn = New-SFConnection $env:SFID
    $cmd = New-Object System.Data.Odbc.OdbcCommand($Sql, $conn)
    $adapter = New-Object System.Data.Odbc.OdbcDataAdapter($cmd)
    $dt = New-Object System.Data.DataTable
    Write-Host "Executing: $Sql"
    $adapter.Fill($dt) | Out-Null
    #$dt |Format-Table -AutoSize | Out-String -Width 1024
    $dt | Format-Table -AutoSize | Out-Host | Out-String -Width 1024
    Write-Host "Row count: $($dt.Rows.Count)`n"
    $cmd.Dispose()
    $conn.Close()
    $conn.Dispose()
    $dt.Dispose()
}
function Command_Control([string]$cmd,[bool]$interactive_mode=$false) {
    $cmds = $cmd.Split(" ")
    Write-Host "Processing command: $cmds" -ForegroundColor Green
    if ( -not $cmds[0].StartsWith("\")) {
        exec_sql $cmd
    } elseif ($cmds[0].StartsWith("\set-vars")) {
        if ($interactive_mode) { 
            write-host "$cmds is not allowed in interactive mode" -ForegroundColor Yellow;  
        } else {
            Set-vars
        }
    } elseif ($cmds[0].StartsWith("\get-vars")) {
        Get-vars
    } elseif ($cmds[0].StartsWith("\q")) {
        return $false
    } elseif ($cmds[0].StartsWith("\conn")) {
        if ($cmds[1] ) {
              $env:SFID=$cmds[1]
              Write-Host "Testing connection to $env:SFID" -ForegroundColor Green
              exec_sql "SELECT CURRENT_VERSION()"
        } else {
            Show-Dict $conn_dict
        }
    } elseif ($cmds[0].StartsWith("\comp")) {        
        Write-Host "Compare $cmds" -ForegroundColor Green
        Compare-Schema -source_db_schema $cmds[1] -target_db_schema $cmds[2]
    } elseif ($cmds[0].StartsWith("\help")) {
        if ($cmds[1] -and $cmds[1].StartsWith("meta")) {
           Show-Dict $meta_dict $true
        } elseif ($cmds[0].StartsWith("\")) {
           Show-Help
        }
    } elseif ($meta_dict.ContainsKey($cmds[0].Substring(1))) {
        exec_sql $meta_dict[$cmds[0].Substring(1)]
    } else {
        Write-Host "Unknown meta-command: $cmd" -ForegroundColor Red 
    }
   return $true
}
function Input-Sql([string]$Prompt) {
    Write-Host "$Prompt" -ForegroundColor Cyan -NoNewline
    $sql=""
    while($true) { 
        $line = Read-Host 
        $sql += $line + "`n"
        if ($line.StartsWith('\')) { break }
        if ($line.Contains(';')) { break }        
    }

    return $sql
}
# If no Action provided, enter interactive mode
if ($Action.Trim().Length -eq 0) {
    while ($true) {
        $cmd = Input-Sql "Input SQL (type \q to exit): "
        if ($cmd.Trim().Length -eq 0) { continue }
        $cc_flag = Command_Control $cmd.Trim() $true
        if ($cc_flag -eq $false) { break }
    }
# if Acttion provided, execute it accordingly
} elseif ($Action.StartsWith("\") ) {
    Command_Control "$Action $ExtraArgs" | Out-Null
} else {  
    exec_sql "$Action $ExtraArgs"
}
