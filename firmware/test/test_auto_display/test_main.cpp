#include <cassert>

#include "auto_display_logic.h"
#include "now_page_logic.h"
#include "quote_transport_logic.h"

void testLegacyBridgeDefaults() {
  const AutoDisplayConfig config{};

  assert(!config.claudeEnabled);
  assert(config.codexEnabled);
  assert(config.approvalEnabled);
  assert(config.musicEnabled);

  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == 900);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds == 10);
  assert(config.scheduled[AUTO_SCHEDULED_QUOTE].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_QUOTE].intervalSeconds == 1800);
  assert(config.scheduled[AUTO_SCHEDULED_QUOTE].durationSeconds == 12);
  assert(!config.scheduled[AUTO_SCHEDULED_STOCK].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_STOCK].intervalSeconds == 900);
  assert(config.scheduled[AUTO_SCHEDULED_STOCK].durationSeconds == 10);
  assert(!config.scheduled[AUTO_SCHEDULED_NET].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_NET].intervalSeconds == 600);
  assert(config.scheduled[AUTO_SCHEDULED_NET].durationSeconds == 10);
}

void testClaudeCanBeDisabled() {
  AutoSelectionInputs in{};
  in.claudeWorking = true;
  in.config.claudeEnabled = false;
  assert(chooseAutoDisplay(in) == AUTO_IDLE);

  in.config.claudeEnabled = true;
  assert(chooseAutoDisplay(in) == AUTO_CLAUDE);
}

void testApprovalsCanBeDisabled() {
  AutoSelectionInputs in{};
  in.approvalNeeded = true;
  in.config.approvalEnabled = false;
  assert(chooseAutoDisplay(in) == AUTO_IDLE);

  in.config.approvalEnabled = true;
  assert(chooseAutoDisplay(in) == AUTO_APPROVAL);
}

void testAutoAgentSelectionPinsOnlyEnabledCodexWhileIdle() {
  AgentDisplaySelectionInputs in{};
  in.claudeEnabled = false;
  in.codexEnabled = true;
  in.current = AGENT_DISPLAY_CLAUDE;
  in.nowMs = 6000;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CODEX);

  in.current = AGENT_DISPLAY_CODEX;
  in.nowMs = 12000;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CODEX);
}

void testAutoAgentSelectionPinsOnlyEnabledClaudeWhileIdle() {
  AgentDisplaySelectionInputs in{};
  in.claudeEnabled = true;
  in.codexEnabled = false;
  in.current = AGENT_DISPLAY_CODEX;
  in.nowMs = 6000;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CLAUDE);

  in.current = AGENT_DISPLAY_CLAUDE;
  in.nowMs = 12000;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CLAUDE);
}

void testBothEnabledIdleAgentsKeepSlowAlternation() {
  AgentDisplaySelectionInputs in{};
  in.claudeEnabled = true;
  in.codexEnabled = true;
  in.current = AGENT_DISPLAY_CLAUDE;
  in.nowMs = 5999;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CLAUDE);

  in.nowMs = 6000;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CODEX);
}

void testOnlyEnabledWorkingAgentIsSelected() {
  AgentDisplaySelectionInputs in{};
  in.claudeEnabled = false;
  in.codexEnabled = true;
  in.codexWorking = true;
  in.current = AGENT_DISPLAY_CLAUDE;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CODEX);

  in.claudeEnabled = true;
  in.codexEnabled = false;
  in.claudeWorking = true;
  in.codexWorking = false;
  in.current = AGENT_DISPLAY_CODEX;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CLAUDE);
}

void testExactlyOneWorkingOfBothEnabledAgentsIsSelected() {
  AgentDisplaySelectionInputs in{};
  in.claudeEnabled = true;
  in.codexEnabled = true;
  in.claudeWorking = true;
  in.current = AGENT_DISPLAY_CODEX;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CLAUDE);

  in.claudeWorking = false;
  in.codexWorking = true;
  in.current = AGENT_DISPLAY_CLAUDE;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CODEX);
}

void testBothEnabledWorkingAgentsKeepFastAlternation() {
  AgentDisplaySelectionInputs in{};
  in.claudeEnabled = true;
  in.codexEnabled = true;
  in.claudeWorking = true;
  in.codexWorking = true;
  in.current = AGENT_DISPLAY_CLAUDE;
  in.nowMs = 1999;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CLAUDE);

  in.nowMs = 2000;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CODEX);
}

