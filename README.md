---

# Weapon Dynamic Slot Positioner for Sven Co-op

![AngelScript](https://img.shields.io/badge/Language-AngelScript-blue.svg)
![Game](https://img.shields.io/badge/Game-Sven%20Co--op-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

An AngelScript plugin for Sven Co-op servers that dynamically on runtime game session manages weapon HUD slots to prevent overlap and ensure all weapons are selectable by ignoring `iPosition` completely, especially on maps with a large number of custom weapons.
(Yes, it include vanilla weapon, custom weapon with AS, or AMX or whatever they came from. It's all weapon active on the game.)

**!UPDATE NOTE!**: Since unfortunately scanning thru registered custom weapon from plugin cannot be done by scanning the map, please try to pickup all the custom weapon plugin once, and the plugin will store them permanently on persistent storage in file. You only need to do this once in lifetime! 

![hud_behavior_1](https://github.com/user-attachments/assets/63871232-0543-4f24-9392-acbe54be7ee6)

---

## Table of Contents
* [The Problem](#the-problem)
* [The Solution](#the-solution)
* [Key Features](#key-features)
* [Installation](#installation)
* [Usage for Players](#usage-for-players)
* [How It Works (Technical Details)](#how-it-works-technical-details)
* [Code Structure](#code-structure)
* [Contributing](#contributing)
* [License](#license)

---

## The Problem

The default Sven Co-op weapon HUD has a fundamental limitation: each weapon "bucket" (slot 1, slot 2, etc.) has a fixed number of positions to display weapon icons. When a map features more weapons in a single bucket with conflicted positions, the icons begin to overlap and sometimes hidden.

This causes two major issues:
1.  **Visual Clutter:** The HUD becomes messy and unreadable.
2.  **Inaccessibility:** Players cannot select the "hidden" or overlapped weapons using the scroll wheel or number keys, making those weapons completely unusable.

This is a common frustration on custom maps that are rich with unique weapons.

## The Solution

This plugin provides a server-side workaround for this engine limitation. It intercepts weapon pickups and drops, and dynamically re-assigns the HUD position for each weapon in a player's inventory.

When a player picks up a new weapon, the plugin finds the first available, non-overlapping position in the correct HUD bucket and tells the client to display the weapon there. When a weapon is dropped, its position is freed up for future use.

It also introduces a "Graveyard Slot" — a hidden, off-screen position. All weapons that are not in the player's inventory are sent to this slot, ensuring that the player's HUD is completely clean of any unowned weapon icons.

## Key Features

-   **Dynamic HUD Slot Management:** Automatically arranges weapon icons in the HUD to prevent overlap.
-   **Sort Inventory Based on First-Pickup:** Moving position of the weapon around to player's preferences.
-   **Full Weapon Selectability:** Ensures every weapon a player carries can be selected.
-   **HUD Mod Compatibility:** Allows players to choose their HUD mode (`!togglehudslot`) to support both the standard game HUD and popular client-side HUD modifications like **ABCEnchance (MetaHook)**.
-   **Automatic Weapon Discovery:** Scans the map for all weapon entities and maintains a master list to keep player HUDs clean.
-   **Persistent Player Settings & Weapon List:** Remembers each player's chosen HUD mode & discovered weapon list across sessions and map changes.
-   **Lightweight & Server-Side:** No client-side downloads or modifications are required for players using the vanilla HUD.

## Installation

1.  **Place the File on Your Server:**
    Place the files into folder named `WeaponDynamicSlotPos` as the following directory on your game server:
    `.../svencoop/scripts/plugins/`

2.  **Activate the Plugin:**
    Open the `default_plugins.txt` file located in `.../svencoop`. Add the following entry to the `"plugins"` list:

    ```json
    "plugin"
	{
		"name"          "WeaponDynamicSlotPos"
		"script"        "WeaponDynamicSlotPos/WeaponDynamicSlotPos"
	}
    ```

3.  **Restart the Server:**
    Restart your server or change maps for the plugin to become active. You should see `[WDSP] Running!` in the server console on startup.

## Usage for Players

Players can control the plugin's behavior to match their client-side setup using a chat command.

**Command:** `!togglehudslot` or `/togglehudslot`

Typing this command will open a menu allowing the player to choose their HUD mode.

-   **Option 1: Vanilla HUD [HL/SC]**
    -   This is the default mode and should be used by most players.
    -   It enables the dynamic slotting logic, fixing the weapon overlap issue.

-   **Option 2: ABCEnchance [MetaHook]**
    -   This mode is for players using the ABCEnchance client-side plugin, which comes with its own advanced HUD that already solves the slotting problem.
    -   Selecting this option will **disable** the dynamic slotting logic for that player to prevent conflicts with their client-side mod.

The player's choice is saved and will be remembered the next time they join the server.

## How It Works (Technical Details)

-   **PlayerLoadout Class:** At the core of the plugin is the `PlayerLoadout` class, which manages the inventory state for each player individually. It tracks which weapons a player has and which HUD slots are currently occupied.

-   **Network Messages:** The plugin works by sending custom `WeaponList` network messages to the client. This message tells the client which weapon to display, in which bucket (`iSlot`), and at which position within that bucket (`iPos`).

-   **The "Graveyard Slot":** The plugin defines `GRAVEYARD_POS_INDEX = 0`. Position `0` in any weapon bucket is not rendered by the client. On map start and when a player connects, the plugin sends a `WeaponList` message for every known weapon on the server, assigning them all to this graveyard position. This effectively "cleans the slate" for the player's HUD.

-   **Dynamic Allocation:** When a player picks up a weapon (detected via the `WDSP_CanCollect` hook), the plugin:
    1.  Gets the weapon's default slot (e.g., shotgun is slot 3).
    2.  Finds the first free position in that slot (e.g., position 1, 2, 3...).
    3.  Sends a `WeaponList` message to the client to place the weapon's icon at that specific slot and position.
    4.  Marks that position as "occupied" in its internal state.

-   **Dropping/Losing Weapons:** When a player drops a weapon, the plugin sends another `WeaponList` message, re-assigning the weapon to the graveyard position (hiding it) and marking its previous HUD position as "free".

## Code Structure

The source code is organized into three logical parts:

-   `Misc.as`: Contains utility functions for discovering all registered weapon entities on the server. It includes a large, hardcoded list as a fallback and dynamically scans the map for any `weapon_*` entities to build a comprehensive master list.
-   `PlayerLoadout.as`: Defines the main `PlayerLoadout` class responsible for all state management, slot allocation, and network message construction for a single player. It also handles the settings menu and file I/O for player preferences.
-   `WeaponDynamicSlotPos.as`: The main plugin entry point. It contains the `PluginInit` function, registers all the necessary game event hooks (e.g., `ClientPutInServer`, `CanCollect`), and links game events to the logic in the `PlayerLoadout` class.

## Contributing

Feel free to fork this repository, make improvements, and submit a pull request. Suggestions for new features or bug fixes are welcome via the issue tracker.

## License


This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.








