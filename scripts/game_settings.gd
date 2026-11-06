class_name GameSettings
extends RefCounted

# Chosen on the main menu and read by the game scene.
static var ai_enabled: bool = false
static var ai_difficulty: AIController.Difficulty = AIController.Difficulty.NORMAL
static var ai_player_id: int = 1
# Saved deck name per seat; an empty string means that seat's starter deck.
static var deck_names: Array[String] = ["", ""]
# Army per seat (see ArmyCatalog).
static var armies: Array[String] = [ArmyCatalog.IRONCREST_ID, ArmyCatalog.ASHEN_ID]
# Terrain placements each player makes before the match; 0 skips the setup phase.
static var setup_tiles: int = 0
