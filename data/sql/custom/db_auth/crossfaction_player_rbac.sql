-- Cross-faction player permissions (ADR-023). Role 195 ("Sec Level Player") gets the two-side
-- interaction permissions so normal players can mail, trade, add friends, use the who list and
-- deliver nearby text emotes across factions; say/yell deliver cross-faction unconditionally,
-- whisper needs the chat config plus RBAC. The rest of the layer is config-gated (see the ADR).
-- Re-applicable: DELETE + INSERT; only touches the project-granted links for role 195.
DELETE FROM `rbac_linked_permissions` WHERE `id` = 195 AND `linkedId` IN (25, 26, 27, 28, 29, 51);

INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
(195, 25), -- two-side interaction: chat (nearby say/emote delivery)
(195, 26), -- two-side interaction: channels
(195, 27), -- two-side interaction: mail
(195, 28), -- two-side who list
(195, 29), -- two-side add friend
(195, 51); -- two-side trade
