# mod-personal-arena-teams

Personal arena teams (RFC-003 Group D, ADR-024): rated arena premades queue without buying a
charter. When a group leader queues rated for 2v2/3v3/5v5 and has no team of that bracket, a
team named after the leader is created free and the whole group joins it (members already in
another team of that bracket stay out).

- Solo rated 3v3 is not this module's job: mod-arena-3v3-solo-queue owns solo queueing via its
  own personal-team flow.
- Hook: `OnPlayerCanJoinInArenaQueue` (fires before the queue handler's team checks), so the
  core's rated-group flow proceeds normally after creation. Premades with a real team are
  untouched; unrated skirmishes are untouched.
- Config: `PersonalArenaTeams.Enable` (default 1). No DB schema changes — teams are core rows.
