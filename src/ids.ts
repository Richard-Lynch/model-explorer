// SPDX-License-Identifier: GPL-3.0-or-later
// Which model ids the app will handle at all.
//
// WHY. The staging panel turns ids into a YAML block that a human pastes into configuration a
// templating engine later renders. The ids come from upstream (the gateway's /v1/models and a
// public catalogue), so an id is UNTRUSTED text. An id carrying a newline could add a key to the
// pasted block, a `#` could hide the rest of a line, and `{{ ... }}` or `{% ... %}` would be
// evaluated by whatever renders the configuration. A real model id needs none of those.
//
// So an id must match a strict shape: path segments of letters, digits and `. _ : ~ -`,
// separated by single slashes (a leading `~` is real: some catalogue aliases start with it).
// Anything else is QUARANTINED: left out of every list, counted, and named in the UI, never
// silently dropped and never rendered into the staged block.

import type { Snapshot } from "./schemas";

export const MODEL_ID_RE = /^[A-Za-z0-9~][A-Za-z0-9._:~-]*(\/[A-Za-z0-9._:~-]+)*$/;

// Belt and braces: the pattern above already excludes every one of these, but they are the
// characters the rule exists for, so they are refused by name as well. A later widening of the
// pattern cannot let them back in without this check failing too.
const FORBIDDEN = ["{{", "{%", "{#", "#"];
// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u001f\u007f\u0085\u2028\u2029]/;

export function isSafeModelId(id: string): boolean {
  if (typeof id !== "string" || id.length === 0 || id.length > 200) return false;
  if (CONTROL.test(id)) return false;
  if (FORBIDDEN.some((f) => id.includes(f))) return false;
  return MODEL_ID_RE.test(id);
}

/** Throws when an id is not safe; the message quotes it as JSON, so it shows exactly. */
export function assertSafeModelId(id: string): void {
  if (!isSafeModelId(id)) {
    throw new Error(`refusing an unsafe model id: ${JSON.stringify(id)}`);
  }
}

/**
 * The snapshot with every unsafe id removed from all three lists, plus the removed ids
 * (de-duplicated, in first-seen order) for the UI to report.
 */
export function quarantineUnsafeIds(s: Snapshot): { snapshot: Snapshot; quarantined: string[] } {
  const bad: string[] = [];
  const keep = (id: string) => {
    if (isSafeModelId(id)) return true;
    if (!bad.includes(id)) bad.push(id);
    return false;
  };
  return {
    snapshot: {
      ...s,
      enumerated: s.enumerated.filter(keep),
      declared_picker: s.declared_picker.filter(keep),
      openrouter: s.openrouter.filter((m) => keep(m.id)),
    },
    quarantined: bad,
  };
}
