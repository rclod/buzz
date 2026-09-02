import { expect, test } from "@playwright/test";

import { waitForAnimations } from "../helpers/animations";
import { installMockBridge, TEST_IDENTITIES } from "../helpers/bridge";

const SHOTS = "test-results/activity-scope-label";

const AGENT_PUBKEY = TEST_IDENTITIES.tyler.pubkey;
const LONG_AGENT_NAME =
  "Observer Agent With An Exceptionally Long Display Name";
const AGENTS_CHANNEL_ID = "94a444a4-c0a3-5966-ab05-530c6ddc2301"; // #agents
const RANDOM_CHANNEL_ID = "4207c81d-22f5-506d-a06b-a1fe7aea8b09"; // #random

// Open the activity pane via profile → "View activity" (same ingress the
// observer-feed screenshot spec uses).
async function openActivityFromChannel(
  page: import("@playwright/test").Page,
  channelTestId: string,
  channelTitle: string,
) {
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await page.getByTestId(channelTestId).click();
  await expect(page.getByTestId("chat-title")).toHaveText(channelTitle);

  const messageRow = page
    .getByTestId("message-row")
    .filter({ has: page.getByText("Observer Agent", { exact: false }) });
  await expect(messageRow.first()).toBeVisible({ timeout: 8_000 });
  await messageRow.first().getByRole("button").first().click();

  const profilePanel = page.getByTestId("user-profile-panel");
  await expect(profilePanel).toBeVisible({ timeout: 10_000 });

  const activityBtn = page.getByTestId(
    `user-profile-view-activity-${AGENT_PUBKEY}`,
  );
  await expect(activityBtn).toBeVisible({ timeout: 5_000 });
  await activityBtn.click();

  const panel = page.getByTestId("agent-session-thread-panel");
  await expect(panel).toBeVisible({ timeout: 10_000 });
  return panel;
}

