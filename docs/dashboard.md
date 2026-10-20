# Dashboard

The popover that opens from the menu bar icon. Providers are sections; each section shows the metrics you've enabled.

## First launch

A fresh install opens a welcome screen instead of turning providers on by itself. It lists the providers signed in on your Mac, found without any permission dialogs, and you choose which ones to connect. After you connect providers, a one-time card at the top of the dashboard points to **Customize**, where you can turn any provider on or off; the card stays until you close it with its ✕ button.

When no provider is on, the dashboard shows **Choose Providers**, which opens Customize.

Updates never change the providers you already have on or off — but when an update ships a provider you've never seen, a local check runs once for just that provider and turns it on only if you actually have the tool. See [Which Providers Are On](provider-enablement.md) for the full lifecycle.

Each provider card leads with its **Always Visible** metrics. Click the centered chevron between the Always Visible and **On Demand** rows to show or hide the On Demand metrics; the whole row is clickable and lights softly under the pointer, and the chevron turns as the section opens. Open cards stay open across popover closes and app restarts. A provider with neither On Demand metrics nor quick links shows no chevron.

When open, a divider separates Always Visible and On Demand rows. A provider with no data shows only its header and a **No data yet** tag until data arrives.

## Activity

The card at the top shows how fast tokens are being used right now. The big number defaults to tokens per minute over the last 10 minutes (the same window Syrtis uses, so one large request doesn't swing it); spending lives in the **Spend** card below, so this card only answers "how fast right now". The unit stays in place as the number changes. Opened, the headline adds an estimate like `≈ $84/hr`: the live speed priced at today's average cost per token for each provider, so it shifts with today's model mix (for subscription plans it's the API-equivalent value, not a charge). Tokens include cache reads, like the daily totals. Below it a small stacked chart shows that same speed over the last half hour as a smooth line, one band per provider (or per device, with the **Providers / Devices** switch). The dot next to the number breathes while anything is in use and goes still when nothing is.

The speed has three states: **—** with `reading logs` while the logs are read for the first time after launch (rare: the app takes a reading right away), the number while anything is in use, and **Idle** with when things last moved (`last active 12m ago`, or `no activity in 30 min`). Claude and Codex headers show `idle` the same way.

Speed for this Mac comes from Claude Code and Codex logs as they are written, every 2 seconds while the panel is open and every 30 seconds in the background (only new lines are read), so the speed is already current when you open it. Remote devices update at each import, so their speed is a snapshot; a device that hasn't imported in 15 minutes, or whose last import failed, is shown as not live with how long ago it last updated. **Usage From** applies here too, and a provider turned off in Customize is left out of the card, just as it is left out of the other live cards.

Run-out warnings stay on the provider meters. Click the Activity header to show or hide its chart and breakdown. The **Providers / Devices** switch appears automatically when remote devices exist.

## Tokens, Spend, and Models

These cards sit below Activity. Click a header to show or hide its details. Once a card is open its chevron hides until the pointer is over the header. Each card has its own **Today / Yesterday / 30 Days** choice and remembers it when closed. The 30 Days period matches the provider spend rows: today plus the previous 30 days.

- **Tokens** shows the selected period's tokens, a 14-day chart, and each provider's share.
- **Spend** does the same for dollars, counting providers that price their usage.
- **Models** shows the most-used model and its share, then the top five models when open. Shares use cost, or tokens when nothing was priced.

Tokens and Spend bars stack each provider's contribution in that provider's color, with the first and last day labeled under them when open. Spend is priced at API rates, so it reads as an estimate (`estimated today`), shares under 1% show as `<1%`, and usage that couldn't be priced is called out instead of counted as $0. Open cards compare Today with yesterday, Yesterday with the day before, and 30 Days with its daily average. All three follow **Usage From**, exclude providers turned off in Customize, and hide when no provider keeps the history they need. They start closed and can be turned off in [Settings → Live Activity](settings.md#live-activity). Right-click any of the four live cards and choose **Hide … Card** to remove it; turn it back on in [Settings → Live Activity](settings.md#live-activity).

