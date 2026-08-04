# The lock's failure path, on a real session (#96)

Three of #73's criterion-5 answers cannot be produced by any harness in this
repo, and this file is what stands in their place: a run sheet for a human at
the machine, and a place to say what was seen.

Why they are here and not in a script:

- **The shake** is an animation on a real PAM rejection. `tests/` cannot import
  `PamContext`; the nested compositor never presents (#85), so seam 2 can drive
  the conversation but never see what the surface does about the answer; and a
  capture is one still frame, which is the one thing an animation is not.
- **faillock's message** needs a real faillock, counting real failures.
- **The fingerprint prompt** needs a reader with a finger enrolled in it.

Everything about these three that *is* a state rather than an event has been
pulled inward and is repeatable off-session:

    tools/capture-harness.sh out.png --surface lock --lock-state summoned,failed
    tools/capture-harness.sh out.png --surface lock --lock-state lockout
    tools/capture-harness.sh out.png --surface lock --lock-state summoned,fingerprint

Run those with `--session` when the icons matter: `MultiEffect` draws nothing
on the offscreen scenegraph, so the fingerprint glyph is missing from an
offscreen capture and only its label renders.

`tests/tst_lockpolicy.qml` holds the decisions behind them — `messageTone`,
`isLockout`, `lockedOutBy`, `fingerprintEnrolled`.

---

## 1. A wrong password

Lock the session as you normally would, then:

1. Type a wrong password and press Enter.
2. Watch for **all three**:
   - the field **shakes** — four legs (−8px, +8px, −4px, back to 0; the swing
     is `Theme.space2`) over `Theme.motionFast`, 140ms end to end, so watch for
     it — and the fog pulses;
   - a message appears under the field in `Theme.textPrimary` — on a stock Arch
     stack that is `Authentication failed`, which is the shell's *own* fallback
     and not PAM's text (see below);
   - the field clears, stays live, and **keeps asking** — no counter, no
     cooldown of the shell's own (#30: the retry limit is faillock's).
3. Type the right password. It unlocks.

