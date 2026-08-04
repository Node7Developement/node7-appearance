# Versions

## 1.1.0
- Added `/rc` with the same saved-appearance reload path as `/loadskin`.
- Consolidated duplicate client and server handlers.
- Optimized component application, interaction checks, persistence helpers, and legacy table setup.

## 1.0.1
- Fixed active character lookup for RSG-format node7-core.
- Removed the hard node7-players dependency; node7-players is optional compatibility only.
- Added the server state-bag citizenid bridge on Node7Core player load.

## 1.0.0
- Converted from rsg-appearance source data.
- Replaced menubase with ox_lib context, input, and text UI.
- Added NODE7 citizenid persistence.
