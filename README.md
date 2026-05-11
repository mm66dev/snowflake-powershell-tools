# snowflake-powershell-tools

A simple PowerShell CLI for connecting to Snowflake, running SQL, and comparing schema objects.

## Files

- `sf-cli.ps1` - main script for executing SQL, managing Snowflake connections, and comparing schemas.
- `sf-cli-conn.pds1` - connection definitions for Snowflake environments.
- `sf-cli-meta.pds1` - saved SQL shortcuts and meta commands.

## Requirements

- PowerShell on Windows
- Snowflake ODBC driver installed
- A valid Snowflake connection string in `sf-cli-conn.pds1`

## Usage

Run the script from PowerShell:

```powershell
.s-cli.ps1 \help
```

### Common commands

- `\help` - show help text
- `\conn <SFID>` - list or test a saved connection
- `\get-vars` - show current environment variables
- `\set-vars -c <SFID> -w <warehouse> -d <database> -s <schema> -r <role>` - set connection context
- `\comp <source-db.schema> <target-db.schema>` - compare schema objects between two Snowflake schemas
- `\q` - exit interactive mode

### Execute SQL directly

```powershell
.s-cli.ps1 "SELECT CURRENT_VERSION();"
```

### Interactive mode

Run the script without an action to enter interactive SQL mode:

```powershell
.s-cli.ps1
```

Then type SQL statements or backslash commands like `\conn`, `\get-vars`, `\comp`, and `\q`.

## Configure connections

Edit `sf-cli-conn.pds1` and add or update named entries for your Snowflake environments. Each entry should include `Driver`, `Server`, `Authenticator`, `Uid`, and any other required connection settings.

## Notes

- `sf-cli-meta.pds1` contains predefined meta commands that can be executed by name.
- The schema compare command uses Snowflake `INFORMATION_SCHEMA` views to compare tables, columns, views, sequences, functions, and procedures.
