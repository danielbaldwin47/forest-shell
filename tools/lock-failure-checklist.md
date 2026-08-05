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

**And a third prerequisite, which is easy to miss and stops the run dead.** The
parallel context opens the PAM service named by `system.lock.fingerprintPamConfig`
(default `fprintd`) out of `configDirectory`, `/etc/pam.d`. Arch ships no
`/etc/pam.d/fprintd` — the `pam_fprintd.so` module arrives without a service
file — so on a stock install there is nothing for the context to open, and a
machine with a working, enrolled reader still shows no prompt. Confirm the file
exists before blaming the surface:

    ls /etc/pam.d/fprintd

Creating it is a two-line service, and it is worth being deliberate about,
because a PAM service file is authentication policy:

    #%PAM-1.0
    auth     required   pam_fprintd.so
    account  required   pam_permit.so

`required` rather than `sufficient` is the safe shape here: this service is only
ever consulted by the lock's own fingerprint context, and it must not become a
way to satisfy some other stack's auth. The password context is a separate
service (`system.lock.pamConfig`, default `login`) and is untouched by this.

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

Already answered on this machine, twice, and the second answer is the better
one. On 2026-08-03 `fprintd-list` was not installed at all, so the probe's
`Process` had nothing to launch and the empty stdout decided it. That tests
almost nothing: a missing binary short-circuits the parse.