test.describe("activity panel scope label", () => {
  test("channel-targeted pane shows the channel name", async ({ page }) => {
    await installMockBridge(page, {
      managedAgents: [
        {
          pubkey: AGENT_PUBKEY,
          name: "Observer Agent",
          status: "running" as const,
          channelNames: ["agents"],
        },
      ],
    });

    const panel = await openActivityFromChannel(
      page,
      "channel-agents",
      "agents",
    );
    await expect(page.getByTestId("agent-session-agent-name")).toHaveText(
      "Observer Agent",
    );
    await expect(page.getByTestId("agent-session-agent-avatar")).toBeVisible();
    const scope = page.getByTestId("agent-session-scope-label");
    await expect(scope).toHaveText("Activity · #agents");
    const recency = page.getByTestId("agent-session-recency-label");
    await expect(recency).toHaveText("No updates yet");
    await expect(recency).toBeVisible();

    // Simulate long-scope pressure deterministically: scope owns truncation
    // while the independently shrinking recency stays visible.
    await scope.evaluate((element) => {
      element.style.width = "5rem";
      element.style.flex = "none";
    });
    expect(
      await scope.evaluate((element) => element.scrollWidth),
    ).toBeGreaterThan(await scope.evaluate((element) => element.clientWidth));
    await expect(recency).toBeVisible();

    await page.getByTestId("agent-session-settings-menu-trigger").click();
    await page.getByTestId("agent-session-toggle-raw-feed").click();
    await expect(scope).toHaveText("Raw ACP activity · #agents");
    expect(
      await scope.evaluate((element) => element.scrollWidth),
    ).toBeGreaterThan(await scope.evaluate((element) => element.clientWidth));
    await expect(recency).toHaveText("No updates yet");
    await expect(recency).toBeVisible();
    await page.keyboard.press("Escape");

    await waitForAnimations(page);
    await panel.screenshot({ path: `${SHOTS}/01-channel-scoped.png` });
  });

  test("restored pane stays scoped to the current channel", async ({
    page,
  }) => {
    // The agent lives in #random only. Restoring an agentSession URL on
    // #agents therefore has no in-memory source-channel hint, but the channel
    // surface must still isolate activity to #agents. The app uses a hash
    // router, so the deep link goes in the hash.
    await installMockBridge(page, {
      managedAgents: [
        {
          pubkey: AGENT_PUBKEY,
          name: LONG_AGENT_NAME,
          status: "running" as const,
          channelNames: ["random"],
        },
      ],
      searchProfiles: [
        {
          pubkey: AGENT_PUBKEY,
          displayName: LONG_AGENT_NAME,
          isAgent: true,
        },
      ],
    });

    await page.goto(
      `/#/channels/${AGENTS_CHANNEL_ID}?agentSession=${AGENT_PUBKEY}`,
      { waitUntil: "domcontentloaded" },
    );
    await expect(page.getByTestId("chat-title")).toHaveText("agents");

    await page.waitForFunction(
      () => typeof window.__BUZZ_E2E_SEED_OBSERVER_EVENTS__ === "function",
    );
    await expect
      .poll(() =>
        page.evaluate(
          () =>
            window.__BUZZ_E2E_HAS_MOCK_LIVE_SUBSCRIPTION__?.({
              channelName: "agents",
            }) ?? false,
        ),
      )
      .toBe(true);
    await page.evaluate((pubkey) => {
      window.__BUZZ_E2E_EMIT_MOCK_TYPING__?.({
        channelName: "agents",
        pubkey,
      });
    }, AGENT_PUBKEY);
    await page.evaluate(
      ({ agentPubkey, agentsChannelId, randomChannelId }) => {
        const toolEvent = (
          seq: number,
          channelId: string,
          sessionId: string,
          title: string,
        ) => ({
          seq,
          timestamp: new Date(Date.now() + seq).toISOString(),
          kind: "acp_read",
          agentIndex: 0,
          channelId,
          sessionId,
          turnId: `${sessionId}-turn`,
          payload: {
            method: "session/update",
            params: {
              sessionId,
              update: {
                sessionUpdate: "tool_call",
                toolCallId: `${sessionId}-tool`,
                status: "completed",
                title,
                kind: "shell",
                rawInput: { command: title },
              },
            },
          },
        });

        window.__BUZZ_E2E_SEED_OBSERVER_EVENTS__?.({
          agentPubkey,
          events: [
            toolEvent(
              1,
              randomChannelId,
              "parent-session",
              "Parent channel history",
            ),
            toolEvent(
              2,
              agentsChannelId,
              "new-session",
              "New channel activity",
            ),
          ],
        });
      },
      {
        agentPubkey: AGENT_PUBKEY,
        agentsChannelId: AGENTS_CHANNEL_ID,
        randomChannelId: RANDOM_CHANNEL_ID,
      },
    );

    const panel = page.getByTestId("agent-session-thread-panel");
    await expect(panel).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId("agent-session-agent-name")).toHaveText(
      LONG_AGENT_NAME,
    );
    const agentName = page.getByTestId("agent-session-agent-name");
    expect(
      await agentName.evaluate((element) => element.scrollWidth),
    ).toBeGreaterThan(
      await agentName.evaluate((element) => element.clientWidth),
    );
    const scope = page.getByTestId("agent-session-scope-label");
    await expect(scope).toHaveText("Activity · #agents");
    await expect(
      panel.getByText("New channel activity", { exact: true }),
    ).toBeVisible();
    await expect(
      panel.getByText("Parent channel history", { exact: true }),
    ).toHaveCount(0);
    const composerActivity = page.getByTestId("bot-activity-composer-trigger");
    await expect(composerActivity).toBeVisible();
    await expect(composerActivity).toContainText("New channel activity");
    await expect(page.getByTestId("message-typing-indicator")).toHaveCount(0);
    const recency = page.getByTestId("agent-session-recency-label");
    await expect(recency).not.toHaveText("No updates yet");
    await expect(recency).toBeVisible();

    await page.setViewportSize({ width: 720, height: 700 });
    await expect(scope).toBeVisible();
    await expect(recency).toBeVisible();
    const recencyWidth = await recency.evaluate(
      (element) => element.clientWidth,
    );

    await page.getByTestId("agent-session-settings-menu-trigger").click();
    await page.getByTestId("agent-session-toggle-raw-feed").click();
    await expect(scope).toHaveText("Raw ACP activity · #agents");
    await expect(recency).toBeVisible();
    expect(await recency.evaluate((element) => element.clientWidth)).toBe(
      recencyWidth,
    );
    await page.keyboard.press("Escape");

    await waitForAnimations(page);
    await panel.screenshot({ path: `${SHOTS}/02-restored-channel-scoped.png` });
  });
});