Claude and Codex headers also show live speed (with several accounts, on the card signed in at the default home). Active providers can animate their meters. Both features can be turned off in [Settings → Live Activity](settings.md#live-activity).

## Rows

**Metrics with a limit** (session, weekly, credits with a cap) show a progress bar with:

- A fill whose color is a verdict on the whole window, based on your current burn rate: blue while you're on course to finish with at least 10% to spare, yellow when you're projected to land inside the last 10% with a little cushion to spare, red when you're projected to run out before the reset — or to finish right at the limit with nothing to spare. So a half-full bar burning too fast is already red, and a nearly-drained bar coasting to the reset stays blue. Bars without a reset window (like a credit balance), and fresh windows too young to project, color by the level itself instead: yellow once 80% is used, red once 10% or less is left. The colors come from the system palette, so they adapt to light/dark and accessibility settings, and they never flip with the Used/Left toggle.
- A headline like `52% left` or `48% used`. **Click it** to flip between Used and Left everywhere — hovering shows the opposite reading.
- A reset label like `Resets in 3h 25m` or `Resets today at 6:38 PM`. **Click it** to flip between countdown and exact time everywhere — hovering shows the other format.
- A blue bar reads `lasts until reset` next to the metric name, with an even-pace tick on the bar (Always Show Pacing, on by default in Settings; turn it off and blue bars stay plain). A metric with nothing used yet stays plain even then — there's no pace to project until something has been spent.
- A yellow bar adds a `~3% left at reset` note right-aligned next to the metric name, plus the even-pace tick on the bar (where usage would sit if you burned evenly across the window). That cushion is always at least 1%; if you're projected to finish with nothing to spare it turns red instead (so a yellow bar never reads `~0% spare`).
- A red bar swaps the note for an orange `runs out in ~1h 9m` — how long until the current pace uses it up — and still shows the even-pace tick on the bar. When you're projected to finish right at the limit, with no run-out before the reset, it reads `runs out before reset`.
- Once the balance is spent — actually empty, or so close it rounds to `0` (like `0% left` or `$0.00`) — the bar stays red and the note reads `Limit reached`, no matter how gentle the burn rate looked. A visibly empty bar never shows a calmer color.
- **Hover the bar**, the spare note, or a warning for the pace projection at reset — the one number not already on the row: a blue bar shows the cushion you're on course to finish with (`~35% left at reset`), a yellow bar the usage it complements the spare note with (`~92% used at reset`), a red bar how far past the limit you're projected to land (`~12% over limit at reset`, or `~100% used at reset` when you're projected to finish right at it). Once spent it reads `Limit reached`.

**Metrics without a limit** (daily spend, balances) show as a single line like `$4.08 spent` or `1.2M tokens`. The Today / Yesterday / Last 30 Days rows combine cost and tokens (`$4.08 · 1.2M tokens`) and can be turned on or off in Customize. A day with no usage reads "No data" rather than a misleading `$0.00 · 0 tokens` — the same as when the source can't be loaded at all. Big numbers are abbreviated to keep rows tidy (`$2.06K`, `1.5B`) — hover the value to see the exact figures and source note, such as a local estimate.

For Claude, Codex, Cursor, Grok, and OpenCode spend rows, the value gently highlights when you point at it, signaling it's interactive; hovering it for a moment opens a small model breakdown for that period: a ranked list of models, each showing its name and spend on one line, its share percentage and tokens on the next, and a thin share bar. Cursor groups its per-thinking-effort model names (like `claude-opus-4-8-thinking-max`) under the base model. Long tails fold into **Other** — anything past the top named models or under 5% of the period. Models no pricing source can price don't appear here (or in the row's totals) at all; the row's warning triangle names them instead (see [Pricing](pricing.md)).

**Last 14 Days** (Claude, Codex, Cursor, Grok, and OpenCode; listed as Usage Trend in Customize) is a small bar chart of the last two weeks of token usage with the average spend per day — one bar per day, drawn from the same source as that provider's spend rows (local logs for Claude, Codex, Grok, and OpenCode; Cursor's usage export for Cursor). **Hover it** for the peak day, the date range, and the source. It's on by default; turn it off or reorder it from Customize like any other metric. It can't be starred for the menu bar — the strip shows single values, not a chart.

**Top Models Today** shows today's top models as one bar split by each model's share of the day's cost, with a legend underneath (share and cost lined up on the right). It is off by default; turn it on in Customize to show it on demand. The Models live card covers models across providers.

On demand, Today, Yesterday, and Last 30 Days share one **Usage** row with three columns. Each column keeps the amber warning when a model couldn't be priced, and clicking a column opens that period's model breakdown. The On Demand groups (Top Models Today, Usage) each have a quiet title and are separated by space alone. **Rate Limit Resets** stays a single row with the count (`1 available`); hover it to see each reset's expiry, soonest first, and click to keep that popover open. For Codex, **Use** in the popover asks for confirmation before anything is spent. Claude's resets are shown read-only, since Anthropic offers no way to redeem them from outside its own apps.

Rows with a reset date tick every 30 seconds, so countdowns and pace stay live between refreshes.

## Right-click menus

Every row: **Hide · Star for menu bar / Unstar · Refresh \<provider\> · Customize…** (Customize opens straight to that provider's metrics.)
Provider headers: **Hide \<provider\> · Refresh \<provider\> · Customize…** (Hide turns the whole provider off; turn it back on in Customize. Customize opens straight to that provider's metrics.)

## Footer

The bar pinned to the bottom of the popover. On the left: the app version, and a live "Refreshes in …" countdown you can click (a refresh arrow appears under the pointer) (or press **⌘R**) to refresh right away. On the right: an **Options** menu button. It holds everything in one place — **Customize**, **Settings**, **Check for Updates…** (when updates are available in the build), **Report an Issue…**, **About Quotapus**, and **Quit Quotapus**. **Report an Issue…** opens GitHub's issue chooser in your browser.

## Customize

Open Customize from the footer's **Options** menu (or press **Return**). It's a two-level screen: a list of providers, then a provider's detail.

The **provider list** shows every provider with a switch to turn it on or off, a count of its metrics, and a chevron into its detail. Turn a provider off and it stays in the list, greyed — its metrics hide from the dashboard and menu bar but keep their setup for when you turn it back on. Drag enabled providers by their grip to reorder; tap a row to open its detail. On a fresh install only the providers you connect on the welcome screen start on (see "First launch" above); this list is where you add the rest.

A provider's **detail** has a back button and provider-specific Reset control in its top bar, followed by two metric sections: **Always Visible** (shown on the dashboard card) and **On Demand** (tucked behind the header chevron). Each metric row has a drag grip, its name, an always-visible star for the menu bar, and an on/off switch. Drag a metric into the other card—or onto one of that card's rows—to move it between Always Visible and On Demand. An empty card shows a dashed **Drag metrics here** target. You can star up to two metrics per provider. OpenRouter and Z.ai also show an **API Key** section here, where you can add, replace, reveal, or clear that provider's key.

Drag-reorder also works directly on the dashboard — drag a row within its provider, drag it across the Always Visible / On Demand divider while the card is open, or drag a provider header to reorder sections. On a Force Touch trackpad you'll feel a light tap each time the dragged item snaps into a new slot.

The default reset layout keeps each provider's core quota meters and Usage Trend always visible, then tucks balances, reset details, and spend-history rows on demand. Optional detail rows like Claude Sonnet and Cursor Requests/Credits stay off by default, but start on demand if you enable them.

Made a change you didn't mean to? Press **⌘Z** to undo — it works anywhere in the popover (the dashboard and Customize alike) and steps back through your recent customization changes one at a time: hiding or showing a metric, reordering metrics or whole providers, starring or unstarring, and moving a metric across the divider all undo. Each step restores the exact previous arrangement. Undo is per-session (it starts fresh after a relaunch), and resetting clears it.

When Quotapus ships a new default metric, existing layouts get it once. If you turn it off, it stays off. A provider's **Reset** button (top right of its detail) restores that provider's default metrics, order, menu-bar stars, and which metrics start on demand, but leaves other providers and the provider order untouched. The **Reset All Customization** button (top right of the provider list) does the same for every provider at once, restores the default provider order, and re-detects your installed tools — turning providers back on for exactly the tools set up on your Mac, just like first launch (see [Which Providers Are On](provider-enablement.md)). It asks for confirmation first, since it wipes the whole layout and re-detects providers, and can't be undone.

## Keyboard

| Key | Action |
|---|---|
| Return | From the dashboard, open Customize; from a provider detail, return to the provider list; from the provider list or Settings, return to the dashboard |
| Esc | From a provider detail, return to the provider list; from the provider list or Settings, return to the dashboard; from the dashboard, close the popover |
| ⌘Z | Undo the last customization change (app-wide; repeat to step back) |
| ⌘R | Refresh now from the dashboard or Settings (skips the cache) |
| ⌘, | Open / close Settings (in the popover) |

A global shortcut (recorded in Settings) toggles the popover from anywhere.

## Closing

Closing the popover resets navigation state: scroll position returns to the top and Customize / Settings close. Provider cards remember whether their On Demand section was open.
