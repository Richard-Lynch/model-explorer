// SPDX-License-Identifier: GPL-3.0-or-later
// The id rule (src/ids.ts) and the staged block (src/stage.ts): unsafe ids are refused at load
// and again at render, and every emitted id is quoted.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { isSafeModelId, quarantineUnsafeIds } from "../src/ids";
import { snapshotSchema } from "../src/schemas";
import { renderDesiredState } from "../src/stage";

const TEMPLATE = "openrouter/{{ lookup('pipe','id') }}";
const NEWLINE = "openrouter/vendor/model-a\nextra_key: injected";
const COMMENT = "openrouter/vendor/model-a # trailing";
const BLOCK_TAG = "openrouter/{% raw %}x";
const CONTROL = "openrouter/vendor/model\u0000a";

const UNSAFE = [TEMPLATE, NEWLINE, COMMENT, BLOCK_TAG, CONTROL, "", "/leading", "a//b", "a/", "a b"];
const SAFE = [
  "openrouter/anthropic/claude-x",
  "openrouter/openrouter/auto",
  "openrouter/vendor/model-a:free",
  "~anthropic/claude-sonnet-latest",
  "anthropic/claude-example",
  "openrouter/x-ai/grok-4.7",
];

describe("isSafeModelId", () => {
  it.each(SAFE)("accepts %j", (id) => expect(isSafeModelId(id)).toBe(true));
  it.each(UNSAFE)("refuses %j", (id) => expect(isSafeModelId(id)).toBe(false));
});

describe("renderDesiredState", () => {
  it.each([TEMPLATE, NEWLINE, COMMENT, BLOCK_TAG, CONTROL])("refuses a staged %j", (id) => {
    expect(() => renderDesiredState(["openrouter/vendor/model-a"], [id])).toThrow(/unsafe model id/);
  });

  it("refuses an unsafe id in the declared list too", () => {
    expect(() => renderDesiredState([TEMPLATE], [])).toThrow(/unsafe model id/);
  });

  it("quotes every id and keeps a normal block", () => {
    const out = renderDesiredState(["openrouter/vendor/model-a"], ["openrouter/anthropic/claude-x"]);
    const items = out.split("\n").filter((l) => l.startsWith("  - "));
    expect(items).toEqual([
      '  - "openrouter/anthropic/claude-x"   # ADDED by the model explorer',
      '  - "openrouter/vendor/model-a"',
    ]);
    // Nothing a templating engine would evaluate reaches the block.
    expect(out).not.toMatch(/\{\{|\{%/);
  });
});

describe("quarantineUnsafeIds", () => {
  it("withholds unsafe ids from every list and names them", () => {
    const fixture = JSON.parse(readFileSync("tests/fixtures/catalogue.json", "utf8"));
    fixture.enumerated.push(NEWLINE);
    fixture.declared_picker.push(TEMPLATE);
    fixture.openrouter.push({ id: COMMENT });
    const { snapshot, quarantined } = quarantineUnsafeIds(snapshotSchema.parse(fixture));
    expect(quarantined).toEqual([NEWLINE, TEMPLATE, COMMENT]);
    expect(snapshot.enumerated).not.toContain(NEWLINE);
    expect(snapshot.declared_picker).not.toContain(TEMPLATE);
    expect(snapshot.openrouter.map((m) => m.id)).not.toContain(COMMENT);
    // The safe rows are untouched, and the result renders.
    expect(snapshot.openrouter.map((m) => m.id)).toEqual(["vendor/model-a", "vendor/model-b"]);
    expect(() => renderDesiredState(snapshot.declared_picker, [])).not.toThrow();
  });

  it("withholds nothing from the clean fixture", () => {
    const fixture = JSON.parse(readFileSync("tests/fixtures/catalogue.json", "utf8"));
    expect(quarantineUnsafeIds(snapshotSchema.parse(fixture)).quarantined).toEqual([]);
  });
});