void testFixedAgentDisplayIgnoresAutoEnablementAndActivity() {
  AgentDisplaySelectionInputs in{};
  in.claudeEnabled = false;
  in.codexEnabled = false;
  in.codexWorking = true;
  in.codexNeedsInput = true;
  in.current = AGENT_DISPLAY_CODEX;
  in.mode = AGENT_DISPLAY_FIXED_CLAUDE;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CLAUDE);

  in.claudeWorking = true;
  in.claudeNeedsInput = true;
  in.current = AGENT_DISPLAY_CLAUDE;
  in.mode = AGENT_DISPLAY_FIXED_CODEX;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CODEX);
}

void testApprovalSwitchIndependentlyAllowsRequestingDisabledAgent() {
  AgentDisplaySelectionInputs in{};
  in.claudeEnabled = false;
  in.codexEnabled = true;
  in.approvalEnabled = true;
  in.claudeNeedsInput = true;
  in.current = AGENT_DISPLAY_CODEX;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CLAUDE);

  in.approvalEnabled = false;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CODEX);
}

void testNoEnabledAgentKeepsCurrentIdlePet() {
  AgentDisplaySelectionInputs in{};
  in.claudeEnabled = false;
  in.codexEnabled = false;
  in.current = AGENT_DISPLAY_CLAUDE;
  in.nowMs = 6000;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CLAUDE);

  in.current = AGENT_DISPLAY_CODEX;
  in.nowMs = 12000;
  assert(chooseAgentDisplay(in) == AGENT_DISPLAY_CODEX);
}

void testPriorityAndFairScheduledChoice() {
  AutoSelectionInputs in{};
  in.config.codexEnabled = true;
  in.codexWorking = true;
  in.musicPlaying = true;
  assert(chooseAutoDisplay(in) == AUTO_CODEX);

  in.codexWorking = false;
  assert(chooseAutoDisplay(in) == AUTO_MUSIC);

  in.musicPlaying = false;
  in.dueMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE;
  in.validMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE;
  in.lastShownWeather = 200;
  in.lastShownQuote = 100;
  assert(chooseAutoDisplay(in) == AUTO_QUOTE);

  in.approvalNeeded = true;
  assert(chooseAutoDisplay(in) == AUTO_APPROVAL);
}

void testAllItemsCanBeDisabled() {
  AutoSelectionInputs in{};
  in.config.claudeEnabled = false;
  in.config.codexEnabled = false;
  in.config.approvalEnabled = false;
  in.config.musicEnabled = false;
  for (int i = 0; i < AUTO_SCHEDULED_COUNT; ++i) in.config.scheduled[i].enabled = false;
  in.approvalNeeded = true;
  in.claudeWorking = true;
  in.codexWorking = true;
  in.musicPlaying = true;
  in.dueMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE | AUTO_DUE_STOCK | AUTO_DUE_NET;
  in.validMask = in.dueMask;

  assert(chooseAutoDisplay(in) == AUTO_IDLE);
}

void testDisabledQuoteIsNeverSelected() {
  AutoSelectionInputs in{};
  in.config.scheduled[AUTO_SCHEDULED_QUOTE].enabled = false;
  in.dueMask = AUTO_DUE_QUOTE;
  in.validMask = AUTO_DUE_QUOTE;

  assert(chooseAutoDisplay(in) == AUTO_IDLE);
}

void testEnabledValidQuoteIsSelectedWhenDue() {
  AutoSelectionInputs in{};
  in.dueMask = AUTO_DUE_QUOTE;
  in.validMask = AUTO_DUE_QUOTE;

  assert(chooseAutoDisplay(in) == AUTO_QUOTE);
}

void testInvalidQuoteFallsBackToAnotherDuePage() {
  AutoSelectionInputs in{};
  in.dueMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE;
  in.validMask = AUTO_DUE_WEATHER;

  assert(chooseAutoDisplay(in) == AUTO_WEATHER);
}

void testInvalidRangesAreClampedWithoutMutatingInput() {
  AutoDisplayConfig input{};
  input.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds = -20;
  input.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds = 999;
  input.scheduled[AUTO_SCHEDULED_QUOTE].intervalSeconds = 20000;
  input.scheduled[AUTO_SCHEDULED_QUOTE].durationSeconds = 1;

  const AutoDisplayConfig normalized = normalizeAutoDisplayConfig(input);

  assert(normalized.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == 60);
  assert(normalized.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds == 60);
  assert(normalized.scheduled[AUTO_SCHEDULED_QUOTE].intervalSeconds == 14400);
  assert(normalized.scheduled[AUTO_SCHEDULED_QUOTE].durationSeconds == 5);
  assert(input.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == -20);
}

