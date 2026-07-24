[README.md](https://github.com/user-attachments/files/30333640/README.md)
# node7-appearance

NODE7 RedM appearance, creator, clothing, and wardrobe system converted from rsg-appearance data for ox_lib menus.

## Required
- ox_lib
- oxmysql
- node7-core
- node7-players

## Commands
- /appearance
- /creator
- /clothing
- /wardrobe
- /outfits
- /loadappearance
- /fixvisible
- /openappearance [id] - admin ACE: node7.appearance.admin

No node7-menu-base. No NUI. No RSG core. No rsg-menubase.


## v1.0.1
- Fixed active character lookup for RSG-format node7-core.
- Removed hard node7-players dependency; node7-players is now optional compatibility only.
- Added server state-bag citizenid bridge on Node7Core player load.
