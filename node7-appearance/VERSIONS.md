## 1.4.0

- Added one automatic saved `/loadskin`-equivalent refresh after `Node7Core:Client:OnPlayerLoaded`.
- Waits until the selected character and saved appearance are ready before applying.
- Guards against duplicate refreshes during the same character session.
- Resets the one-time guard only on `Node7Core:Client:OnPlayerUnload`.
- Supports one refresh when `node7-appearance` restarts while a character is already loaded.

## 1.2.1

- Corrected RedM `ApplyShopItemToPed` calls to use the build-safe final flag `false`, preventing masks and clothing compatibility passes from suppressing saved beard components.

## 1.2.0

- Fixed `/rc`, `/loadskin`, and `/loadappearance` removing saved barber beards.
- Clothing now rebuilds first; hair is restored afterward and beard is always the final MetaPed component.
- No full MetaPed variation refresh runs after the beard is applied.
- Removed unsafe live body-component inspection from the normal appearance-completion event so barber restoration always receives the event.
- Kept the tattoo body-texture bridge export available for explicit tattoo integrations.

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