void testMissingPatchFieldsUseDefaults() {
  AutoDisplayConfigPatch patch{};
  patch.claudeEnabled = AutoConfigField<bool>{true, true};
  patch.scheduled[AUTO_SCHEDULED_WEATHER].enabled = AutoConfigField<bool>{true, false};

  const AutoDisplayConfig config = applyAutoDisplayConfigPatch(patch);

  assert(config.claudeEnabled);
  assert(config.codexEnabled);
  assert(config.musicEnabled);
  assert(!config.scheduled[AUTO_SCHEDULED_WEATHER].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == 900);
  assert(config.scheduled[AUTO_SCHEDULED_QUOTE].durationSeconds == 12);
}

void testInvalidPatchFieldsUseDefaults() {
  AutoDisplayConfigPatch patch{};
  patch.musicEnabled = AutoConfigField<bool>{false, false};
  patch.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds = AutoConfigField<int>{false, 1};
  patch.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds = AutoConfigField<int>{true, 2};

  const AutoDisplayConfig config = applyAutoDisplayConfigPatch(patch);

  assert(config.musicEnabled);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == 900);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds == 5);
}

void testRepeatedRevisionIsIgnored() {
  AutoDisplayRuntimeState runtime{};
  AutoDisplayConfigPatch first{};
  first.codexEnabled = AutoConfigField<bool>{true, false};
  assert(applyAutoDisplayRevision(runtime, 7, first));
  runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs = 1234;

  AutoDisplayConfigPatch repeated{};
  repeated.codexEnabled = AutoConfigField<bool>{true, true};
  assert(!applyAutoDisplayRevision(runtime, 7, repeated));

  assert(!runtime.config.codexEnabled);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs == 1234);
}

void testInterruptedPageRestartsWithFullDuration() {
  AutoDisplayRuntimeState runtime{};
  runtime.activeScheduledPage = AUTO_SCHEDULED_WEATHER;
  runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs = 1000;
  runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs = 6000;

  AutoTransitionInputs input{};
  input.nowMs = 2000;
  input.validMask = AUTO_DUE_WEATHER;
  input.approvalNeeded = true;
  assert(advanceAutoDisplay(runtime, input) == AUTO_APPROVAL);
  assert(runtime.activeScheduledPage == AUTO_SCHEDULED_WEATHER);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs == 1000);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs == 0);

  input.nowMs = 3000;
  input.approvalNeeded = false;
  assert(advanceAutoDisplay(runtime, input) == AUTO_WEATHER);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs == 1000);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs == 0);

  // A slow redraw after the interruption must not consume display time.
  assert(autoScheduledPageBecameVisible(runtime, AUTO_WEATHER, 5000));
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs == 15000);
  assert(!autoScheduledPageBecameVisible(runtime, AUTO_WEATHER, 6000));
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs == 15000);
}

void testScheduledDeadlineStartsAfterFirstSuccessfulDraw() {
  AutoDisplayRuntimeState runtime{};
  runtime.scheduled[AUTO_SCHEDULED_QUOTE].dueMs = 1000;

  AutoTransitionInputs input{};
  input.nowMs = 1000;
  input.validMask = AUTO_DUE_QUOTE;
  assert(advanceAutoDisplay(runtime, input) == AUTO_QUOTE);
  assert(runtime.activeScheduledPage == AUTO_SCHEDULED_QUOTE);
  assert(runtime.scheduled[AUTO_SCHEDULED_QUOTE].untilMs == 0);
  assert(runtime.scheduled[AUTO_SCHEDULED_QUOTE].lastShownOrder == 0);

  // Simulate a three-second bitmap transfer before the first visible pixel.
  assert(autoScheduledPageBecameVisible(runtime, AUTO_QUOTE, 4000));
  assert(runtime.scheduled[AUTO_SCHEDULED_QUOTE].untilMs == 16000);
  assert(runtime.scheduled[AUTO_SCHEDULED_QUOTE].lastShownOrder == 1);

  input.nowMs = 15999;
  assert(advanceAutoDisplay(runtime, input) == AUTO_QUOTE);
  input.nowMs = 16000;
  assert(advanceAutoDisplay(runtime, input) == AUTO_IDLE);
}