With reduced effects on (`Theme.animateTransforms` false, #69) the shake is
deliberately dropped and the fog pulse carries the refusal on its own — still
visibly a refusal, just not a moving one. Check the knob before calling a
missing shake a bug.

**Which message you get, and why it is not the verbatim one.**
`LockPolicy.failureText` returns PAM's message when there is one and its own
wording when there is not, and the two are one letter apart:

    if (pamMessage) return pamMessage;      // PAM verbatim
    case "failed": return "Authentication failed";   // the shell's fallback

Measured on a real session (2026-08-04, #152): the screen said `Authentication
failed`, the fallback. Arch's `pam_unix` conveys a plain auth failure by return
code and sends **nothing** through the conversation, so `password.message` is
empty at completion and the fallback is what renders. The `authentication
failure` text people remember is what `pam_unix` writes to the journal, not a
`PAM_ERROR_MSG` to the conversation. This file previously claimed the opposite;
it was never checked against a real stack until #152.

So §1 exercises the **fallback** branch. The verbatim branch is §2's — `pam_faillock`
does message through the conversation, which is why its text arrives unrewritten.
If §2 also shows a shell fallback (`Too many attempts`), then nothing on that
stack ever reaches the verbatim path, and that is worth its own ticket. It did
not: §2 was run here on 2026-08-04 and PAM's own text came through untouched.

Record: the exact message string, and which of the two branches it is. `failed`
is the shell's, `failure` is PAM's — one word, opposite conclusions, so read it
off the screen rather than from memory. The log cannot settle it: the live path
logs the *kind* only (`password attempt failed`), never the text, and `posed`
lines come from the capture harness, so a real session emits none.

## 2. faillock's lockout

**Read this before running it.** You are deliberately locking your own account
out of authentication. `pam_faillock`'s default `unlock_time` on Arch is 600
seconds, and if `/etc/security/faillock.conf` sets `unlock_time = 0` the lock
does not expire on its own at all.

Before you start:

1. Check the policy you are about to trigger:

       grep -vE '^\s*(#|$)' /etc/security/faillock.conf

   Confirm `deny` (default 3) and `unlock_time` (default 600). If
   `unlock_time = 0`, do not do this without a second route in.

2. Open a root shell somewhere the lock cannot swallow — a second TTY
   (`Ctrl+Alt+F2`, log in, `sudo -i` and leave it open) or an SSH session from
   another machine. That shell is how you get out:

       faillock --user "$USER" --reset

Then:

3. Lock the session and enter a wrong password `deny` times.
4. On the attempt that trips it, watch for:
   - the message turning **ember** (`Theme.accentEmber`), not the ordinary
     error colour — the lockout tone (`LockPolicy.messageTone`);
   - faillock's text verbatim. It speaks twice — the refusal (`Account locked
     due to 3 failed logins`) and then, where `unlock_time` is set, the
     countdown. The countdown is the one that lands, because it is spoken
     second, and on this stack (2026-08-04) it reads `(10 minutes left to
     unlock)` — upstream Linux-PAM's `_("(%d minutes left to unlock)")`,
     parentheses and all, **not** `Try again in N minutes`. That guess is what
     #161 was: `LockPolicy.lockoutPatterns` was written against wording nobody
     had checked, matched none of the real text, and the lockout went
     unrecognised on every Arch default install;
   - the shell **still asking** — the field stays live and takes input. The
     shell has no idea when faillock starts saying yes again, so it never stops
     offering (#30).
5. **The message must not retreat.** Stop typing and wait out the summon
   timeout (`LockPolicy.summonTimeoutMs`). The field may go quiet; the lockout
   message must stay on screen. That is the whole point of `clearMessage`
   refusing to forget a lockout, and it is what has never been watched.
6. **Look again on the *next* attempt, before typing anything.** Once the
   account is locked, `pam_faillock` announces it in its **preauth** phase —
   before `pam_unix` puts up the prompt — so the lockout is on screen while the
   field is live and empty. It must already be ember there, and must survive the
   summon timeout there too. This is #164: until it was fixed, the announcement
   rendered `Theme.textSecondary` (a `pam_info` is not a `PAM_ERROR_MSG`) and
   retreated, for as long as the user took to type a password they had already
   been told would not work.
7. Reset from the shell you kept open (`faillock --user "$USER" --reset`), then
   unlock with the right password.

Record: the message string, the colour, and whether it survived the timeout —
at both moments, step 4's and step 6's, because they were two different answers
until #164.

Also say whether the string is faillock's own or the shell's fallback (`Too many
attempts`, the `maxTries` arm of `LockPolicy.failureText`). §1 established that
this stack's `pam_unix` sends no message, which left §2 as the only step that
could show the verbatim path working at all.

**Run on this machine (2026-08-04, #152).** It answered yes: `(10 minutes left
to unlock)` rendered unrewritten, so `failureText`'s verbatim branch is sound and
the shell's fallbacks were never the problem. Everything §1b found wrong lived in
the classification on top of it — #161 (the text matched nothing) and #164 (the
match was acted on a conversation phase too late). With both fixed and the run
repeated, the ember arrives with the announcement and stays. The `maxTries` arm
is still unexercised here and probably always will be: this stack's
`pam_faillock` returns `PAM_AUTH_ERR`, so ~60 attempts logged `password attempt
failed` and not one logged `maxTries`. That is why `isLockout` carries the
weight, and why its patterns are worth more than the return code.

## 3. The fingerprint prompt

Needs a reader with an enrolled finger — `fprintd-list "$USER"` must name at
least one. `system.lock.fingerprint` must also be on.

**Where a finger is enrolled:**

1. Lock the session.
2. The prompt draws under the status strip: the `fingerprint-pattern` glyph and
   whatever fprintd said (`Place your finger on the reader`).
3. Touch the reader with the wrong finger. **Read the line before it changes**
   — this is #168's acceptance, and the only place it can be checked. It must
   say `Failed to match fingerprint` long enough to be read
   (`LockPolicy.fingerprintErrorDwellMs`, 1.5s), and then go back to the
   prompt on its own. Before #168 it did neither: pam_fprintd re-prompts 9.7ms
   after the failure, inside one 16.7ms frame, so the failure was never drawn
   and a wrong finger looked identical to a finger the reader never saw. A
   blink with nothing readable in it is the regression.
   The reader's own prompt then comes back and it waits for another touch. The
   shell does *not* re-arm anything here — this step used to claim it did
   (`fingerprintMaxRestarts`, `fingerprintRetryDelayMs`), and #169 found both
   numbers dead: pam_fprintd re-prompts **inside** the one conversation.
4. Touch it wrong twice more. Three is all there is — `max-tries`, pam_fprintd's
   own option, whose default and documented minimum are both 3. Counted, not
   assumed: `LockPolicy.fingerprintTouchBudget` says 3 and
   `lock: fingerprint offer withdrawn after N touch(es)` says what the
   module really spent. **If those two disagree the log says so as a warning**
   (`pam_fprintd spent N touch(es), not the 3 LockPolicy documents`) — that
   line is the finding, and it means the budget moved under us.
5. After the third, the line must **say fingerprint is over and point at the
   password** (`Out of fingerprint tries — use your password`) and stay on
   screen. It arrives up to a dwell late on purpose — the third touch is a
   failure like the other two and keeps its 1.5s, so `Failed to match
   fingerprint` is still readable and the closing line follows it rather than
   wiping it (#168). This is #169's acceptance. Before it, the line simply vanished: the
   reader's light going out was the only feedback, and that light is the
   hardware's, not the shell's. A prompt that disappears with nothing in its
   place is the regression.
6. Type the password. It still works, and a relock offers the finger again —
   the withdrawal is for this lock only.
7. Restart, and this time touch it with the right finger. It unlocks.
8. Start typing instead of touching. The prompt **stays** — nothing aborts the
   fingerprint context on a keystroke; it closes when PAM answers, when the
   touches run out, or when the lock ends. Note whether both conversations on
   screen at once read as one screen or as two competing ones. (They are
   deliberately on separate lines: the prompt sits under the status strip, not
   in it.)

**Where nothing is enrolled** (this machine, and every machine with no reader):

    fprintd-list "$USER"    # "no devices available" or no enrolled fingers

Lock, and confirm **nothing** draws where the prompt would be. A prompt that
cannot be answered is worse than no prompt, which is why the probe gates it.
`LockPolicy.fingerprintEnrolled` is what reads that answer out of fprintd, and
`tests/tst_lockpolicy.qml` covers the reading; what a real session adds is that
the surface honours it.

Already answered on this machine (2026-08-03): `fprintd-list` is not installed
at all, so the probe cannot find an enrolled finger, and every lock capture
taken without `--lock-state fingerprint` renders nothing where the prompt
would be. That is the absent half. The enrolled half needs a machine with a
reader and is still open.

Record: which half you could run. Both halves need saying — "no reader here, so
the prompt stayed away" is half the criterion.

---

## Recording the result

Paste the answers into #96 (and #73's criterion 5) as a comment: the exact
message strings, whether the shake fired, whether the lockout message retreated,
and which fingerprint half was observable on the machine you used. A criterion
whose result lives only in someone's memory is not closed.
