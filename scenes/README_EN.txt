Bot-mode fix

1) Replace scenes/world.gd and scenes/bot_ai.gd with the corresponding files from the archive.
2) In bot_match the teams are fixed: the local player is CT, the bot is T.
3) The local player is now assigned a team directly on spawn/respawn. Previously offline mode skipped the network ready-handshake, so team stayed -1 and player.gd hid arms_node.
4) Fixed the bot's visibility check: if the ray hits the target CharacterBody3D's capsule first, it now counts as visible. Previously the bot often thought the player was behind a wall and didn't shoot.
5) Added slight lead on moving targets, slightly faster reaction and better base accuracy.