void testSerialMetadataCannotConfirmOrResetHTTPBitmapTransport() {
  QuoteBitmapFetchState state{};

  noteQuoteMetadataReceived(state, QUOTE_METADATA_SERIAL);
  assert(state.httpReachability == QUOTE_HTTP_UNKNOWN);
  assert(!quoteBitmapFetchAllowed(state, 100));

  noteQuoteMetadataReceived(state, QUOTE_METADATA_HTTP);
  assert(state.httpReachability == QUOTE_HTTP_CONFIRMED);
  assert(quoteBitmapFetchAllowed(state, 100));
  noteQuoteBitmapFetchFailure(state, 100);
  const uint32_t retryAfter = state.retryAfterMs;
  assert(!quoteBitmapFetchAllowed(state, retryAfter - 1));

  noteQuoteMetadataReceived(state, QUOTE_METADATA_SERIAL);
  assert(state.failureCount == 1);
  assert(state.retryAfterMs == retryAfter);
  assert(!quoteBitmapFetchAllowed(state, retryAfter - 1));
  assert(quoteBitmapFetchAllowed(state, retryAfter));

  noteQuoteBitmapFetchSuccess(state);
  assert(state.failureCount == 0);
  assert(state.retryAfterMs == 0);
  assert(quoteBitmapFetchAllowed(state, retryAfter));

  resetQuoteBitmapFetchState(state);
  noteQuoteHTTPReachable(state);
  assert(quoteBitmapFetchAllowed(state, retryAfter));
}

void testWiredSerialFirstQuoteAllowsHTTPBootstrapProbe() {
  QuoteBitmapFetchState state{};
  noteQuoteMetadataReceived(state, QUOTE_METADATA_SERIAL);
  assert(!quoteBitmapFetchAllowed(state, 100));

  QuoteMetadataPollInputs input{};
  input.wifiConnected = true;
  input.bridgeConfigured = true;
  input.modeNeedsQuote = true;
  input.wiredActive = true;
  assert(!shouldPollQuoteMetadataHTTP(input, state, 100));

  input.intervalElapsed = true;
  assert(shouldPollQuoteMetadataHTTP(input, state, 100));

  noteQuoteMetadataReceived(state, QUOTE_METADATA_HTTP);
  assert(state.httpReachability == QUOTE_HTTP_CONFIRMED);
  assert(quoteBitmapFetchAllowed(state, 100));
  assert(!shouldPollQuoteMetadataHTTP(input, state, 100));
}

void testFailedHTTPReachabilityProbeObeysBackoff() {
  QuoteBitmapFetchState state{};
  noteQuoteHTTPMetadataFailure(state, 100);
  assert(state.httpReachability == QUOTE_HTTP_FAILED);
  assert(state.failureCount == 1);
  assert(state.retryAfterMs == 5100);

  QuoteMetadataPollInputs input{};
  input.wifiConnected = true;
  input.bridgeConfigured = true;
  input.modeNeedsQuote = true;
  input.intervalElapsed = true;
  input.wiredActive = true;
  assert(!shouldPollQuoteMetadataHTTP(input, state, 5099));
  assert(shouldPollQuoteMetadataHTTP(input, state, 5100));
}

void testSerialMetadataPreservesHTTPFailureUntilHTTPConfirmsReachability() {
  QuoteBitmapFetchState state{};
  noteQuoteHTTPMetadataFailure(state, 100);
  const uint32_t retryAfter = state.retryAfterMs;

  noteQuoteMetadataReceived(state, QUOTE_METADATA_SERIAL);
  assert(state.httpReachability == QUOTE_HTTP_FAILED);
  assert(state.failureCount == 1);
  assert(state.retryAfterMs == retryAfter);
  assert(!quoteBitmapFetchAllowed(state, retryAfter - 1));

  noteQuoteMetadataReceived(state, QUOTE_METADATA_HTTP);
  assert(state.httpReachability == QUOTE_HTTP_CONFIRMED);
  assert(state.failureCount == 1);
  assert(state.retryAfterMs == retryAfter);
  assert(!quoteBitmapFetchAllowed(state, retryAfter - 1));
  assert(quoteBitmapFetchAllowed(state, retryAfter));
}

