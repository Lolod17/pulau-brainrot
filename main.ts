// PULAU BRAINROT's hand-in (Node 22, standard library only). The game is this directory's Rojo project, built
// into game.rbxl with `rojo build default.project.json --output game.rbxl`. This program first verifies the
// hand-in and fails loudly on a broken entry (a scorer would refuse it at submit), then copies game.rbxl,
// src/, screenshots/ and PLAY.json from beside this file to /output and writes /output/dossier.json, the
// summary the judge reads, with the vendored make.fun library.
//
// The check refuses, printing one line and exiting 1, when: PLAY.json does not parse or lacks the required
// fields; place_id or universe_id is not a positive whole number (they stay 0 until the place is published);
// url is not exactly https://www.roblox.com/games/<place_id>; screenshots holds fewer than 3 or more than 4
// files, or a file is not named .jpg/.jpeg/.png, or any file is 262144 bytes or more; or game.rbxl is missing
// or 33554432 bytes or more.
//
// Every name under /output starts with a letter, a digit or _ and holds only letters, digits, . _ and -: the
// grader fails an entry whose output holds any other, so a file such as .gitkeep or .DS_Store copied in fails it.
// So src/ and screenshots/ are copied without any name that starts with a dot, at any depth.
//
// Outside the grader's container, MAKEFUN_OUTPUT_DIR stands in for /output:
//   mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

import { copyFileSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

const here = fileURLToPath(new URL('.', import.meta.url));
const out = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

/** The screenshots/ rules: 3 or 4 images, each .jpg/.jpeg/.png and each under 262144 bytes. */
const MIN_SHOTS = 3;
const MAX_SHOTS = 4;
const MAX_SHOT_BYTES = 262144;

/** The game.rbxl rule: the built place must be under 33554432 bytes (32 MiB). */
const MAX_PLACE_BYTES = 33554432;

/** A broken hand-in: the message is the one line printed before exiting 1. */
class HandInError extends Error {}

const isPositiveWhole = (value: unknown): value is number =>
  typeof value === 'number' && Number.isInteger(value) && value > 0;

/** Reads PLAY.json and returns its place_id and universe_id, refusing anything the kit would refuse. */
function checkPlay(): { placeId: number; universeId: number } {
  const playPath = join(here, 'PLAY.json');
  if (!existsSync(playPath)) throw new HandInError('PLAY.json is missing from the repository root');

  let play: unknown;
  try {
    play = JSON.parse(readFileSync(playPath, 'utf8'));
  } catch {
    throw new HandInError('PLAY.json is not valid JSON');
  }
  if (typeof play !== 'object' || play === null || Array.isArray(play)) {
    throw new HandInError('PLAY.json must be a JSON object');
  }

  const { url, place_id, universe_id } = play as Record<string, unknown>;
  if (!isPositiveWhole(place_id)) throw new HandInError('PLAY.json place_id is not a positive whole number');
  if (!isPositiveWhole(universe_id)) throw new HandInError('PLAY.json universe_id is not a positive whole number');
  const expected = `https://www.roblox.com/games/${place_id}`;
  if (url !== expected) throw new HandInError(`PLAY.json url must be ${expected}, got ${JSON.stringify(url)}`);

  return { placeId: place_id, universeId: universe_id };
}

/** Checks screenshots/ holds 3 or 4 images, each .jpg/.jpeg/.png and each under 262144 bytes. */
function checkScreenshots(): number {
  const shotsDir = join(here, 'screenshots');
  if (!existsSync(shotsDir)) throw new HandInError('screenshots/ is missing from the repository root');

  const names = readdirSync(shotsDir, { withFileTypes: true })
    .filter((entry) => !entry.name.startsWith('.'))
    .map((entry) => entry.name);

  for (const name of names) {
    if (!/\.(jpg|jpeg|png)$/i.test(name)) {
      throw new HandInError(`screenshots/${name} is not a .jpg, .jpeg or .png file`);
    }
  }
  if (names.length < MIN_SHOTS || names.length > MAX_SHOTS) {
    throw new HandInError(`screenshots/ holds ${names.length} files, but the kit wants 3 or 4`);
  }
  for (const name of names) {
    const bytes = statSync(join(shotsDir, name)).size;
    if (bytes >= MAX_SHOT_BYTES) {
      throw new HandInError(`screenshots/${name} is ${bytes} bytes, but must be under ${MAX_SHOT_BYTES}`);
    }
  }
  return names.length;
}

/** Runs every hand-in check; the first failure throws a HandInError naming the problem. */
function checkHandIn(): void {
  const placePath = join(here, 'game.rbxl');
  if (!existsSync(placePath)) throw new HandInError('game.rbxl is missing; run rojo build first');
  const placeBytes = statSync(placePath).size;
  if (placeBytes > MAX_PLACE_BYTES) {
    throw new HandInError(`game.rbxl is ${placeBytes} bytes, but must be at most ${MAX_PLACE_BYTES}`);
  }
  checkPlay();
  checkScreenshots();
}

try {
  checkHandIn();
} catch (error) {
  if (!(error instanceof HandInError)) throw error;
  console.error(`Broken hand-in: ${error.message}`);
  process.exit(1);
}

/** cpSync's filter: leave out every file and directory whose name starts with a dot (.gitkeep, .DS_Store, .git). */
const notDotted = (path: string): boolean => !basename(path).startsWith('.');

copyFileSync(join(here, 'game.rbxl'), join(out, 'game.rbxl'));
copyFileSync(join(here, 'PLAY.json'), join(out, 'PLAY.json'));
cpSync(join(here, 'src'), join(out, 'src'), { recursive: true, filter: notDotted });
mkdirSync(join(out, 'screenshots'), { recursive: true });
if (existsSync(join(here, 'screenshots'))) cpSync(join(here, 'screenshots'), join(out, 'screenshots'), { recursive: true, filter: notDotted });

// The scorer's own caps (reference/gate.json): only text_max_bytes shapes the bytes; the others refuse an entry the
// scorer would refuse (more than 4 screenshots or one over 256 KiB; a place of more than 500000 instances, whose
// scripts' sources come to over 8 MiB or whose scripts' paths come to over 1048576 characters, in all).
writeFileSync(
  join(out, 'dossier.json'),
  buildDossier(out, { text_max_bytes: 65536, screenshots: { max: 4, max_bytes: 262144 }, max_instances: 500000, scripts_max_source_bytes: 8388608, scripts_max_path_chars: 1048576 }),
);