**Re-run 2026-08-04 (#152), with fprintd installed.** The machine now has
`fprintd 1.94.5`, `libfprint 1.94.100`, and a real reader on the USB bus —
`06cb:009a Synaptics, Inc. Metallica MIS Touch Fingerprint Reader`. libfprint
claims none of it: the daemon starts, enumerates zero devices, and the probe's
command answers

    $ fprintd-list "$USER"
    No devices available          # on stdout, exit 1

That is the absent half done properly. The line arrives on **stdout**, which is
the stream `StdioCollector` reads (`LockAuth.qml`), so `fingerprintEnrolled` is
handed real text and returns false on it rather than on emptiness — the prompt
stays away because the parse said so. `tests/tst_lockpolicy.qml` now carries
that verbatim string; before this run every fingerprint case in it was invented
wording, which is exactly the setup that produced #161 at §2.

The enrolled half is still open, and on *this* machine it is blocked by driver
support rather than by hardware. libfprint has no driver for 06cb:009a —
enumerated twice, `fprintd` as root and libfprint's own typelib as the user,
zero devices both times, and enumeration is descriptor matching that happens
before any device is opened, so this is not permissions and not a sensor left
in a bad state.

The reader is not a libfprint device at all. 06cb:009a is a Validity-family
sensor, and the driver that knows it is **python-validity** (`DEV_9a = (0x06cb,
0x009a)` in `validitysensor/usb.py`), which ships its own daemon,
`open-fprintd`, implementing fprintd's D-Bus API in fprintd's place. That is
the stack this machine ran before its current install — CachyOS here dates to
2026-04-09 and its pacman log, unrotated, first installs `fprintd` on
2026-08-03.

**What that means for the probe, and it is not obvious.** On the
python-validity stack the *daemon* is replaced but the *client* is not:
`fprintd-list` stays the same binary from fprintd's own client tooling, so its
output format — the `Fingerprints for user` line `fingerprintEnrolled` matches
on — is unchanged, and `LockAuth`'s probe keeps working. The thing to check
before trusting a green result there is that the client is actually installed:
`open-fprintd` pulls it in as a separate package, and a stack that has the
daemon without the client gives the probe nothing to launch, which reads as
"nothing enrolled" no matter how many fingers are.

**That stack was installed here later the same day**, and the reader works.
`open-fprintd 0.7-2`, `python-validity 0.15-1`, `fprintd-clients-git` for the
client and the PAM module, `fprintd` itself gone. The probe now answers:

    found 1 devices
    Device at /net/reactivated/Fprint/Device/0
    Using device /net/reactivated/Fprint/Device/0
    Fingerprints for user daniel on DBus driver (press):
     - #0: right-index-finger

A finger was already enrolled with nothing enrolled on this install — these
sensors store the print on the sensor, so it outlived the operating system that
put it there. Worth knowing before assuming an enrolment step is needed.

Note the shape against what `tests/tst_lockpolicy.qml` had been assuming: the
driver name and press/swipe mode trail the user, and the fingers are a list on
following lines rather than a value after the colon. `fingerprintEnrolled`
survives that because it anchors on `Fingerprints for user` and nothing after
it — now pinned by a case rather than left to luck.

So the enrolled half is reachable on this machine at last. What still gates it
is the PAM service file above: `/etc/pam.d/fprintd` does not exist here, so the
fingerprint context has nothing to open. Create it, then run steps 1-5.

Record: which half you could run. Both halves need saying — "no reader here, so
the prompt stayed away" is half the criterion.

**Run on this machine (2026-08-04, #152) — enrolled half, at last.** The prompt
drew under the strip with its glyph, the right finger unlocked, and typing did
not abort it. Three of the five steps behaved. The other two did not, and both
answers came from the same measurement.

The `fprintd` PAM service was driven directly, outside the shell, printing every
conversation message with a millisecond stamp:

    [ 10915.5 ms] ERROR_MSG  | Failed to match fingerprint
    [ 10925.2 ms] TEXT_INFO  | Place your finger on the fingerprint reader
    [ 12047.8 ms] ERROR_MSG  | Failed to match fingerprint
    [ 12058.0 ms] TEXT_INFO  | Place your finger on the fingerprint reader
    [ 13547.1 ms] ERROR_MSG  | Failed to match fingerprint
    [ 13548.9 ms] RESULT     | 11 (Have exhausted maximum number of retries)

**The failure text is real and unreadable.** `Failed to match fingerprint`
arrives, and the re-prompt replaces it **9.7 ms** later — a frame at 60Hz is
16.7ms, so it never survives to be drawn. `LockAuth`'s `onPamMessage` assigns
every message unconditionally, so the error loses to whatever follows it. On
screen this reads as the prompt blinking: not an animation, a label overwritten
before it could render. The third error lasts 1.8ms before the result arrives,
so the last one is invisible too.

**The re-arm never runs.** `pam_fprintd` retries internally — `max-tries`,
default *and minimum* 3 — so all three touches happen inside one conversation,
and it then returns `PAM_MAXTRIES`. `LockAuth` treats MaxTries as final and
closes, which means `fingerprintMaxRestarts` (5) and `fingerprintRetryDelayMs`
(1000) are unreachable on a stock `pam_fprintd`. The real bound is three
touches, set by a module option this shell does not pass. The close is also
silent: the message is cleared, the prompt disappears, the reader's light goes
out, and nothing says fingerprint has stopped being an option. The password
field carries on working, and a relock resets it.

Both were filed rather than fixed in that pass — #168 for the unreadable failure
text, #169 for the unreachable re-arm and the silent withdrawal. What makes them
the same lesson as #161 one section up: the numbers were written against a
re-arm that PAM's own module never lets happen.

**Run again on the same machine, after both fixes (2026-08-04, #152).** Steps 3
and 5 now read as this file asks for them. The whole conversation, as seen:

    Place your finger on the fingerprint reader
    Place your finger on the reader again          (finger lifted too fast)
    Failed to match fingerprint                    (a wrong finger — readable)
    Out of fingerprint tries — use your password   (after the third touch, and it stays)

Three things are worth reading off that. The failure line is legible where it
had 9.7 ms before, so `fingerprintErrorDwellMs` is doing its job. The swipe-retry
prompt still comes through, so the dwell is holding errors without swallowing
ordinary messages — the failure mode a blunt "errors always win" would have had.
And the conversation ends on the third touch with the closing line on screen,
which means the budget being reported is `pam_fprintd`'s own `max-tries` rather
than a shell-side count layered over it. That was #169's choice to make
deliberately, since the other reading meant re-arming past an authentication
module's refusal.

### 3f — the same reader, after a suspend (#188)

Everything above locks the session deliberately. This step is the other way in,
and it is the one the bug was reported against: **close the lid, wait for the
machine to go down, open it again.** The shell locks *inside* logind's delay
inhibitor, so on this path the lock — and every PAM conversation it opens — is
raised seconds before the machine suspends underneath it.

Run it in this order, because the first two answers decide what the third one
means.

1. **Settle the hardware question first, with the shell out of the picture.**
   Switch to a TTY (`Ctrl+Alt+F3`), suspend from there (`systemctl suspend`),
   wake the machine, and — still on the TTY — run:

       fprintd-list "$USER"

   Then a verify: `fprintd-verify`, and touch the reader.

   > This is the gating question, and it is not about the shell at all. This
   > machine runs `open-fprintd` + `python-validity` rather than upstream
   > fprintd, and that driver loses its TLS session to the sensor across a
   > suspend. What re-establishes it is
   > `python3-validity-suspend-hotfix.service`, which is **enabled** and
   > `WantedBy=suspend.target` — it runs `systemctl --no-block restart
   > python3-validity.service open-fprintd.service` on the way back up. Note
   > `--no-block`: the restart is still in flight while logind is handing out
   > resume notifications, which is the race the shell's probe settle window
   > exists for. `open-fprintd-suspend.service` and
   > `open-fprintd-resume.service` are both disabled, and that is expected —
   > the hotfix unit is the one doing this job.
   >
   > If `fprintd-list` cannot see the device on the TTY, **stop**: the reader
   > does not come back on this hardware, nothing the shell does will light it,
   > and step 3 below is testing the fallback rather than the fix. Record the
   > `fprintd-list` output and the journal for the two units.

2. **How long it takes.** Run `fprintd-list "$USER"` immediately on wake and
   again a few seconds later. If the first fails and the second succeeds, the
   number between them is what `LockPolicy.fingerprintProbeRetryMs` ×
   `fingerprintProbeRetries` (750 ms × 4 = 3 s) has to cover. A gap wider than
   that is a finding, and it is a one-line change.

3. **Now the lock screen.** Back on the session: close the lid, wait for it to
   suspend, open it. The lock comes up. Watch the reader's illuminator, and
   read the fingerprint line without touching anything.

   **What must not happen** is the reported bug: "Failed to match fingerprint",
   then "Out of fingerprint tries — use your password", over a sensor whose
   light never came on. No touch of yours is in that transcript.

   **What should happen**, if step 1 said the reader comes back: the sensor
   lights, the line reads "Place your finger on the fingerprint reader", and a
   correct finger unlocks. If step 1 said it does not: the line reads
   "Fingerprint unavailable — use your password", once, with **no failure line
   in front of it**, and the password field takes a password.

4. **The password, on its own.** Suspend and wake again, and this time type the
   password without touching the reader. It is stranded across the same suspend
   as the fingerprint conversation and is the more serious half of the bug — a
   lock screen that will not take a password after a resume has no other way
   out.

5. **The log is the record.** Four lines carry it, and they are the seam-2 run's
   assertions on real hardware:

       lock: sleep announced — standing conversations down
       lock: fingerprint offer torn down (sleep announced) — touches discarded
       lock: resume observed — re-arming the lock conversations
       lock: rebuilding pam conversations (resume)

   Then one of these, which is the answer to step 1 read off the shell's own
   probe:

       lock: fingerprint enrolled — parallel context started
       lock: fingerprint probe could not run (attempt N) — retrying in 750ms
       lock: fingerprint probe settled: failed after 4 attempt(s)

   And if any touch was charged for something that happened while the machine
   was down, this line says so and is the bug reopening:

       lock: fingerprint offer withdrawn after N touch(es)

---

## Recording the result

Paste the answers into #96 (and #73's criterion 5) as a comment: the exact
message strings, whether the shake fired, whether the lockout message retreated,
and which fingerprint half was observable on the machine you used. A criterion
whose result lives only in someone's memory is not closed.
