[README.md](https://github.com/user-attachments/files/30724312/README.md)
# node7-appearance

NODE7 RedM appearance, creator, clothing, and wardrobe system using ox_lib menus.

## Required
- ox_lib
- oxmysql
- node7-core

`node7-players` remains optional compatibility support and is not a dependency.

## Commands
- `/appearance`
- `/creator` or `/charcreator`
- `/clothing`, `/clothes`, or `/tailor`
- `/wardrobe` or `/outfits`
- `/loadappearance`, `/loadskin`, or `/rc` — reload the saved skin and clothing
- `/fixvisible`
- `/openappearance [id]` — admin ACE: `node7.appearance.admin`

No node7-menu-base, NUI, RSG core, or rsg-menubase dependency.

## v1.1.0
- Added `/rc` as an exact alias of `/loadskin`.
- Consolidated duplicate command, load, outfit-save, and outfit-delete logic.
- Batched ped variation refreshes when applying body and clothing components.
- Prebuilt shop and wardrobe interaction points and reduced proximity-loop work.
- Prevented repeated failing legacy-column ALTER attempts on resource startup.
- Cleaned unused state and redundant JSON encoding.

## Barber persistence

Appearance reloads apply clothing first, then restore hair and beard. Beard is the final MetaPed component, allowing optional `node7-barbers` state to remain visible after `/rc`, `/loadskin`, masks, bandanas, and outfit reloads.


## 1.3.0 barber cache synchronization
- Corrected RedM MP shop-item apply flags.
- Added `SetBarberState` so paid hair/beard changes immediately update the live appearance cache.