void testUnwiredQuoteMetadataRefreshKeepsItsIntervalPolicy() {
  QuoteBitmapFetchState state{};
  noteQuoteHTTPReachable(state);

  QuoteMetadataPollInputs input{};
  input.wifiConnected = true;
  input.bridgeConfigured = true;
  input.modeNeedsQuote = true;
  input.wiredActive = false;
  assert(!shouldPollQuoteMetadataHTTP(input, state, 100));

  input.intervalElapsed = true;
  assert(shouldPollQuoteMetadataHTTP(input, state, 100));
}

void testFixedModeDoesNotRunAutoScheduler() {
  AutoDisplayRuntimeState runtime{};
  runtime.activeScheduledPage = AUTO_SCHEDULED_QUOTE;
  runtime.scheduled[AUTO_SCHEDULED_QUOTE].dueMs = 1000;
  runtime.scheduled[AUTO_SCHEDULED_QUOTE].untilMs = 6000;
  runtime.scheduled[AUTO_SCHEDULED_QUOTE].lastShownOrder = 3;
  runtime.lastShownOrder = 3;

  AutoTransitionInputs input{};
  input.autoMode = false;
  input.nowMs = 7000;
  input.validMask = AUTO_DUE_QUOTE;
  input.approvalNeeded = true;

  assert(advanceAutoDisplay(runtime, input) == AUTO_IDLE);
  assert(runtime.activeScheduledPage == AUTO_SCHEDULED_QUOTE);
  assert(runtime.scheduled[AUTO_SCHEDULED_QUOTE].dueMs == 1000);
  assert(runtime.scheduled[AUTO_SCHEDULED_QUOTE].untilMs == 6000);
  assert(runtime.scheduled[AUTO_SCHEDULED_QUOTE].lastShownOrder == 3);
  assert(runtime.lastShownOrder == 3);
}

void testNowLayoutRevisionInvalidatesDisplayedBitmap() {
  const NowPageRevision current{37, 1};
  const NowPageRevision same{37, 1};
  const NowPageRevision newLayout{37, 2};

  assert(!nowPageRevisionChanged(true, current, same));
  assert(nowPageRevisionChanged(true, current, newLayout));
  assert(nowPageFrameIsCurrent(true, current, same, false));
  assert(!nowPageFrameIsCurrent(true, current, newLayout, false));
}

int main() {
  testLegacyBridgeDefaults();
  testClaudeCanBeDisabled();
  testApprovalsCanBeDisabled();
  testAutoAgentSelectionPinsOnlyEnabledCodexWhileIdle();
  testAutoAgentSelectionPinsOnlyEnabledClaudeWhileIdle();
  testBothEnabledIdleAgentsKeepSlowAlternation();
  testOnlyEnabledWorkingAgentIsSelected();
  testExactlyOneWorkingOfBothEnabledAgentsIsSelected();
  testBothEnabledWorkingAgentsKeepFastAlternation();
  testFixedAgentDisplayIgnoresAutoEnablementAndActivity();
  testApprovalSwitchIndependentlyAllowsRequestingDisabledAgent();
  testNoEnabledAgentKeepsCurrentIdlePet();
  testPriorityAndFairScheduledChoice();
  testAllItemsCanBeDisabled();
  testDisabledQuoteIsNeverSelected();
  testEnabledValidQuoteIsSelectedWhenDue();
  testInvalidQuoteFallsBackToAnotherDuePage();
  testInvalidRangesAreClampedWithoutMutatingInput();
  testMissingPatchFieldsUseDefaults();
  testInvalidPatchFieldsUseDefaults();
  testRepeatedRevisionIsIgnored();
  testInterruptedPageRestartsWithFullDuration();
  testScheduledDeadlineStartsAfterFirstSuccessfulDraw();
  testSerialMetadataCannotConfirmOrResetHTTPBitmapTransport();
  testWiredSerialFirstQuoteAllowsHTTPBootstrapProbe();
  testFailedHTTPReachabilityProbeObeysBackoff();
  testSerialMetadataPreservesHTTPFailureUntilHTTPConfirmsReachability();
  testUnwiredQuoteMetadataRefreshKeepsItsIntervalPolicy();
  testFixedModeDoesNotRunAutoScheduler();
  testNowLayoutRevisionInvalidatesDisplayedBitmap();
  return 0;
}
